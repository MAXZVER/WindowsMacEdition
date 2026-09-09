#Requires -Version 5.1
<#
.SYNOPSIS
    Crops an image to the target aspect ratio from the centre, then scales it
    to the exact target size. No stretching.
.EXAMPLE
    .\fit-wallpaper.ps1 -Path .\15-Sequoia-Dark-6K.jpg
    .\fit-wallpaper.ps1 -Path .\*.png -Width 1600 -Height 675 -OutDir .\preview
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Path,
    [int]$Width  = 5120,
    [int]$Height = 2160,
    [string]$OutDir,
    [string]$Suffix,
    [int]$Quality = 95
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $OutDir)  { $OutDir  = Join-Path $PSScriptRoot 'fitted' }
if (-not $Suffix)  { $Suffix  = "_${Width}x${Height}" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
             Where-Object { $_.MimeType -eq 'image/jpeg' }
$encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
    [System.Drawing.Imaging.Encoder]::Quality, [int64]$Quality)

$targetAspect = $Width / $Height

foreach ($item in (Get-ChildItem -Path $Path -File)) {
    $src = $null; $dst = $null; $g = $null
    try {
        $src = [System.Drawing.Image]::FromFile($item.FullName)

        # centre crop to the target aspect ratio
        $srcAspect = $src.Width / $src.Height
        if ($srcAspect -gt $targetAspect) {
            $cropH = $src.Height
            $cropW = [int][math]::Round($src.Height * $targetAspect)
        } else {
            $cropW = $src.Width
            $cropH = [int][math]::Round($src.Width / $targetAspect)
        }
        $cropX = [int][math]::Round(($src.Width  - $cropW) / 2)
        $cropY = [int][math]::Round(($src.Height - $cropH) / 2)
        $srcRect = New-Object System.Drawing.Rectangle($cropX, $cropY, $cropW, $cropH)

        $dst = New-Object System.Drawing.Bitmap($Width, $Height)
        $dst.SetResolution($src.HorizontalResolution, $src.VerticalResolution)

        $g = [System.Drawing.Graphics]::FromImage($dst)
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $dstRect = New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)
        $g.DrawImage($src, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)

        $out = Join-Path $OutDir ($item.BaseName + $Suffix + '.jpg')
        $dst.Save($out, $jpegCodec, $encParams)

        $kept = [math]::Round(100 * $cropH / $src.Height)
        '{0,-28} {1}x{2} -> {3}x{4}  (kept {5}% of height)  {6:N1} MB' -f `
            $item.Name, $src.Width, $src.Height, $Width, $Height, $kept, ((Get-Item $out).Length/1MB)
    }
    finally {
        if ($g)   { $g.Dispose() }
        if ($dst) { $dst.Dispose() }
        if ($src) { $src.Dispose() }
    }
}
Write-Host ''
Write-Host "Output: $OutDir"
