param(
    [ValidateSet('mongodb', 'sqlserver')][string]$Database = 'mongodb',
    [switch]$Setup
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$backendFolder = if ($Database -eq 'sqlserver') { 'server-sql' } else { 'server' }
Push-Location (Join-Path $projectRoot $backendFolder)
try {
    if ($Setup) {
        if ($Database -ne 'sqlserver') { throw '-Setup is supported for sqlserver only.' }
        & npm run setup
        if ($LASTEXITCODE -ne 0) { throw 'SQL Server setup failed.' }
    }
    & npm start
    if ($LASTEXITCODE -ne 0) { throw 'Backend failed. See the message above.' }
} finally { Pop-Location }
