param(
    [ValidateSet('mongodb', 'sqlserver')][string]$Database = 'mongodb',
    [ValidateRange(1, 65535)][int]$WebPort = 5173
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$apiPort = if ($Database -eq 'sqlserver') { 8081 } else { 8080 }
Push-Location (Join-Path $projectRoot 'library_app')
try {
    & flutter run -d chrome "--web-port=$WebPort" "--dart-define=API_URL=http://localhost:$apiPort"
    if ($LASTEXITCODE -ne 0) { throw 'Flutter failed. See the message above.' }
} finally { Pop-Location }
