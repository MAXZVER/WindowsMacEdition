#Requires -Version 5.1
<#
.SYNOPSIS
    Installs a visual style into the user profile instead of
    C:\Windows\Resources\Themes, so no administrator rights are needed.
.DESCRIPTION
    Theme authors write their .theme files assuming the system folder, using
    %SystemRoot%\Resources\Themes and %ResourceDir%\Themes. This copies the
    theme under %LOCALAPPDATA%\Microsoft\Windows\Themes and rewrites those
    paths to point there.

    It also keeps the wallpaper you already have: applying a theme would
    otherwise replace it, and this one points at a Previews folder that is not
    even in the package.
.PARAMETER Source
    Folder holding the unpacked theme (the one containing the .theme files).
.PARAMETER Name
    Name of the theme folder inside the package, e.g. 'macOS Tahoe'.
.PARAMETER KeepWallpaper
    Keep the wallpaper currently set instead of the one the theme carries.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Name,
    [switch]$KeepWallpaper
)

$ErrorActionPreference = 'Stop'

$userThemes = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes'
$target     = Join-Path $userThemes $Name
New-Item -ItemType Directory -Force -Path $userThemes | Out-Null

$srcFolder = Join-Path $Source $Name
if (-not (Test-Path $srcFolder)) { throw "Theme folder not found: $srcFolder" }

if (Test-Path $target) { Remove-Item $target -Recurse -Force }
Copy-Item $srcFolder $target -Recurse -Force
Write-Host "Copied resources to $target"

$currentWallpaper = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper

$installed = @()
foreach ($themeFile in Get-ChildItem $Source -Filter '*.theme') {
    $text = Get-Content $themeFile.FullName -Raw

    # Point every system path at the copy inside the profile. Plain string
    # replacement, not -replace: regex escaping mangles the space in a theme
    # name like "macOS Tahoe" into "macOS\ Tahoe".
    $text = $text.Replace("%SystemRoot%\Resources\Themes\$Name", $target)
    $text = $text.Replace("%ResourceDir%\Themes\$Name",          $target)

    if ($KeepWallpaper -and $currentWallpaper) {
        $text = $text -replace '(?m)^Wallpaper=.*$', "Wallpaper=$currentWallpaper"
        # the slideshow section would override the wallpaper again
        $text = $text -replace '(?ms)\[Slideshow\].*?(?=\r?\n\[|\z)', ''
    }

    $out = Join-Path $userThemes $themeFile.Name
    Set-Content -Path $out -Value $text -Encoding Unicode
    $installed += $out
    Write-Host "Installed $($themeFile.Name)"
}

Write-Host ''
Write-Host 'Visual styles found in the package:'
Get-ChildItem $target -Filter '*.msstyles' | ForEach-Object {
    '  {0}  ({1:N0} KB)' -f $_.Name, ($_.Length / 1KB)
}

Write-Host ''
Write-Host 'Theme files ready to apply:'
$installed | ForEach-Object { "  $_" }
