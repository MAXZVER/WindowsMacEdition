#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the macOS keyboard layout into PowerToys Keyboard Manager: the
    bottom-row modifiers and macOS text navigation.
.DESCRIPTION
    Three key remaps reorder the bottom row so it reads Windows, Option,
    Command, Space:

        Left Ctrl -> Left Win     leftmost key is Windows
        Left Win  -> Left Alt     middle key is Option
        Left Alt  -> Right Ctrl   key next to Space is Command

    Command lands on the *right* Ctrl. It acts as Ctrl for every shortcut, so
    Command+C copies, while staying distinguishable from a left Ctrl - which is
    what lets Command+arrow mean something different from Ctrl+arrow.

    There is deliberately no separate Control key. Windows has one Ctrl
    concept, so a Control key beside a Command key does the same thing: two
    keys, one function, and no Windows key anywhere. The leftmost position buys
    back Win+E, Win+R, Win+Tab, the Start menu, Win+Space for the language
    (the system's own switcher) and Win+L, which no remapper can synthesise
    because Windows reserves it.

    Thirteen shortcut remaps then provide text navigation, which swapping key
    identities cannot express: Option+arrows by word, Command+arrows to line
    ends, and the Shift variants for selection. Each Shift variant needs its
    own entry, since Keyboard Manager matches a combination as a whole.

    Keeping all of it at user level is a deliberate trade - see the README for
    why this is not a scancode map. Use Toggle-MacLayout.ps1 to switch it off
    for games.
.EXAMPLE
    .\Install-KeyboardRemaps.ps1
#>
[CmdletBinding()]
param(
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

# 8=Backspace 32=Space 35=End 36=Home 37=Left 38=Up 39=Right 40=Down
# 91=LWin 160=Shift 162=LCtrl 163=RCtrl(Command) 164=LAlt(Option)
$config = @'
{
    "remapKeys": {
        "inProcess": [
            { "originalKeys": "162", "newRemapKeys": "91"  },
            { "originalKeys": "91",  "newRemapKeys": "164" },
            { "originalKeys": "164", "newRemapKeys": "163" }
        ]
    },
    "remapKeysToText": { "inProcess": [] },
    "remapShortcuts": {
        "global": [
            { "originalKeys": "164;37",     "newRemapKeys": "162;37"     },
            { "originalKeys": "164;39",     "newRemapKeys": "162;39"     },
            { "originalKeys": "164;160;37", "newRemapKeys": "162;160;37" },
            { "originalKeys": "164;160;39", "newRemapKeys": "162;160;39" },
            { "originalKeys": "164;8",      "newRemapKeys": "162;8"      },

            { "originalKeys": "163;37",     "newRemapKeys": "36"         },
            { "originalKeys": "163;39",     "newRemapKeys": "35"         },
            { "originalKeys": "163;160;37", "newRemapKeys": "160;36"     },
            { "originalKeys": "163;160;39", "newRemapKeys": "160;35"     },
            { "originalKeys": "163;38",     "newRemapKeys": "162;36"     },
            { "originalKeys": "163;40",     "newRemapKeys": "162;35"     },
            { "originalKeys": "163;160;38", "newRemapKeys": "162;160;36" },
            { "originalKeys": "163;160;40", "newRemapKeys": "162;160;35" }
        ],
        "appSpecific": []
    },
    "remapShortcutsToText": { "global": [], "appSpecific": [] }
}
'@

$base = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'
if (-not (Test-Path $base)) { throw "PowerToys is not installed ($base not found)." }

$kmDir = Join-Path $base 'Keyboard Manager'
New-Item -ItemType Directory -Force -Path $kmDir | Out-Null
$target = Join-Path $kmDir 'default.json'
if (Test-Path $target) { Copy-Item $target "$target.bak" -Force; Write-Host 'Backed up existing remaps to default.json.bak' }
[IO.File]::WriteAllText($target, $config, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote 3 key remaps and 13 shortcut remaps to $target"

# Keyboard Manager ships disabled; flip it on without disturbing other modules.
$settings = Join-Path $base 'settings.json'
if (Test-Path $settings) {
    $raw = [IO.File]::ReadAllText($settings)
    if ($raw -match '("Keyboard Manager"\s*:\s*)false') {
        [IO.File]::WriteAllText($settings, ($raw -replace '("Keyboard Manager"\s*:\s*)false', '${1}true'), (New-Object System.Text.UTF8Encoding($false)))
        Write-Host 'Enabled the Keyboard Manager module'
    }
}

# A leftover Scancode Map would be applied by the driver before any of this and
# would fight it. Only a reboot clears one that is already loaded.
$sc = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' -Name 'Scancode Map' -ErrorAction SilentlyContinue)
if ($sc) {
    Write-Warning 'A Scancode Map exists in the registry and will fight these remaps.'
    Write-Warning 'Remove it (elevated) and reboot: keyboard\Remove-ScancodeMap.reg'
}

if (-not $NoRestart) {
    $proc = Get-Process -Name PowerToys -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) {
        $exe = $proc.Path
        Get-Process -Name PowerToys* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process $exe
        Start-Sleep -Seconds 5
        if (Get-Process -Name 'PowerToys.KeyboardManager*' -ErrorAction SilentlyContinue) {
            Write-Host 'PowerToys restarted, Keyboard Manager engine is running.'
        } else {
            Write-Warning 'Keyboard Manager engine did not come up - start PowerToys manually.'
        }
    } else {
        Write-Warning 'PowerToys is not running (or is elevated) - restart it yourself to load the remaps.'
    }
}

Write-Host ''
Write-Host 'Done. Toggle-MacLayout.ps1 switches this off for games.'
