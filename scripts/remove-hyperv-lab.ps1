[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot,
    [string[]]$VmNames = @(
        'vyos-az-external','vyos-az-edge','vyos-az-core','vyos-az-inside','vyos-az-developer','vyos-az-segment1',
        'vyos-onp-edge','vyos-onp-core','vyos-onp-inside','vyos-onp-developer','vyos-onp-segment1'
    ),
    [string[]]$SwitchNames = @(
        'az-dren','az-ext','az-core','az-sdpc','az-sdpg','az-sdpt','az-avd','az-domain','az-domsvc','az-dev','az-devsvc','az-seg','az-hwil','az-wan',
        'vyos-oob',
        'onp-core','onp-sdpc','onp-sdpg','onp-sdpt','onp-avd','onp-domain','onp-domsvc','onp-dev','onp-devsvc','onp-seg','onp-hwil','onp-ext'
    ),
    [switch]$RemoveVhds,
    [switch]$RemoveSwitches,
    [switch]$RemoveIsos = $true,
    [switch]$RemoveHwIds = $true,
    [string]$IsoWorkingRoot,
    [string]$HwIdsOutputPath
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

if ([string]::IsNullOrWhiteSpace($IsoWorkingRoot)) {
    $IsoWorkingRoot = Join-Path $RepoRoot 'artifacts\vyos-config-iso'
}

if ([string]::IsNullOrWhiteSpace($HwIdsOutputPath)) {
    $HwIdsOutputPath = Join-Path $RepoRoot 'artifacts\vyos-hwids.vyos'
}

foreach ($vmName in $VmNames) {
    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if ($null -eq $vm) {
        Write-Host "[SKIP] VM not found: $vmName"
        continue
    }

    if ($PSCmdlet.ShouldProcess($vmName, 'Remove VM')) {
        if ($vm.State -ne 'Off') {
            Stop-VM -Name $vmName -TurnOff -Force | Out-Null
        }

        $vhdPaths = @()
        if ($RemoveVhds) {
            $vhdPaths = Get-VMHardDiskDrive -VMName $vmName | Select-Object -ExpandProperty Path
        }

        Remove-VM -Name $vmName -Force | Out-Null
        Write-Host "[OK] VM removed: $vmName"

        foreach ($path in $vhdPaths) {
            if (Test-Path $path) {
                Remove-Item -Path $path -Force
                Write-Host "[OK] VHD removed: $path"
            }
        }
    }
}

if ($RemoveSwitches) {
    foreach ($switchName in $SwitchNames) {
        $switch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
        if ($null -eq $switch) {
            Write-Host "[SKIP] Switch not found: $switchName"
            continue
        }

        if ($PSCmdlet.ShouldProcess($switchName, 'Remove VMSwitch')) {
            try {
                Remove-VMSwitch -Name $switchName -Force -ErrorAction Stop
                Write-Host "[OK] Switch removed: $switchName"
            } catch {
                Write-Host "[WARN] Could not remove switch: $switchName - $($_.Exception.Message)"
                continue
            }
        }
    }
}

Write-Host 'Done.'

if ($RemoveIsos) {
    if (Test-Path $IsoWorkingRoot) {
        Get-ChildItem -Path $IsoWorkingRoot -Filter '*.iso' -File -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] ISO removed: $($_.FullName)"
        }
    } else {
        Write-Host "[WARN] ISO working root not found: $IsoWorkingRoot"
    }
}

if ($RemoveHwIds) {
    if (Test-Path $HwIdsOutputPath) {
        Remove-Item -Path $HwIdsOutputPath -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] hw-id config removed: $HwIdsOutputPath"
    } else {
        Write-Host "[WARN] hw-id config not found: $HwIdsOutputPath"
    }
}
