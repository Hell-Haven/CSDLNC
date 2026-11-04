param([string]$Server = 'lpc:localhost')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$schema = 'verify_' + [guid]::NewGuid().ToString('N')
$connection = [System.Data.SqlClient.SqlConnection]::new("Server=$Server;Database=tempdb;Integrated Security=True;TrustServerCertificate=True;Connect Timeout=5")
$transaction = $null
$schemaCreated = $false
function Invoke-TestSql([string]$Text) {
    $command = $connection.CreateCommand()
    $command.Transaction = $transaction
    $command.CommandTimeout = 30
    $command.CommandText = $Text
    try { return $command.ExecuteScalar() } finally { $command.Dispose() }
}
function Invoke-Batches([string]$Text) {
    $textInSchema = $Text.Replace('dbo.', "[$schema].").Replace('USE LibraryCompare;', '')
    foreach ($batch in [regex]::Split($textInSchema, '(?m)^\s*GO\s*$')) {
        if (-not [string]::IsNullOrWhiteSpace($batch)) { Invoke-TestSql $batch | Out-Null }
    }
}
try {
    $connection.Open()
    Invoke-TestSql "CREATE SCHEMA [$schema]" | Out-Null
    $schemaCreated = $true
    $schemaText = [System.IO.File]::ReadAllText((Join-Path $workspace 'sqlserver\01_schema.sql'))
    # Skip CREATE DATABASE and the initial one-time guard. All objects below
    # exist only in a unique tempdb schema, removed in finally. Type metadata
    # must be committed before TVP use to avoid SQL Server metadata deadlocks.
    $schemaText = $schemaText.Substring($schemaText.IndexOf('CREATE TABLE dbo.Publishers'))
    Invoke-Batches $schemaText
    $transaction = $connection.BeginTransaction()
    Invoke-Batches ([System.IO.File]::ReadAllText((Join-Path $workspace 'sqlserver\02_seed.sql')))
    $count = Invoke-TestSql "SELECT COUNT(*) FROM [$schema].Books"
    $copies = Invoke-TestSql "SELECT SUM(TotalCopies) FROM [$schema].Books"
    if ($count -ne 8 -or $copies -ne 72) { throw 'Seed mismatch.' }
    Invoke-TestSql @"
DECLARE @Items [$schema].BookRequest;
INSERT @Items VALUES('B001',2),('B002',1);
DECLARE @Due datetime2=DATEADD(day,14,SYSUTCDATETIME());
EXEC [$schema].BorrowBooks 'VERIFY_LOAN','R001','S001',@Due,@Items;
"@ | Out-Null
    if ((Invoke-TestSql "SELECT AvailableCopies FROM [$schema].Books WHERE BookCode='B001'") -ne 10) { throw 'Borrow stock mismatch.' }
    Invoke-TestSql @"
DECLARE @Items [$schema].BookRequest;
INSERT @Items VALUES('B001',1);
EXEC [$schema].ReturnBooks 'VERIFY_LOAN',@Items;
"@ | Out-Null
    if ((Invoke-TestSql "SELECT Status FROM [$schema].Loans WHERE LoanCode='VERIFY_LOAN'") -ne 'BORROWING') { throw 'Partial return status mismatch.' }
    if ((Invoke-TestSql "SELECT AvailableCopies FROM [$schema].Books WHERE BookCode='B001'") -ne 11) { throw 'Partial return stock mismatch.' }
    Invoke-TestSql @"
DECLARE @Items [$schema].BookRequest;
INSERT @Items VALUES('B001',1),('B002',1);
EXEC [$schema].ReturnBooks 'VERIFY_LOAN',@Items;
"@ | Out-Null
    if ((Invoke-TestSql "SELECT Status FROM [$schema].Loans WHERE LoanCode='VERIFY_LOAN'") -ne 'RETURNED') { throw 'Final return status mismatch.' }
    if ((Invoke-TestSql "SELECT SUM(AvailableCopies) FROM [$schema].Books") -ne 72) { throw 'Final stock mismatch.' }
    $compareText = [System.IO.File]::ReadAllText((Join-Path $workspace 'sqlserver\03_compare.sql'))
    Invoke-Batches $compareText.Substring(0,$compareText.IndexOf('-- CRUD'))
    $transaction.Rollback()
    $transaction.Dispose()
    $transaction = $null
    Write-Output 'PASS: schema, identical seed (8 titles / 72 copies), comparison SELECTs, multi-book borrow, partial/full return. Test data rolled back.'
} finally {
    if ($null -ne $transaction) { try { $transaction.Rollback() } catch {} ; $transaction.Dispose() }
    $transaction = $null
    if ($schemaCreated -and $connection.State -eq 'Open') {
        Invoke-TestSql @"
DROP PROCEDURE IF EXISTS [$schema].BorrowBooks;
DROP PROCEDURE IF EXISTS [$schema].ReturnBooks;
DROP TABLE IF EXISTS [$schema].LoanItems, [$schema].BookAuthors, [$schema].Loans;
DROP TABLE IF EXISTS [$schema].Books, [$schema].Readers, [$schema].Staff, [$schema].Publishers;
IF TYPE_ID(N'$schema.BookRequest') IS NOT NULL DROP TYPE [$schema].BookRequest;
DROP SCHEMA [$schema];
"@ | Out-Null
        Write-Output 'Cleanup complete: test schema and all its objects removed from tempdb.'
    }
    $connection.Dispose()
}
