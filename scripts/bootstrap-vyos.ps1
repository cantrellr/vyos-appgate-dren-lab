param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [Parameter(Mandatory = $true)]
    [string]$VmName,
    [string]$IsoOutputPath,
    [string]$IsoWorkingRoot,
    [string]$InstanceId,
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
    $IsoOutputPath = Join-Path $IsoWorkingRoot ("$VmName.config.iso")
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

$networkConfigLines = $null
if ($DisableDhcpEth0) {
    $networkConfigLines = @(
        "version: 2",
        "ethernets:",
        "  eth0:",
        "    dhcp4: false",
        "    dhcp6: false"
    )
}

$tempRoot = Join-Path $IsoWorkingRoot ([System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetRandomFileName()))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    Set-Content -Path (Join-Path $tempRoot 'user-data') -Value $userDataLines -Encoding UTF8
    Set-Content -Path (Join-Path $tempRoot 'meta-data') -Value $metaDataLines -Encoding UTF8
    if ($null -ne $networkConfigLines) {
        Set-Content -Path (Join-Path $tempRoot 'network-config') -Value $networkConfigLines -Encoding UTF8
    }

    $oscdimg = Get-Command -Name oscdimg.exe -ErrorAction SilentlyContinue
    $mkisofs = Get-Command -Name mkisofs -ErrorAction SilentlyContinue
    $geniso = Get-Command -Name genisoimage -ErrorAction SilentlyContinue

    if ($oscdimg) {
        & $oscdimg.Source -o -u2 -udfver102 -lCIDATA $tempRoot $IsoOutputPath | Out-Null
    } elseif ($mkisofs) {
        & $mkisofs.Source -o $IsoOutputPath -V CIDATA -J -r $tempRoot | Out-Null
    } elseif ($geniso) {
        & $geniso.Source -o $IsoOutputPath -V CIDATA -J -r $tempRoot | Out-Null
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
