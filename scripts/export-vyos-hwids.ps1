param(
    [string[]]$VmNamePatterns = @('vyos-az-*','vyos-onp-*'),
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Convert-MacAddress {
    param([string]$Mac)

    if ([string]::IsNullOrWhiteSpace($Mac)) {
        return $null
    }

    $normalized = ($Mac -replace '[-:]','')
    $pairs = $normalized -split '(.{2})' | Where-Object { $_ -ne '' }
    return ($pairs -join ':').ToLowerInvariant()
}

$vmNames = @()
foreach ($pattern in $VmNamePatterns) {
    $vmNames += (Get-VM -Name $pattern -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
}

$vmNames = $vmNames | Sort-Object -Unique
if ($vmNames.Count -eq 0) {
    throw 'No VMs matched the provided patterns.'
}

$outputLines = @()
foreach ($vmName in $vmNames) {
    $outputLines += "# $vmName"
    $adapters = Get-VMNetworkAdapter -VMName $vmName | Sort-Object Name
    foreach ($adapter in $adapters) {
        $mac = Convert-MacAddress -Mac $adapter.MacAddress
        if ($null -eq $mac) {
            continue
        }
        $outputLines += "set interfaces ethernet $($adapter.Name) hw-id '$mac'"
    }
    $outputLines += ''
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputLines | ForEach-Object { Write-Host $_ }
} else {
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $outputLines | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "[OK] hw-id config written: $OutputPath"
}
