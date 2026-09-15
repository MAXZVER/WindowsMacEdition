#Requires -Version 5.1
<#
.SYNOPSIS
    Checks at every logon that the mac-like setup is actually in place, puts
    back what is missing, and writes down what it found.
.DESCRIPTION
    Things have gone missing here more than once: an autostart entry created
    after logon never fired, Windhawk disappeared with all its mods, and a
    stale build once replaced a newer one. This does not try to prevent any of
    that - it notices it, repairs what it safely can, and leaves a log so the
    next "something turned itself off" has evidence behind it instead of
    guesswork.

    What it repairs:
      - missing Startup shortcuts for the indicator and the island
      - a missing or empty Dynamic Island config.ini, restored from the
        snapshot kept next to this script
      - either program not running

    What it deliberately does NOT do: overwrite an existing island config.
    You tune those settings by hand, and a watchdog that reverts your edits
    every morning would be worse than the problem. Pass -ForceConfig when you
    really do want the snapshot put back.
.PARAMETER ForceConfig
    Overwrite the island config with the snapshot even if a config exists.
.PARAMETER Snapshot
    Take a fresh snapshot of the current island config and exit.
#>
[CmdletBinding()]
param(
    [switch]$ForceConfig,
    [switch]$Snapshot
)

$ErrorActionPreference = 'Stop'
if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

$log        = Join-Path $PSScriptRoot 'startup-check.log'
$snapshotFile   = Join-Path $PSScriptRoot 'island-config.ini'
$startupDir = [Environment]::GetFolderPath('Startup')

$indicatorExe = Join-Path $env:LOCALAPPDATA 'CaretLangIndicator\CaretLangIndicator.exe'
$indicatorArgs = '-OnlyOnChange -Switcher'
# The island installs itself into the profile, the same way the indicator does;
# the copy in the project folder is only the build output.
$islandExe    = Join-Path $env:LOCALAPPDATA 'DynamicIsland\DynamicIsland.exe'
$islandConfig = Join-Path $env:APPDATA 'DynamicIsland\config.ini'

function Note([string]$text) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $text
    Write-Host $text
    try { Add-Content -Path $log -Value $line -Encoding UTF8 } catch { }
}

if ($Snapshot) {
    Copy-Item $islandConfig $snapshotFile -Force
    Note "snapshot updated from $islandConfig"
    return
}

Note '--- checking ---'

# 1. Startup shortcuts ------------------------------------------------------
function Ensure-Shortcut([string]$name, [string]$target, [string]$arguments) {
    $path = Join-Path $startupDir $name
    $shell = New-Object -ComObject WScript.Shell

    if (Test-Path $path) {
        $sc = $shell.CreateShortcut($path)
        if ($sc.TargetPath -ne $target -or $sc.Arguments -ne $arguments) {
            Note "shortcut '$name' pointed at '$($sc.TargetPath) $($sc.Arguments)' - correcting"
            $sc.TargetPath = $target
            $sc.Arguments = $arguments
            $sc.WorkingDirectory = Split-Path $target
            $sc.Save()
        }
        return
    }

    Note "shortcut '$name' was missing - recreating"
    $sc = $shell.CreateShortcut($path)
    $sc.TargetPath = $target
    $sc.Arguments = $arguments
    $sc.WorkingDirectory = Split-Path $target
    $sc.Save()
}

if (Test-Path $indicatorExe) {
    Ensure-Shortcut 'Caret Language Indicator.lnk' $indicatorExe $indicatorArgs
} else {
    Note "MISSING: $indicatorExe - the indicator is not installed any more"
}

if (Test-Path $islandExe) {
    Ensure-Shortcut 'Dynamic Island.lnk' $islandExe ''
} else {
    Note "MISSING: $islandExe - the island build is gone"
}

# 2. Island settings --------------------------------------------------------
if (Test-Path $snapshotFile) {
    $needRestore = $ForceConfig -or
                   -not (Test-Path $islandConfig) -or
                   ((Get-Item $islandConfig).Length -eq 0)
    if ($needRestore) {
        New-Item -ItemType Directory -Force -Path (Split-Path $islandConfig) | Out-Null
        Copy-Item $snapshotFile $islandConfig -Force
        Note 'island config restored from snapshot'
    }
    elseif ((Get-FileHash $islandConfig).Hash -ne (Get-FileHash $snapshotFile).Hash) {
        Note 'island config differs from the snapshot (left alone - run -Snapshot to accept it)'
    }
} else {
    Note 'no island snapshot next to this script'
}

# 3. Are they actually running ---------------------------------------------
function Ensure-Running([string]$processName, [string]$exe, [string]$arguments) {
    if (Get-Process -Name $processName -ErrorAction SilentlyContinue) { return }
    if (-not (Test-Path $exe)) { return }
    Note "$processName was not running - starting it"
    if ($arguments) {
        Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory (Split-Path $exe)
    } else {
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
    }
}

Ensure-Running 'CaretLangIndicator' $indicatorExe $indicatorArgs
Ensure-Running 'DynamicIsland'      $islandExe    ''

# Windhawk is deliberately not part of this setup any more. It carried nine
# mods - smooth scrolling, menu and Explorer animations, invisible borders -
# but it crashed four times in a week, three of those inside its own Direct2D
# UI, and took the shell down with it. Nothing here depends on it.

Note '--- done ---'
