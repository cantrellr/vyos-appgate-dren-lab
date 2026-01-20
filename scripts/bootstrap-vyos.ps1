param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [Parameter(Mandatory = $true)]
    [string]$VmName,
    [string]$IsoOutputPath,
    [string]$IsoWorkingRoot,
    [string]$InstanceId,
    [ValidateSet('ConfigOnly','NoCloud')]
    [string]$IsoMode = 'ConfigOnly',
    [switch]$SkipAttach,
    [switch]$DisableDhcpEth0
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$repoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($IsoWorkingRoot)) {
    $IsoWorkingRoot = Join-Path $repoRoot 'artifacts\vyos-config-iso'
}

if ([string]::IsNullOrWhiteSpace($IsoOutputPath)) {
    $isoSuffix = if ($IsoMode -eq 'NoCloud') { 'seed' } else { 'configonly' }
    $IsoOutputPath = Join-Path $IsoWorkingRoot ("$VmName.$isoSuffix.iso")
}

if ([string]::IsNullOrWhiteSpace($InstanceId)) {
    $InstanceId = [guid]::NewGuid().ToString()
}

if (-not (Test-Path -Path $IsoWorkingRoot)) {
    New-Item -ItemType Directory -Path $IsoWorkingRoot | Out-Null
}

function Get-VyosHostNameFromConfig {
    param([string]$Path)

    $pattern = 'set system host-name ''([^'']+)''|set system host-name "([^"]+)"'
    $match = Select-String -Path $Path -Pattern $pattern | Select-Object -First 1
    if ($null -eq $match) {
        return $null
    }

    if ($match.Matches[0].Groups[1].Success) {
        return $match.Matches[0].Groups[1].Value
    }

    if ($match.Matches[0].Groups[2].Success) {
        return $match.Matches[0].Groups[2].Value
    }

    return $null
}

$hostname = $null
$vyosConfigLines = $null
$userDataLines = $null
$metaDataLines = $null
$networkConfigLines = $null

if ($IsoMode -eq 'NoCloud') {
    $hostname = Get-VyosHostNameFromConfig -Path $ConfigPath

    $vyosConfigLines = Get-Content -Path $ConfigPath | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and
        (-not $_.StartsWith('#')) -and
        ($_ -notin @('configure','commit','save','exit'))
    }

    $userDataLines = @(
        "#cloud-config",
        "datasource_list: [ NoCloud, None ]",
        "vyos_config_commands:"
    ) + ($vyosConfigLines | ForEach-Object { "  - $_" })

    $metaDataLines = @(
        "instance-id: $InstanceId"
    )

    if (-not [string]::IsNullOrWhiteSpace($hostname)) {
        $metaDataLines += "local-hostname: $hostname"
    }

    if ($DisableDhcpEth0) {
        $networkConfigLines = @(
            "version: 2",
            "ethernets:",
            "  eth0:",
            "    dhcp4: false",
            "    dhcp6: false"
        )
    }
}

$tempRoot = Join-Path $IsoWorkingRoot ([System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetRandomFileName()))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    if ($IsoMode -eq 'NoCloud') {
        Set-Content -Path (Join-Path $tempRoot 'user-data') -Value $userDataLines -Encoding UTF8
        Set-Content -Path (Join-Path $tempRoot 'meta-data') -Value $metaDataLines -Encoding UTF8
        if ($null -ne $networkConfigLines) {
            Set-Content -Path (Join-Path $tempRoot 'network-config') -Value $networkConfigLines -Encoding UTF8
        }
    } else {
        $configLines = Get-Content -Path $ConfigPath
        $configLines = $configLines | Where-Object { $_ -and ($_.Trim() -notin @('configure','commit','save','exit')) }
        $configText = ($configLines -join "`n")
        $configOutPath = Join-Path $tempRoot 'config.vyos'
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($configOutPath, $configText, $utf8NoBom)
        $applyScript = @(
            '#!/bin/vbash',
            'set -e',
            'if [ "$(id -u)" -ne 0 ]; then',
            "  echo 'Run as root (sudo -i).';",
            '  exit 1;',
            'fi',
            'mkdir -p /mnt/cdrom',
            'if ! mountpoint -q /mnt/cdrom; then',
            '  mount /dev/sr1 /mnt/cdrom || mount /dev/sr0 /mnt/cdrom || mount /dev/cdrom /mnt/cdrom',
            'fi',
            'if [ ! -f /mnt/cdrom/config.vyos ]; then',
            "  echo 'config.vyos not found on /mnt/cdrom';",
            '  exit 1;',
            'fi',
            'configure',
            'source /mnt/cdrom/config.vyos',
            'commit',
            'save',
            'exit',
            "echo 'Config applied. Rebooting...';",
            'reboot'
        )
        $applyPath = Join-Path $tempRoot 'apply-config.sh'
        $applyText = ($applyScript -join "`n")
        [System.IO.File]::WriteAllText($applyPath, $applyText, $utf8NoBom)
    }

    $oscdimg = Get-Command -Name oscdimg.exe -ErrorAction SilentlyContinue
    $mkisofs = Get-Command -Name mkisofs -ErrorAction SilentlyContinue
    $geniso = Get-Command -Name genisoimage -ErrorAction SilentlyContinue

    $isoLabel = if ($IsoMode -eq 'NoCloud') { 'CIDATA' } else { 'VYOSCFG' }

    if ($oscdimg) {
        & $oscdimg.Source -o -u2 -udfver102 -l$isoLabel $tempRoot $IsoOutputPath | Out-Null
    } elseif ($mkisofs) {
        & $mkisofs.Source -o $IsoOutputPath -V $isoLabel -J -r $tempRoot | Out-Null
    } elseif ($geniso) {
        & $geniso.Source -o $IsoOutputPath -V $isoLabel -J -r $tempRoot | Out-Null
    } else {
        throw "ISO tool not found. Install Windows ADK (oscdimg) or mkisofs/genisoimage, then retry."
    }
} finally {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $SkipAttach) {
    $dvd = Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue
    if ($null -eq $dvd) {
        Add-VMDvdDrive -VMName $VmName -Path $IsoOutputPath | Out-Null
    } else {
        Set-VMDvdDrive -VMName $VmName -Path $IsoOutputPath | Out-Null
    }

    Write-Host "[OK] Cloud-init ISO attached: $VmName -> $IsoOutputPath"
} else {
    Write-Host "[OK] Cloud-init ISO created: $VmName -> $IsoOutputPath"
}
