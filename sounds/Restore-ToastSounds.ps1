# Возвращает оригинальные файлы звуков Windows из бэкапа.
# ЗАПУСКАТЬ ОТ ИМЕНИ АДМИНИСТРАТОРА.

$ErrorActionPreference = 'Stop'
$media  = "$env:WINDIR\Media"
$backup = Join-Path $PSScriptRoot 'windows-media-backup'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Нужны права администратора.'
}
if (-not (Test-Path $backup)) { throw "Бэкапа нет: $backup" }

Get-ChildItem $backup -Filter *.wav | ForEach-Object {
    $dst = Join-Path $media $_.Name
    takeown /f "$dst" | Out-Null
    icacls  "$dst" /grant "*S-1-5-32-544:(F)" | Out-Null
    Copy-Item $_.FullName $dst -Force
    Write-Host "восстановлен: $($_.Name)"
}
Write-Host ''
Write-Host 'Оригиналы возвращены.'
