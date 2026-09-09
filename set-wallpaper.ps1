#Requires -Version 5.1
<#
.SYNOPSIS
    Sets the desktop wallpaper without letting Windows re-compress it badly,
    optionally across every virtual desktop.
.DESCRIPTION
    Windows transcodes whatever you set into a JPEG at roughly quality 85 and
    caches it as TranscodedWallpaper. On a high resolution screen that is
    visible. JPEGImportQuality raises that ceiling to 100 before applying.

    Windows 11 keeps a separate wallpaper per virtual desktop under
    HKCU\...\Explorer\VirtualDesktops\Desktops\{guid}. SystemParametersInfo
    only touches the desktop you are currently on, so -AllVirtualDesktops
    writes the same path into every one of them. The key is exported first.
.EXAMPLE
    .\set-wallpaper.ps1 -Path .\fitted\forest.jpg -AllVirtualDesktops
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateSet('Fill','Fit','Stretch','Tile','Center','Span')]
    [string]$Style = 'Fill',
    [int]$ImportQuality = 100,
    [switch]$AllVirtualDesktops,
    [string]$BackupDir = (Join-Path $PSScriptRoot 'backup')
)

$ErrorActionPreference = 'Stop'

$Path = (Resolve-Path $Path).Path
if (-not (Test-Path $Path)) { throw "File not found: $Path" }

Add-Type -AssemblyName System.Drawing
$img  = [System.Drawing.Image]::FromFile($Path)
$dims = "$($img.Width)x$($img.Height)"
$img.Dispose()

$desktop = 'HKCU:\Control Panel\Desktop'

$old = (Get-ItemProperty $desktop -Name JPEGImportQuality -ErrorAction SilentlyContinue).JPEGImportQuality
Write-Host ("JPEGImportQuality: {0} -> {1}" -f $(if ($null -eq $old) { 'not set (defaults to ~85)' } else { $old }), $ImportQuality)
Set-ItemProperty $desktop -Name JPEGImportQuality -Value $ImportQuality -Type DWord

$styleMap = @{ Fill = 10; Fit = 6; Stretch = 2; Tile = 0; Center = 0; Span = 22 }
Set-ItemProperty $desktop -Name WallpaperStyle -Value ([string]$styleMap[$Style])
Set-ItemProperty $desktop -Name TileWallpaper  -Value $(if ($Style -eq 'Tile') { '1' } else { '0' })

if (-not ('Wallpaper' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
}

$SPI_SETDESKWALLPAPER = 20
$SPIF_UPDATEINIFILE   = 0x01
$SPIF_SENDCHANGE      = 0x02

$rc = [Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $Path,
        ($SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE))
if ($rc -eq 0) { throw "SystemParametersInfo failed (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }

Write-Host ''
Write-Host "Applied : $Path"
Write-Host "Image   : $dims"
Write-Host "Style   : $Style"

if ($AllVirtualDesktops) {
    $deskKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops\Desktops'

    if (-not (Test-Path $deskKey)) {
        Write-Host ''
        Write-Host 'No per-desktop wallpapers configured - the single wallpaper already covers all desktops.'
        return
    }

    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $bak = Join-Path $BackupDir ('virtualdesktops_{0}.reg' -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    & reg.exe export 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops' "$bak" /y > $null 2>&1
    Write-Host ''
    Write-Host "Backup  : $bak"
    Write-Host ''

    $n = 0
    foreach ($k in Get-ChildItem $deskKey) {
        $before = (Get-ItemProperty $k.PSPath -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper
        Set-ItemProperty -Path $k.PSPath -Name Wallpaper -Value $Path -Type String
        $n++
        $tag = if ($before -eq $Path) { 'already set' } else { 'updated' }
        '{0,2}. {1}  [{2}]' -f $n, $k.PSChildName, $tag
    }
    Write-Host ''
    Write-Host "Virtual desktops updated: $n"
}
