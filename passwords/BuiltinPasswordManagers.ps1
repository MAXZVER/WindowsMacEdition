#Requires -Version 5.1
<#
.SYNOPSIS
    Turns the browsers' own password managers off, so iCloud Passwords is the
    only thing offering to fill logins. Run elevated.
.DESCRIPTION
    Sets PasswordManagerEnabled = 0 as a machine policy for every Chromium
    browser installed here. The built-in manager then stops offering to save,
    stops autofilling, and its settings page is greyed out - Chrome will not
    quietly turn itself back on after an update, which is the whole reason for
    using a policy rather than the in-app toggle.

    Passwords already stored in the browsers are NOT touched, exported or
    deleted by this script. Clearing them out is a separate decision and is
    made in each browser's own settings, by you.

    Side effect: browsers will show "Managed by your organization" in the menu.
    That is what a local policy looks like from the inside; -Restore removes it.
.PARAMETER Restore
    Puts everything back: deletes the values this script set, and any policy
    key it created that is left empty.
.EXAMPLE
    .\BuiltinPasswordManagers.ps1            # disable
    .\BuiltinPasswordManagers.ps1 -Restore   # undo
#>
[CmdletBinding()]
param(
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Needs an elevated PowerShell: these are machine policies under HKLM.'
}

# Yandex Browser is Chromium and honours the same policy under its own vendor key
$targets = @(
    @{ Name = 'Google Chrome';   Key = 'HKLM:\SOFTWARE\Policies\Google\Chrome' },
    @{ Name = 'Microsoft Edge';  Key = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' },
    @{ Name = 'Yandex Browser';  Key = 'HKLM:\SOFTWARE\Policies\YandexBrowser' }
)

$valueName = 'PasswordManagerEnabled'

foreach ($t in $targets) {
    if ($Restore) {
        if (Test-Path $t.Key) {
            $existing = Get-ItemProperty $t.Key -Name $valueName -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-ItemProperty -Path $t.Key -Name $valueName -Force
                Write-Host ("  {0,-16} policy removed" -f $t.Name)
            } else {
                Write-Host ("  {0,-16} nothing to remove" -f $t.Name)
            }
            # drop the key only if this script is what created it
            $left = (Get-ItemProperty $t.Key).PSObject.Properties |
                    Where-Object { $_.Name -notlike 'PS*' }
            if (-not $left -and -not (Get-ChildItem $t.Key -ErrorAction SilentlyContinue)) {
                Remove-Item $t.Key -Force
                Write-Host ("  {0,-16} empty policy key deleted" -f $t.Name)
            }
        } else {
            Write-Host ("  {0,-16} no policy key" -f $t.Name)
        }
    }
    else {
        if (-not (Test-Path $t.Key)) { New-Item -Path $t.Key -Force | Out-Null }
        Set-ItemProperty -Path $t.Key -Name $valueName -Value 0 -Type DWord
        Write-Host ("  {0,-16} built-in password manager disabled" -f $t.Name)
    }
}

Write-Host ''
Write-Host '--- current state ---'
foreach ($t in $targets) {
    $v = (Get-ItemProperty $t.Key -Name $valueName -ErrorAction SilentlyContinue).$valueName
    '  {0,-16} {1}' -f $t.Name, $(if ($null -eq $v) { 'no policy (browser decides)' } else { "$valueName = $v" })
}

Write-Host ''
if ($Restore) {
    Write-Host 'Restart the browsers for them to pick this up.'
} else {
    Write-Host 'Restart the browsers. Saved passwords are still in each profile -'
    Write-Host 'clear them yourself once iCloud has everything you need.'
}
