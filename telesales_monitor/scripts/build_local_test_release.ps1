# Builds a release-mode APK with a separate local-test signing key and application ID.
# This APK is not Play Store uploadable and installs alongside the Play-signed app.
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $projectRoot 'android'
$propertiesPath = Join-Path $androidDir 'local-test-key.properties'
$keystorePath = Join-Path $androidDir 'local-test-upload.jks'

function Find-Keytool {
    $command = Get-Command keytool -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @()
    if ($env:JAVA_HOME) {
        $candidates += Join-Path $env:JAVA_HOME 'bin\keytool.exe'
    }
    if ($env:ProgramFiles) {
        $androidStudioRoot = Join-Path $env:ProgramFiles 'Android'
        if (Test-Path $androidStudioRoot) {
            $candidates += Get-ChildItem $androidStudioRoot -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName 'jbr\bin\keytool.exe' }
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    throw 'keytool was not found. Install Android Studio or set JAVA_HOME to a JDK.'
}

$hasProperties = Test-Path $propertiesPath
$hasKeystore = Test-Path $keystorePath
if ($hasProperties -xor $hasKeystore) {
    throw 'Local test signing is only partially configured. Keep both android\local-test-key.properties and android\local-test-upload.jks, or remove both and rerun this script.'
}

if (-not $hasProperties) {
    $keytool = Find-Keytool
    $randomBytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($randomBytes)
    }
    finally {
        $rng.Dispose()
    }
    $password = [Convert]::ToBase64String($randomBytes).TrimEnd('=')
    [Array]::Clear($randomBytes, 0, $randomBytes.Length)

    try {
        $env:ASKEVA_LOCAL_TEST_KEY_PASSWORD = $password
        & $keytool -genkeypair -keystore $keystorePath `
            -storepass:env ASKEVA_LOCAL_TEST_KEY_PASSWORD `
            -alias localtest -keypass:env ASKEVA_LOCAL_TEST_KEY_PASSWORD `
            -keyalg RSA -keysize 2048 -validity 10000 `
            -dname 'CN=Telesales Local Test, OU=Development, O=AskEVA, L=Chennai, ST=Tamil Nadu, C=IN'
        if ($LASTEXITCODE -ne 0) { throw 'keytool failed to create the local test keystore.' }

        $properties = @(
            'storeFile=../local-test-upload.jks'
            "storePassword=$password"
            'keyAlias=localtest'
            "keyPassword=$password"
        )
        [IO.File]::WriteAllLines($propertiesPath, $properties, (New-Object Text.UTF8Encoding($false)))
    }
    catch {
        Remove-Item $keystorePath -Force -ErrorAction SilentlyContinue
        Remove-Item $propertiesPath -Force -ErrorAction SilentlyContinue
        throw
    }
    finally {
        Remove-Item Env:ASKEVA_LOCAL_TEST_KEY_PASSWORD -ErrorAction SilentlyContinue
        $password = $null
    }
}

Push-Location $projectRoot
try {
    $previousFlag = $env:ASKEVA_LOCAL_TEST_RELEASE
    $env:ASKEVA_LOCAL_TEST_RELEASE = '1'
    try {
        & flutter build apk --release
        if ($LASTEXITCODE -ne 0) {
            throw "Local test release build failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        if ($null -eq $previousFlag) {
            Remove-Item Env:ASKEVA_LOCAL_TEST_RELEASE -ErrorAction SilentlyContinue
        } else {
            $env:ASKEVA_LOCAL_TEST_RELEASE = $previousFlag
        }
    }
}
finally {
    Pop-Location
}

Write-Host 'Local test APK built: build\app\outputs\flutter-apk\app-release.apk'
Write-Host 'Package ID: com.askeva.telesales_monitor.localtest (not for Play Store upload)'
