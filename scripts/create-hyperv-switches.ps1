param(
    [string]$AzureExternalAdapterName,
    [string]$OnPremUnderlayAdapterName,
    [switch]$UseExternalAdapters
)

$ErrorActionPreference = 'Stop'

$internalSwitches = @(
    'AZ-DREN',
    'AZ-SDPC',
    'AZ-SDPG',
    'AZ-SDPT',
    'AZ-AVD',
    'AZ-DOMAIN',
    'AZ-DOMSVC',
    'AZ-DEV',
    'AZ-DEVSVC',
    'AZ-SEG',
    'ONP-DREN',
    'ONP-SDPC',
    'ONP-SDPG',
    'ONP-SDPT',
    'ONP-AVD',
    'ONP-DOMAIN',
    'ONP-DOMSVC',
    'ONP-DEV',
    'ONP-DEVSVC',
    'ONP-SEG',
    'ONP-HWIL'
)

$externalSwitches = @(
    @{ Name = 'AZ-WAN'; Adapter = $AzureExternalAdapterName },
    @{ Name = 'ONP-UNDERLAY'; Adapter = $OnPremUnderlayAdapterName }
)

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

    if ([string]::IsNullOrWhiteSpace($AdapterName)) {
        throw "Adapter name required for external switch '$Name'."
    }

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
