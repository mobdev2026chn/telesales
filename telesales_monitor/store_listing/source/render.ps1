# Builds the Play Store images in store_listing/:
#   icon-512.png             512 x 512, 32-bit PNG (from assets/images/ask_eva_logo.png, the launcher icon)
#   feature-graphic.png      1024 x 500, 24-bit PNG, no transparency (rendered from feature-graphic.html)
# Run: powershell -ExecutionPolicy Bypass -File store_listing\source\render.ps1   (needs Chrome or Edge, and internet for the fonts)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sourceDir = $PSScriptRoot
$outDir = Split-Path -Parent $sourceDir
$appDir = Split-Path -Parent $outDir

function Save-Resized([string]$from, [string]$to, [int]$w, [int]$h, [System.Drawing.Imaging.PixelFormat]$format) {
    $src = [System.Drawing.Image]::FromFile($from)
    try {
        $bmp = New-Object System.Drawing.Bitmap($w, $h, $format)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.DrawImage($src, 0, 0, $w, $h)
        $g.Dispose()
        $bmp.Save($to, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    } finally { $src.Dispose() }
}

# App icon
Save-Resized (Join-Path $appDir 'assets\images\ask_eva_logo.png') (Join-Path $outDir 'icon-512.png') 512 512([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

# Feature graphic
$browser = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { throw 'Chrome or Edge is needed to render the feature graphic.' }

$html = Join-Path $sourceDir 'feature-graphic.html'
$shot = Join-Path ([IO.Path]::GetTempPath()) 'askeva-feature-graphic-raw.png'
$profileDir = Join-Path ([IO.Path]::GetTempPath()) 'askeva-render-profile'
Remove-Item $shot -ErrorAction SilentlyContinue
$url = 'file:///' + (($html -replace '\\', '/') -replace ' ', '%20')
$browserArgs = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
          '--window-size=1024,500', '--virtual-time-budget=8000', '--allow-file-access-from-files',
          "`"--user-data-dir=$profileDir`"", "`"--screenshot=$shot`"", "`"$url`"")
Start-Process -FilePath $browser -ArgumentList $browserArgs -Wait -NoNewWindow
if (-not (Test-Path $shot)) { throw 'The browser did not save a screenshot.' }

Save-Resized $shot (Join-Path $outDir 'feature-graphic.png') 1024 500 ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
Remove-Item $shot

foreach ($f in 'icon-512.png', 'feature-graphic.png') {
    $p = Join-Path $outDir $f
    $img = [System.Drawing.Image]::FromFile($p)
    Write-Host ("{0}: {1} x {2}, {3}, {4:N0} KB" -f $f, $img.Width, $img.Height, $img.PixelFormat, ((Get-Item $p).Length / 1KB))
    $img.Dispose()
}
