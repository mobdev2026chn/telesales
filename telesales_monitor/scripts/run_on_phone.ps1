# Runs the debug app on a USB-connected phone (or emulator) against the local backend.
# Forwards the device's port 5000 to this PC (adb reverse), so the app's default debug URL
# http://127.0.0.1:5000/api reaches the backend without Wi-Fi, LAN IPs or firewall rules.
# Extra arguments are passed to `flutter run`, e.g. .\scripts\run_on_phone.ps1 -d <device-id>
$ErrorActionPreference = 'Stop'

function Find-Tool([string]$name, [string[]]$candidates) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    throw "$name was not found. Add it to PATH."
}

$adb = Find-Tool 'adb' @(
    $(if ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe' }),
    $(if ($env:ANDROID_SDK_ROOT) { Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe' }),
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')
)
$flutter = Find-Tool 'flutter' @('E:\flutter\bin\flutter.bat', 'C:\flutter\bin\flutter.bat', 'C:\src\flutter\bin\flutter.bat')

$healthUrl = 'http://localhost:5000/api/health'
try {
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 5
    if ($health.success -ne $true) { throw 'Unexpected health response.' }
}
catch {
    throw "The backend is not answering at $healthUrl. Start it first: cd backend; npm run dev. Details: $($_.Exception.Message)"
}

Write-Host "Using adb: $adb"
# The device can show as unauthorized/offline for a few seconds after plugging in or accepting the prompt
$devices = $null
for ($attempt = 1; $attempt -le 10 -and -not $devices; $attempt++) {
    $listed = & $adb devices | Select-Object -Skip 1 | Where-Object { $_.Trim() }
    $devices = $listed | Where-Object { $_ -match '\sdevice$' }
    if (-not $devices) {
        if ($attempt -eq 1) { Write-Host 'Waiting for the phone (unlock it and tap "Allow" on the USB debugging prompt)...' }
        Start-Sleep -Seconds 2
    }
}
if (-not $devices) {
    $seen = if ($listed) { ($listed -join '; ') } else { 'nothing' }
    throw "No ready device found (adb sees: $seen). 'unauthorized' = tap Allow on the phone's USB debugging prompt; 'offline' or nothing = replug the cable, set USB mode to File transfer, or run: & `"$adb`" kill-server"
}

# Forward on every connected device (the forward resets when the cable is unplugged)
foreach ($line in $devices) {
    $serial = ($line -split '\s+')[0]
    & $adb -s $serial reverse tcp:5000 tcp:5000 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "adb reverse failed on $serial." }
    Write-Host "Device $serial -> backend: phone 127.0.0.1:5000 forwards to this PC's port 5000"
}

Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & $flutter run @args
}
finally {
    Pop-Location
}
