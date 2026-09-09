# Подменяет системные файлы звуков уведомлений Windows на маковские.
# ЗАПУСКАТЬ ОТ ИМЕНИ АДМИНИСТРАТОРА.
# Откат: Restore-ToastSounds.ps1

$ErrorActionPreference = 'Stop'
$src    = $PSScriptRoot
$media  = "$env:WINDIR\Media"
$backup = Join-Path $src 'windows-media-backup'

$map = @{
    'Windows Notify System Generic.wav' = 'Glass.wav'   # Notification.Default
    'Windows Notify Messaging.wav'      = 'Pop.wav'     # Notification.IM / SMS
    'Windows Notify Email.wav'          = 'Ping.wav'    # Notification.Mail
    'Windows Notify Calendar.wav'       = 'Hero.wav'    # Notification.Reminder
    'Windows Notify.wav'                = 'Glass.wav'   # общий
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Нужны права администратора. Запусти PowerShell от имени администратора.'
}

New-Item -ItemType Directory -Force -Path $backup | Out-Null

foreach ($target in $map.Keys) {
    $dst = Join-Path $media $target
    $new = Join-Path $src   $map[$target]

    if (-not (Test-Path $new)) { Write-Warning "нет источника: $new"; continue }
    if (-not (Test-Path $dst)) { Write-Warning "нет цели: $dst";     continue }

    # бэкап один раз — чтобы повторный запуск не затёр оригинал подменённым
    $bak = Join-Path $backup $target
    if (-not (Test-Path $bak)) { Copy-Item $dst $bak -Force; Write-Host "бэкап: $target" }

    takeown /f "$dst" | Out-Null
    icacls  "$dst" /grant "*S-1-5-32-544:(F)" | Out-Null   # Администраторы, по SID (не зависит от языка ОС)

    Copy-Item $new $dst -Force
    Write-Host ("{0,-36} <- {1}" -f $target, $map[$target])
}

Write-Host ''
Write-Host 'Готово. Перезапусти приложение, которое шлёт уведомления.'
