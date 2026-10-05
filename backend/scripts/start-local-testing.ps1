$ErrorActionPreference = 'Stop'

$mongoAvailable = Test-NetConnection -ComputerName 127.0.0.1 -Port 27017 -InformationLevel Quiet -WarningAction SilentlyContinue
if (-not $mongoAvailable) {
    throw 'Local MongoDB is not listening on 127.0.0.1:27017. Start MongoDB before starting the testing backend.'
}

$env:NODE_ENV = 'development'
$env:PORT = '5000'
$env:MONGODB_URI = 'mongodb://127.0.0.1:27017/telesales_db'

Write-Host 'Starting local testing backend: http://0.0.0.0:5000/api'
Write-Host 'MongoDB target: mongodb://127.0.0.1:27017/telesales_db'

Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & npm run dev
    if ($LASTEXITCODE -ne 0) {
        throw "Backend exited with code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
