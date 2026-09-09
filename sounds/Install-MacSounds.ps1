#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads the macOS system sounds, converts them to WAV and registers a
    "macOS" sound scheme in Windows. No Python, no ffmpeg, no admin rights.
.DESCRIPTION
    The sounds live in /System/Library/Sounds inside macOS and Apple does not
    publish them separately, so they are pulled from a community mirror. They
    arrive as 24-bit big-endian AIFF; Windows PlaySound wants little-endian
    16-bit PCM WAV, so this converts them in-process.

    Only events that have a macOS counterpart are remapped. USB connect, logon,
    UAC and battery keep their Windows sounds on purpose - macOS has no such
    events, so replacing them would be less faithful, not more.

    Note this covers PlaySound events only: dialogs, alerts, Win32 apps. Toast
    notifications resolve ms-winsoundevent: against the files in
    C:\Windows\Media and ignore the registry entirely - see
    Replace-ToastSounds.ps1 for that half.
.PARAMETER OutDir
    Where to put the converted WAV files. They are referenced by absolute path
    from the registry, so pick somewhere permanent.
.EXAMPLE
    .\Install-MacSounds.ps1
.EXAMPLE
    .\Install-MacSounds.ps1 -OutDir 'D:\Sounds\macOS'
#>
[CmdletBinding()]
param(
    [string]$OutDir = $PSScriptRoot,
    [string]$SchemeName = 'macOS',
    [string]$SourceUrl = 'https://raw.githubusercontent.com/extratone/macOSsystemsounds/main/aiff/aiff.zip'
)

$ErrorActionPreference = 'Stop'
if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

# --- AIFF -> WAV -----------------------------------------------------------
# AIFF stores samples big-endian; WAV is little-endian. 24-bit is narrowed to
# 16 by keeping the two high bytes, which is what the Windows mixer wants.

function ConvertFrom-ExtendedFloat([byte[]]$b) {
    $expon = ((($b[0] -band 0x7F) -shl 8) -bor $b[1])
    $hi = ([uint32]$b[2] -shl 24) -bor ([uint32]$b[3] -shl 16) -bor ([uint32]$b[4] -shl 8) -bor $b[5]
    $lo = ([uint32]$b[6] -shl 24) -bor ([uint32]$b[7] -shl 16) -bor ([uint32]$b[8] -shl 8) -bor $b[9]
    if ($expon -eq 0 -and $hi -eq 0 -and $lo -eq 0) { return 0 }
    $expon -= 16383
    [math]::Round([math]::Pow(2, $expon - 31) * $hi + [math]::Pow(2, $expon - 63) * $lo)
}

function Convert-AiffToWav([string]$In, [string]$Out) {
    $d = [IO.File]::ReadAllBytes($In)
    if ([Text.Encoding]::ASCII.GetString($d, 0, 4) -ne 'FORM') { throw "not an AIFF: $In" }

    $be4 = { param($o) ([int]$d[$o] -shl 24) -bor ([int]$d[$o + 1] -shl 16) -bor ([int]$d[$o + 2] -shl 8) -bor $d[$o + 3] }
    $be2 = { param($o) ([int]$d[$o] -shl 8) -bor $d[$o + 1] }

    $pos = 12
    $channels = 0; $bits = 0; $rate = 0; $dataOff = -1; $dataLen = 0
    while ($pos -lt $d.Length - 8) {
        $id = [Text.Encoding]::ASCII.GetString($d, $pos, 4)
        $size = & $be4 ($pos + 4)
        $body = $pos + 8
        if ($id -eq 'COMM') {
            $channels = & $be2 $body
            $bits = & $be2 ($body + 6)
            $rate = ConvertFrom-ExtendedFloat $d[($body + 8)..($body + 17)]
        }
        elseif ($id -eq 'SSND') {
            $skip = & $be4 $body
            $dataOff = $body + 8 + $skip      # past offset and blockSize
            $dataLen = $size - 8 - $skip
        }
        $pos = $body + $size + ($size % 2)    # chunks are word-aligned
    }
    if ($dataOff -lt 0) { throw "no SSND chunk in $In" }

    $step = $bits / 8
    $count = [int]($dataLen / $step)
    $pcm = New-Object byte[] ($count * 2)
    for ($i = 0; $i -lt $count; $i++) {
        $s = $dataOff + $i * $step
        $pcm[$i * 2] = $d[$s + 1]             # low byte  <- second big-endian byte
        $pcm[$i * 2 + 1] = $d[$s]             # high byte <- first  big-endian byte
    }

    $fs = [IO.File]::Create($Out)
    $w = New-Object IO.BinaryWriter($fs)
    try {
        $byteRate = $rate * $channels * 2
        $blockAlign = $channels * 2
        $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $pcm.Length))
        $w.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
        $w.Write([Text.Encoding]::ASCII.GetBytes('fmt ')); $w.Write([int]16)
        $w.Write([int16]1); $w.Write([int16]$channels); $w.Write([int]$rate)
        $w.Write([int]$byteRate); $w.Write([int16]$blockAlign); $w.Write([int16]16)
        $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$pcm.Length)
        $w.Write($pcm)
    }
    finally { $w.Close(); $fs.Close() }

    [pscustomobject]@{ Channels = $channels; Rate = $rate; SourceBits = $bits; Bytes = (Get-Item $Out).Length }
}

# --- fetch and convert -----------------------------------------------------

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('macsounds_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    Write-Host "Downloading $SourceUrl"
    $zip = Join-Path $tmp 'aiff.zip'
    $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $SourceUrl -OutFile $zip -UseBasicParsing
    $ProgressPreference = $old
    Expand-Archive -Path $zip -DestinationPath $tmp -Force

    $aiffs = Get-ChildItem $tmp -Recurse -Filter *.aiff
    if (-not $aiffs) { throw 'archive contained no .aiff files' }
    Write-Host "Converting $($aiffs.Count) files"
    foreach ($a in $aiffs) {
        $out = Join-Path $OutDir ($a.BaseName + '.wav')
        $i = Convert-AiffToWav $a.FullName $out
        '{0,-12} {1}ch {2}Hz  {3}-bit source  -> {4:N0} bytes' -f $a.BaseName, $i.Channels, $i.Rate, $i.SourceBits, $i.Bytes
    }
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# --- register the scheme ---------------------------------------------------
# Events with no macOS counterpart deliberately keep whatever they play now.

$map = [ordered]@{
    '.Default'              = 'Funk'
    'SystemAsterisk'        = 'Glass'
    'SystemExclamation'     = 'Funk'
    'SystemHand'            = 'Basso'
    'SystemNotification'    = 'Glass'
    'Notification.Default'  = 'Glass'
    'Notification.IM'       = 'Pop'
    'Notification.SMS'      = 'Pop'
    'Notification.Mail'     = 'Ping'
    'MailBeep'              = 'Ping'
    'Notification.Reminder' = 'Hero'
}

$nameKey = "HKCU:\AppEvents\Schemes\Names\$SchemeName"
if (-not (Test-Path $nameKey)) { New-Item -Path $nameKey -Force | Out-Null }
Set-ItemProperty -Path $nameKey -Name '(default)' -Value $SchemeName

foreach ($ev in $map.Keys) {
    $wav = Join-Path $OutDir ($map[$ev] + '.wav')
    if (-not (Test-Path $wav)) { Write-Warning "missing $wav, skipping $ev"; continue }
    foreach ($sub in $SchemeName, '.Current') {
        $k = "HKCU:\AppEvents\Schemes\Apps\.Default\$ev\$sub"
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        Set-ItemProperty -Path $k -Name '(default)' -Value $wav
    }
}

# Fill the rest of the scheme with whatever is playing now, so picking it in
# mmsys.cpl does not silence every event this script does not touch.
Get-ChildItem 'HKCU:\AppEvents\Schemes\Apps' | ForEach-Object {
    Get-ChildItem $_.PSPath | ForEach-Object {
        $k = Join-Path $_.PSPath $SchemeName
        if (-not (Test-Path $k)) {
            $cur = (Get-ItemProperty (Join-Path $_.PSPath '.Current') -ErrorAction SilentlyContinue).'(default)'
            New-Item -Path $k -Force | Out-Null
            Set-ItemProperty -Path $k -Name '(default)' -Value ([string]$cur)
        }
    }
}

Set-ItemProperty -Path 'HKCU:\AppEvents\Schemes' -Name '(default)' -Value $SchemeName

Write-Host ''
Write-Host "Scheme '$SchemeName' registered and active. Check it in mmsys.cpl -> Sounds."
Write-Host 'Toast notifications are a separate mechanism - run Replace-ToastSounds.ps1 for those.'
