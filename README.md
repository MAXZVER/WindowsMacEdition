# Windows Mac Edition

Scripts that make Windows 11 behave like macOS — keyboard, system sounds, a
caret-side layout indicator, wallpaper and theme handling.

Not a theme pack. Every piece here exists because the obvious approach did not
work, and the notes explain why, so you can decide whether you want that
particular trade.

Everything is PowerShell 5.1, which ships with Windows. Nothing to install
except PowerToys for the keyboard part.

---

## Keyboard

Gives you `Control, Option, Command, Space` and macOS text navigation.

```powershell
# elevated, then reboot
reg import keyboard\MacLayout-WinMode-APPLY.reg

# normal shell
.\keyboard\Install-KeyboardRemaps.ps1
```

**Keep the keyboard in Windows mode.** Boards like the Lofree Flow have a
"Mac mode" (`Fn+M`) that reorders the modifiers in firmware — and it works. But
its function row then sends Apple HID codes that Windows does not decode:
volume, media keys and Print Screen stop working, and nothing arrives at the
system at all. Doing the reorder in the scancode map instead keeps the top row
usable.

The scancode map moves two keys at driver level:

| Scancode | Becomes | Result |
|---|---|---|
| `LWin` `E05B` | `LAlt` `0038` | middle key is Option |
| `LAlt` `0038` | `RCtrl` `E01D` | key next to Space is Command |

Command is mapped to the **right** Ctrl on purpose. It acts as Ctrl for every
shortcut, but stays distinguishable from the left one — which is what lets
`Control+Space` and `Command+Space` mean different things.

The PowerToys layer handles everything a scancode map cannot, because swapping
key identities cannot change a whole combination:

| Shortcut | Does |
|---|---|
| `Control+Space` | switch input language |
| `Option+←/→` | move by word |
| `Option+Shift+←/→` | select by word |
| `Option+Backspace` | delete word |
| `Command+←/→` | start / end of line |
| `Command+↑/↓` | start / end of document |
| `Command+Shift+arrows` | the selecting variants |

`Command+Backspace` (delete to start of line) is missing: Windows has no single
shortcut for it and Keyboard Manager cannot emit a sequence.

Two limits worth knowing. Keyboard Manager does not reach elevated windows
unless PowerToys itself runs elevated, and never reaches the lock screen or UAC
prompt. `Alt+Shift` is left untouched as a fallback way to switch layouts.

Undo: `reg import keyboard\Remove-ScancodeMap.reg`, elevated, then reboot.

---

## Sounds

```powershell
.\sounds\Install-MacSounds.ps1              # no admin needed
.\sounds\Replace-ToastSounds.ps1            # elevated
```

The first script downloads the macOS system sounds, converts them and registers
a `macOS` scheme you can pick in `mmsys.cpl`. The conversion runs in PowerShell
— the sources are 24-bit big-endian AIFF and Windows wants little-endian 16-bit
PCM WAV, so there is a small AIFF parser in there. No Python, no ffmpeg.

**Windows has two unrelated sound systems, and that is the whole difficulty.**

`AppEvents` in the registry — what the Sound control panel edits — drives
`PlaySound` only: dialogs, alerts, Win32 apps. Toast notifications resolve
`ms-winsoundevent:` against the files in `C:\Windows\Media` and ignore the
registry completely. You can delete every trace of the old path from the
registry and toasts will still play it.

So the second script replaces those files instead, backing up the originals
first. It needs admin because they belong to `TrustedInstaller`. A major
Windows update or `sfc /scannow` will restore them; rerun it if that happens.

Only events with a macOS counterpart are touched. USB connect, logon, UAC and
battery keep their Windows sounds deliberately — macOS has no such events, and
replacing them would be less faithful, not more.

Apps that ship their own audio — Telegram, Discord, Slack — are out of reach of
both mechanisms. That is also what happens on a real Mac, where Telegram sounds
like Telegram rather than like macOS.

Undo: `sounds\Restore-ToastSounds.ps1` (elevated) and
`sounds\Sounds-RESTORE.reg`.

---

## Caret Language Indicator

A small badge that shows the current keyboard layout and Caps Lock state right
next to the text caret, the way macOS shows its input source.

Windows has no such indicator. PowerToys does not have one either — the feature
requests are still open. The language bar in the taskbar is far from where you
are actually typing, so you notice the wrong layout only after a line of
gibberish.

### Why another one

Existing layout indicators (Punto Switcher, LangBarXX, Caramba) locate the
caret through the classic Win32 API, `GetGUIThreadInfo`. That works in Notepad,
Office and native controls — and returns nothing at all in Chromium and
Electron apps, which draw their own caret. Chrome, VS Code, Telegram, Discord,
Slack: precisely where most typing happens today.

This one falls back to UI Automation and reads the caret from
`TextPattern.GetSelection().GetBoundingRectangles()`, which Chromium does
report. Three levels, in order of precision:

1. `GetGUIThreadInfo` — the real Win32 caret.
2. `TextPattern` selection rectangle — Chromium, Electron, UWP.
3. Bounding box of the focused text control — anything else; the badge then
   sits beside the field rather than at the cursor.

### Build and run

Nothing to install — the C# compiler ships with Windows:

```powershell
.\build.ps1
```

It compiles `src/Indicator.cs` with `csc.exe` from
`C:\Windows\Microsoft.NET\Framework64\v4.0.30319` and writes a ~20 KB exe. To
start it with Windows, put a shortcut in `shell:startup`.

The tray icon carries the current layout — `EN`, `RU` — and turns amber while
Caps Lock is on, so it works like the macOS menu bar: the tray is the state you
can always glance at, the panel is the moment of change. It is drawn at run
time rather than shipped as a `.ico`, since it has to change with the layout.

### Options

| Flag | Values | Default | Meaning |
|---|---|---|---|
| `-Anchor` | `Caret` `Field` `Corner` | `Caret` | what the badge is pinned to |
| `-VAlign` | `Below` `Center` | `Below` | under the caret, or level with the line |
| `-Side` | `Left` `Right` | `Left` | which side of the field, when pinned to a field |
| `-OffsetX` | pixels | `8` | gap from the caret |
| `-OffsetY` | pixels | `2` | vertical nudge |
| `-FieldGap` | pixels | `12` | gap from the edge of a field |
| `-OnlyWhenCaps` | — | off | show only while Caps Lock is on |
| `-OnlyOnChange` | — | off | stay hidden, appear briefly when the layout changes |
| `-ShowMs` | ms | `1200` | how long it stays up in that mode |
| `-Switcher` | — | off | show every installed layout in a row, macOS HUD style |
| `-Glass` | — | off | Windows 11 acrylic instead of the flat dark pill |
| `-Interval` | ms | `120` | polling interval (`40` when `-OnlyOnChange`) |

`-Anchor Corner` parks the badge in a fixed screen corner, which never covers
anything. `-OnlyWhenCaps` gives the macOS arrangement: layout in a menu bar
somewhere, the badge only for Caps Lock.

### macOS HUD mode

```powershell
.\CaretLangIndicator.exe -OnlyOnChange -Switcher
```

This is what macOS actually does: nothing on screen until you switch, then a
panel appears near the caret listing every installed input source with the
active one highlighted, and the highlight slides when you switch again.

It is also by far the cheapest mode. While hidden, a tick is three
same-process calls — `GetForegroundWindow`, `GetKeyboardLayout`, `GetKeyState`
— and UI Automation runs once per switch instead of eight times a second.

Three things matter for it to feel instant, and all three were wrong at first:

- The selection slides with a `RenderTransform`, not `Canvas.Left`. Animating
  the attached property re-runs measure and arrange every frame.
- No `DropShadowEffect`. `AllowsTransparency` makes the window layered and
  therefore software-rendered, so the blur was recomputed 60 times a second.
- No `UpdateLayout()` on selection change — the panel's size never changes.

UI Automation, for the record, was not the bottleneck: `FocusedElement`
measured 3.8 ms on average and `TextPattern` 1.4 ms. It still runs off the
dispatcher, on a pool thread, because that is the threading model UIA clients
are supposed to use and because a busy target window can stall a call for far
longer than the average suggests.

### The PowerShell version

`caret-lang-indicator.ps1` is the same thing as a script. It is slower and
heavier (about 165 MB against 80 MB, and noticeably more CPU), but it has two
useful switches while debugging placement in a stubborn app:

```powershell
.\caret-lang-indicator.ps1 -Diagnose          # prints what it detects for 10 s
.\caret-lang-indicator.ps1 -Log detect.log    # logs detection while you work
```

The log tells you which of the three levels answered (`caret`, `textpattern`,
`field`) and for which application.

### Known limits

- Some apps expose neither a caret nor a sane focused element. There the badge
  falls back to the field rectangle, and if that is missing too, to nothing —
  use `-Fallback Mouse` or `-Anchor Corner`.
- An app with buttons hugging its input box (Telegram) will have the badge
  land near them. There is no position next to a field that is safe in every
  application; `-Anchor Corner` is the way out.
- Windows still measures at 100% scaling only in the sense that positions are
  taken in physical pixels; on a mixed-DPI multi-monitor setup expect drift.

---

## Wallpaper and theme

```powershell
.\fit-wallpaper.ps1 -Path .\wallpaper.jpg -Width 5120 -Height 2160
.\set-wallpaper.ps1 -Path .\fitted\wallpaper.jpg -AllVirtualDesktops
.\install-theme.ps1 -Source .\SomeTheme -Name 'Theme Name'
```

`set-wallpaper.ps1` raises `JPEGImportQuality` to 100 before applying, because
Windows otherwise transcodes whatever you set to roughly quality 85 and caches
it — visible on a high-resolution screen. It also writes every virtual desktop:
Windows 11 keeps a separate wallpaper per desktop under
`HKCU\...\Explorer\VirtualDesktops\Desktops\{guid}`, and `SystemParametersInfo`
only touches the one you are currently on.

`fit-wallpaper.ps1` crops to the target aspect ratio from the centre and then
scales, so nothing is stretched.

`install-theme.ps1` installs a visual style into the user profile so no admin
rights are needed, rewriting the `%SystemRoot%\Resources\Themes` paths theme
authors assume. `install-theme-system.ps1` puts it in the system folder
instead, which is the only place Windows loads msstyles from — needed if you
want the visual style itself and not just cursors, sounds and wallpaper.

---

## Not included

No wallpapers, no `.wav` files, no compiled binary. The macOS sounds and
wallpapers belong to Apple and the replaced originals belong to Microsoft;
`Install-MacSounds.ps1` fetches what it needs at run time. Build the executable
yourself with `build.ps1` — it takes a second, and you get to read the source
first.

## Requirements

Windows 11, PowerShell 5.1, and PowerToys for the keyboard remaps. The scancode
map and the toast sound replacement need an elevated shell; everything else
runs as a normal user.

## Licence

MIT, see `LICENSE`.
