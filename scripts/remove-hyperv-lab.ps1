[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot,
    [string[]]$VmNames = @(
        'vyos-az-proton-ext','vyos-az-proton-out','vyos-az-proton-grey','vyos-az-proton-inside','vyos-az-proton-dev','vyos-az-proton-sandbox',
        'vyos-onp-out','vyos-onp-grey','vyos-onp-inside','vyos-onp-dev','vyos-onp-sandbox'
    ),
    [string[]]$SwitchNames = @(
        'az-dren','az-sdpc','az-sdpg','az-sdpt','az-avd','az-domain','az-domsvc','az-dev','az-devsvc','az-seg','az-wan',
        'onp-dren','onp-sdpc','onp-sdpg','onp-sdpt','onp-avd','onp-domain','onp-domsvc','onp-dev','onp-devsvc','onp-seg','onp-hwil','onp-underlay'
    ),
    [switch]$RemoveVhds,
    [switch]$RemoveSwitches = $true
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
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
            Remove-VMSwitch -Name $switchName -Force
            Write-Host "[OK] Switch removed: $switchName"
        }
    }
}

Write-Host 'Done.'
