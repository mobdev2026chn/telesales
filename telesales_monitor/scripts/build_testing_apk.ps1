param(
    [Parameter(Mandatory = $true)]
    [string]$BackendHost
)

$ErrorActionPreference = 'Stop'

$parsedAddress = $null
if (-not [System.Net.IPAddress]::TryParse($BackendHost, [ref]$parsedAddress) -or
    $parsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
    throw "BackendHost must be the PC's IPv4 address on the phone's Wi-Fi network."
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$apiUrl = "http://${BackendHost}:5000/api"
$healthUrl = "$apiUrl/health"

try {
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 5
    if ($health.success -ne $true -or $health.status -ne 'ok') {
        throw "Unexpected health response."
    }
}
catch {
    throw "The backend health check failed at $healthUrl. Start the backend on port 5000 and verify that this PC's Wi-Fi IP is correct. For phone access, keep the phone and PC on the same Wi-Fi and allow inbound TCP port 5000 through Windows Firewall. Details: $($_.Exception.Message)"
}

Push-Location $projectRoot
try {
    Write-Host "Building debug APK for local testing against $apiUrl"
    & flutter build apk --debug "--dart-define=API_URL=$apiUrl"
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
