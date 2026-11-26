# Changes the Play Store upload key's password: re-locks android/upload-keystore.jks with the new
# password and writes it to android/key.properties, so release builds keep signing.
# Run it yourself in a terminal (it asks for the password; nothing is shown or logged):
#   powershell -ExecutionPolicy Bypass -File scripts\set_upload_key_password.ps1

$ErrorActionPreference = 'Stop'

$androidDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'android'
$propsPath = Join-Path $androidDir 'key.properties'
$keystorePath = Join-Path $androidDir 'upload-keystore.jks'
$backupPath = Join-Path $androidDir 'upload-keystore.backup.jks'

foreach ($p in @($propsPath, $keystorePath)) {
    if (-not (Test-Path $p)) { throw "Not found: $p" }
}

$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytool -and $env:JAVA_HOME) { $keytool = Join-Path $env:JAVA_HOME 'bin\keytool.exe' }
if (-not $keytool -or -not (Test-Path $keytool)) { throw 'keytool not found: add the JDK bin folder to PATH or set JAVA_HOME.' }

$lines = [IO.File]::ReadAllLines($propsPath)
$oldLine = $lines | Where-Object { $_ -match '^storePassword=' } | Select-Object -First 1
if (-not $oldLine) { throw 'key.properties has no storePassword line.' }
$oldPassword = ($oldLine -replace '^storePassword=', '') -replace '\\\\', '\'

function Read-Plain([string]$prompt) {
    $secure = Read-Host -Prompt $prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$new = Read-Plain 'New password (at least 8 characters)'
$confirm = Read-Plain 'Type it again'
if ($new -cne $confirm) { throw 'The two passwords do not match. Nothing was changed.' }
if ($new.Length -lt 8) { throw 'Use at least 8 characters. Nothing was changed.' }
if ($new -ne $new.Trim()) { throw 'The password cannot start or end with a space. Nothing was changed.' }
if ($new -match '[^\x20-\x7E]') { throw 'Use only English letters, digits, spaces and symbols. Nothing was changed.' }

Copy-Item $keystorePath $backupPath -Force
try {
    # Passwords go to keytool through environment variables, never on the command line.
    $env:ASKEVA_OLD_PW = $oldPassword
    $env:ASKEVA_NEW_PW = $new
    & $keytool -storepasswd -keystore $keystorePath -storepass:env ASKEVA_OLD_PW -new:env ASKEVA_NEW_PW
    if ($LASTEXITCODE -ne 0) { throw 'keytool could not change the password (is key.properties still correct?).' }
    & $keytool -list -keystore $keystorePath -alias upload -storepass:env ASKEVA_NEW_PW | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The new password did not open the keystore.' }

    # key.properties is a Java properties file: a backslash must be written as two.
    $escaped = $new -replace '\\', '\\'
    $updated = foreach ($line in $lines) {
        if ($line -match '^storePassword=') { "storePassword=$escaped" }
        elseif ($line -match '^keyPassword=') { "keyPassword=$escaped" }
        else { $line }
    }
    [IO.File]::WriteAllLines($propsPath, [string[]]$updated, (New-Object Text.UTF8Encoding($false)))
    Remove-Item $backupPath -Force
    Write-Host 'Password changed. Back up android\upload-keystore.jks and keep the new password safe.'
}
catch {
    Copy-Item $backupPath $keystorePath -Force
    Remove-Item $backupPath -Force
    Write-Host 'Restored the keystore as it was; the old password still works.'
    throw
}
finally {
    Remove-Item Env:ASKEVA_OLD_PW, Env:ASKEVA_NEW_PW -ErrorAction SilentlyContinue
}
