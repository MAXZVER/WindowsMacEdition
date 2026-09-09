#Requires -Version 5.1
<#
.SYNOPSIS
    Writes the PowerToys Keyboard Manager remaps that give Windows macOS text
    navigation, and points at the scancode map that reorders the modifiers.
.DESCRIPTION
    Two layers are involved, and they do different jobs.

    Layer 1 - the scancode map (MacLayout-WinMode-APPLY.reg, needs admin and a
    reboot). It reorders the bottom-left modifiers at driver level:

        LWin  (E05B) -> LAlt  (0038)   middle key becomes Option
        LAlt  (0038) -> RCtrl (E01D)   key next to Space becomes Command

    That yields Control, Option, Command, Space - the layout of a real Mac
    keyboard - while the keyboard itself stays in Windows mode.

    Keep the keyboard in Windows mode. A keyboard's own "Mac mode" produces the
    same modifier order, but its top row then sends Apple HID codes that Windows
    does not decode: volume, media and Print Screen stop working entirely.
    Doing the reorder here instead keeps the function row usable.

    Command is deliberately mapped to the RIGHT Ctrl. It behaves as Ctrl for
    every shortcut, but stays distinguishable from the left one, which is what
    lets Control+Space and Command+Space mean different things.

    Layer 2 - this script. Scancode maps can only swap key identities, so
    anything that changes a whole combination lives in PowerToys:

        Control+Space          -> Win+Space        switch input language
        Option+Left/Right      -> Ctrl+Left/Right  move by word
        Option+Shift+arrows    -> select by word
        Option+Backspace       -> delete word
        Command+Left/Right     -> Home/End
        Command+Up/Down        -> document start/end
        Command+Shift+arrows   -> the selecting variants

    There is no Command+Backspace ("delete to start of line"): Windows has no
    single shortcut for it and Keyboard Manager cannot emit a sequence.
.NOTES
    Keyboard Manager does not reach elevated windows unless PowerToys itself
    runs elevated, and never reaches the lock screen or UAC. Alt+Shift is left
    untouched as a fallback way to switch layouts.
.EXAMPLE
    .\Install-KeyboardRemaps.ps1
#>
[CmdletBinding()]
param(
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

# 8=Backspace 32=Space 35=End 36=Home 37=Left 38=Up 39=Right 40=Down
# 91=Win 160=Shift 162=LCtrl 163=RCtrl(Command) 164=LAlt(Option)
$config = @'
{
    "remapKeys": { "inProcess": [] },
    "remapKeysToText": { "inProcess": [] },
    "remapShortcuts": {
        "global": [
            { "originalKeys": "162;32",     "newRemapKeys": "91;32"      },

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
if (Test-Path $target) { Copy-Item $target "$target.bak" -Force; Write-Host "Backed up existing remaps to default.json.bak" }
[IO.File]::WriteAllText($target, $config, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote 14 remaps to $target"

# Keyboard Manager ships disabled; flip it on without disturbing other modules.
$settings = Join-Path $base 'settings.json'
if (Test-Path $settings) {
    $raw = [IO.File]::ReadAllText($settings)
    if ($raw -match '("Keyboard Manager"\s*:\s*)false') {
        [IO.File]::WriteAllText($settings, ($raw -replace '("Keyboard Manager"\s*:\s*)false', '${1}true'), (New-Object System.Text.UTF8Encoding($false)))
        Write-Host 'Enabled the Keyboard Manager module'
    }
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
Write-Host 'Remaps are live. The modifier reorder is separate:'
Write-Host '  reg import MacLayout-WinMode-APPLY.reg   (elevated, then reboot)'
