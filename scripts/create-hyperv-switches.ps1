param(
    [string]$AzureExternalAdapterName,
    [string]$OnPremUnderlayAdapterName,
    [switch]$UseExternalAdapters
)

$ErrorActionPreference = 'Stop'

$internalSwitches = @(
    'az-dren',
    'az-sdpc',
    'az-sdpg',
    'az-sdpt',
    'az-avd',
    'az-domain',
    'az-domsvc',
    'az-dev',
    'az-devsvc',
    'az-seg',
    'onp-dren',
    'onp-sdpc',
    'onp-sdpg',
    'onp-sdpt',
    'onp-avd',
    'onp-domain',
    'onp-domsvc',
    'onp-dev',
    'onp-devsvc',
    'onp-seg',
    'onp-hwil'
)

$externalSwitches = @(
    @{ Name = 'az-wan'; Adapter = $AzureExternalAdapterName },
    @{ Name = 'onp-underlay'; Adapter = $OnPremUnderlayAdapterName }
)

function Get-AdapterNames {
    Get-NetAdapter | Select-Object -ExpandProperty Name
}

function Assert-AdapterExists {
    param([string]$AdapterName, [string]$SwitchName)

    if ([string]::IsNullOrWhiteSpace($AdapterName)) {
        throw "Adapter name required for external switch '$SwitchName'."
    }

    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
    if ($null -eq $adapter) {
        $available = (Get-AdapterNames) -join ', '
        throw "Adapter '$AdapterName' not found for switch '$SwitchName'. Available adapters: $available"
    }
}

function Ensure-SwitchInternal {
    param([string]$Name)

    if (Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "[OK] Switch exists: $Name"
        return
    }

    New-VMSwitch -Name $Name -SwitchType Internal | Out-Null
    Write-Host "[NEW] Internal switch created: $Name"
}

function Ensure-SwitchExternal {
    param([string]$Name, [string]$AdapterName)

    if (Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "[OK] Switch exists: $Name"
        return
    }

    Assert-AdapterExists -AdapterName $AdapterName -SwitchName $Name

    New-VMSwitch -Name $Name -NetAdapterName $AdapterName -AllowManagementOS $true | Out-Null
    Write-Host "[NEW] External switch created: $Name (Adapter: $AdapterName)"
}

foreach ($name in $internalSwitches) {
    Ensure-SwitchInternal -Name $name
}

foreach ($ext in $externalSwitches) {
    if ($UseExternalAdapters) {
        Ensure-SwitchExternal -Name $ext.Name -AdapterName $ext.Adapter
    } else {
        Ensure-SwitchInternal -Name $ext.Name
    }
}

Write-Host 'Done.'
