#Requires -Version 5.1
<#
.SYNOPSIS
    Puts the visual style into C:\Windows\Resources\Themes, where Windows
    actually loads msstyles from. Requires an elevated PowerShell.
.DESCRIPTION
    Installing into the user profile is enough for cursors, sounds and
    wallpaper, but the visual style itself is only picked up from the system
    themes folder - which is why the msstyles stayed on Aero.

    The msstyles copied here is the one already patched with ThemeTool, so no
    second patch is needed. The wallpaper you currently have is preserved
    instead of the one the theme ships.
.EXAMPLE
    # in an elevated PowerShell:
    .\install-theme-system.ps1
#>
[CmdletBinding()]
param(
    [string]$Name = 'macOS Tahoe',
    [string]$UserThemes = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes'),
    [switch]$KeepWallpaper = $true
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This needs an elevated PowerShell. Right-click PowerShell and pick "Run as administrator", then run it again.'
}

$sysThemes = Join-Path $env:SystemRoot 'Resources\Themes'
$source    = Join-Path $UserThemes $Name
$target    = Join-Path $sysThemes $Name

if (-not (Test-Path $source)) { throw "Theme folder not found: $source" }

# the patched style, as ThemeTool left it
$style = Get-ChildItem $source -Filter '*.msstyles' | Select-Object -First 1
Write-Host ("Style: {0} ({1:N0} bytes)" -f $style.Name, $style.Length)

if (Test-Path $target) {
    Write-Host "Replacing existing $target"
    Remove-Item $target -Recurse -Force
}
Copy-Item $source $target -Recurse -Force
Write-Host "Copied to $target"

$currentWallpaper = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper

foreach ($themeFile in Get-ChildItem $UserThemes -Filter "$Name*.theme") {
    $text = Get-Content $themeFile.FullName -Raw

    # point the paths back at the system folder
    $text = $text.Replace($source, "%SystemRoot%\Resources\Themes\$Name")
    $text = $text -replace '(?m)^Path=.*$', "Path=%ResourceDir%\Themes\$Name\$($style.Name)"

    if ($KeepWallpaper -and $currentWallpaper) {
        $text = $text -replace '(?m)^Wallpaper=.*$', "Wallpaper=$currentWallpaper"
    }

    $out = Join-Path $sysThemes $themeFile.Name
    Set-Content -Path $out -Value $text -Encoding Unicode
    Write-Host "Installed $($themeFile.Name) -> $sysThemes"
}

Write-Host ''
Write-Host 'Now open Settings > Personalization > Themes and pick the theme.' -ForegroundColor Green
Write-Host 'If the style still does not stick, the signature hook is the next suspect.'
