# Builds the Play Store phone screenshots (1080 x 1920, 24-bit PNG) in store_listing/screenshots/
# from the phone screenshots in source/screens/, using screenshot.html + screenshots-config.js.
# Run: powershell -ExecutionPolicy Bypass -File store_listing\source\render-screenshots.ps1 [-Debug]
#   -Debug writes *-debug.png files that outline the text each replacement found, instead.
param([switch]$Debug)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sourceDir = $PSScriptRoot
$outDir = Join-Path (Split-Path -Parent $sourceDir) 'screenshots'
New-Item -ItemType Directory -Force $outDir | Out-Null
# The folder holds only rendered files: start clean so renamed shots don't leave old copies behind.
Get-ChildItem $outDir -Filter *.png | Remove-Item

# Screenshots as data URIs, so the page can read their pixels (file:// images can't be read back).
$entries = Get-ChildItem (Join-Path $sourceDir 'screens') -Filter *.jpg | ForEach-Object {
    "  '{0}': 'data:image/jpeg;base64,{1}'," -f $_.BaseName, [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName))
}
$dataJs = "window.SCREENS = {`n" + ($entries -join "`n") + "`n};`n"
[IO.File]::WriteAllText((Join-Path $sourceDir 'screens-data.js'), $dataJs, (New-Object Text.UTF8Encoding($false)))

$browser = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { throw 'Chrome or Edge is needed.' }

$config = Get-Content (Join-Path $sourceDir 'screenshots-config.js') -Raw
$shots = [regex]::Matches($config, "(?m)^\s+'?([a-z-]+)'?: \{\s*\r?\n\s*image: '([^']+)', file: '([^']+)'") |
    ForEach-Object { @{ key = $_.Groups[1].Value; image = $_.Groups[2].Value; file = $_.Groups[3].Value } }
if (-not $shots) { throw 'No shots found in screenshots-config.js.' }
$missing = $shots | Where-Object { -not (Test-Path (Join-Path $sourceDir "screens\$($_.image).jpg")) }
foreach ($s in $missing) { Write-Host "skipped $($s.file): screens\$($s.image).jpg not found" }
$shots = $shots | Where-Object { Test-Path (Join-Path $sourceDir "screens\$($_.image).jpg") }

$html = 'file:///' + ((Join-Path $sourceDir 'screenshot.html') -replace '\\', '/' -replace ' ', '%20')
$profileDir = Join-Path ([IO.Path]::GetTempPath()) 'askeva-render-profile'
foreach ($s in $shots) {
    $name = if ($Debug) { "$($s.file)-debug" } else { $s.file }
    $raw = Join-Path ([IO.Path]::GetTempPath()) "askeva-$name-raw.png"
    Remove-Item $raw -ErrorAction SilentlyContinue
    $url = "$html`?shot=$($s.key)" + $(if ($Debug) { '&debug' } else { '' })
    $browserArgs = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
        '--window-size=1080,1920', '--virtual-time-budget=10000', '--allow-file-access-from-files',
        "`"--user-data-dir=$profileDir`"", "`"--screenshot=$raw`"", "`"$url`"")
    Start-Process -FilePath $browser -ArgumentList $browserArgs -Wait -NoNewWindow -RedirectStandardError (Join-Path ([IO.Path]::GetTempPath()) 'askeva-render-err.txt')
    if (-not (Test-Path $raw)) { throw "The browser did not save $name." }

    # Play needs JPEG or 24-bit PNG (no transparency).
    $src = [System.Drawing.Image]::FromFile($raw)
    $bmp = New-Object System.Drawing.Bitmap(1080, 1920, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.DrawImage($src, 0, 0, 1080, 1920)
    $g.Dispose(); $src.Dispose()
    $target = Join-Path $outDir "$name.png"
    $bmp.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Remove-Item $raw
    Write-Host ("{0}.png  {1:N0} KB" -f $name, ((Get-Item $target).Length / 1KB))
}
