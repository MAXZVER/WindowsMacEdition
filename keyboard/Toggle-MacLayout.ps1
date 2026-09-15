#Requires -Version 5.1
<#
.SYNOPSIS
    Turns the macOS keyboard layout on or off. Off gives you the stock Windows
    arrangement back - for games, or for anyone else using the machine.
.DESCRIPTION
    The whole layout lives in PowerToys Keyboard Manager: three key remaps for
    the bottom-row modifiers, thirteen shortcut remaps for text navigation. So
    switching is one flag plus a restart of PowerToys - instant, and no
    administrator rights, since none of it touches HKLM.

    It used to be a scancode map in the registry instead. That version worked
    in more places, including the lock screen, but could not be switched
    without rebooting: kbdclass reads Scancode Map when the service starts, so
    restarting the keyboard device is not enough. For a layout you want to flip
    before a gaming session, that made it useless.

    What the user-level version gives up is elevated windows, the lock screen
    and UAC prompts, where no hook is allowed to run. Alt+Shift still switches
    the language there, and a PIN is digits either way.

    Turning it off matters for games twice over. The leftmost key is the
    Windows key under this layout, and hitting it mid-match drops you to the
    Start menu. And with Keyboard Manager off there is no keyboard hook at all,
    which is what PowerToys itself recommends while gaming.
.PARAMETER On
    Force the macOS layout on.
.PARAMETER Off
    Force the stock Windows layout.
.PARAMETER Status
    Print the current state and exit, changing nothing.
.EXAMPLE
    .\Toggle-MacLayout.ps1            # flip to whatever it is not
.EXAMPLE
    .\Toggle-MacLayout.ps1 -Off       # stock Windows, for a gaming session
#>
[CmdletBinding()]
param(
    [switch]$On,
    [switch]$Off,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'

$Base     = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'
$Settings = Join-Path $Base 'settings.json'
$Config   = Join-Path $Base 'Keyboard Manager\default.json'

function Get-State {
    if (-not (Test-Path $Settings)) { return $null }
    try { return [bool](Get-Content $Settings -Raw | ConvertFrom-Json).enabled.'Keyboard Manager' }
    catch { return $null }
}

function Get-RemapCounts {
    if (-not (Test-Path $Config)) { return $null }
    try {
        $j = Get-Content $Config -Raw | ConvertFrom-Json
        return [pscustomobject]@{
            Keys      = @($j.remapKeys.inProcess).Count
            Shortcuts = @($j.remapShortcuts.global).Count
        }
    } catch { return $null }
}

if (-not (Test-Path $Settings)) { throw "PowerToys is not installed ($Base not found)." }

if ($Status) {
    $s = Get-State
    $c = Get-RemapCounts
    Write-Host ("Layout : " + $(if ($s) { 'macOS' } else { 'stock Windows' }))
    if ($c) { Write-Host ("Remaps : {0} keys, {1} shortcuts" -f $c.Keys, $c.Shortcuts) }
    $sc = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' -Name 'Scancode Map' -ErrorAction SilentlyContinue)
    if ($sc) { Write-Warning 'A Scancode Map is still in the registry. It will keep applying until the next reboot and will fight these remaps.' }
    return
}

if ($On -and $Off) { throw 'Pick one of -On or -Off.' }
$target = if ($On) { $true } elseif ($Off) { $false } else { -not (Get-State) }

$raw = [IO.File]::ReadAllText($Settings)
$want = if ($target) { 'true' } else { 'false' }
$new = $raw -replace '("Keyboard Manager"\s*:\s*)(true|false)', ('${1}' + $want)
if ($new -eq $raw) {
    Write-Host ("Already set to: " + $(if ($target) { 'macOS layout' } else { 'stock Windows layout' }))
    return
}
[IO.File]::WriteAllText($Settings, $new, (New-Object System.Text.UTF8Encoding($false)))

# PowerToys reads the flag at startup, so it has to come back round.
$proc = Get-Process -Name PowerToys -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc -and $proc.Path) {
    $exe = $proc.Path
    Get-Process -Name PowerToys* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process $exe
    Start-Sleep -Seconds 4
} else {
    Write-Warning 'PowerToys is not running (or is elevated) - start it yourself for this to take effect.'
}

$engine = Get-Process -Name 'PowerToys.KeyboardManager*' -ErrorAction SilentlyContinue
Write-Host ("Now: " + $(if ($target) { 'macOS layout' } else { 'stock Windows layout' }))
if ($target -and -not $engine) { Write-Warning 'Keyboard Manager engine did not start.' }
if (-not $target -and $engine)  { Write-Warning 'Keyboard Manager engine is still running.' }
