param(
    [string]$AzureExternalAdapterName,
    [string]$OnPremUnderlayAdapterName,
    [switch]$UseExternalAdapters
)

$ErrorActionPreference = 'Stop'

$internalSwitches = @(
    'az-dren',
    'az-ext',
    'az-core',
    'az-sdpc',
    'az-sdpg',
    'az-sdpt',
    'az-avd',
    'az-domain',
    'az-domsvc',
    'az-dev',
    'az-devsvc',
    'az-seg',
    'az-hwil',
    'vyos-oob',
    'onp-core',
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
    @{ Name = 'onp-ext'; Adapter = $OnPremUnderlayAdapterName }
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

function Ensure-SwitchPrivate {
    param([string]$Name)

    if (Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "[OK] Switch exists: $Name"
        return
    }

    New-VMSwitch -Name $Name -SwitchType Private | Out-Null
    Write-Host "[NEW] Private switch created: $Name"
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

function Ensure-SwitchHostIp {
    param(
        [string]$SwitchName,
        [string]$HostIp,
        [int]$PrefixLength
    )

    if ([string]::IsNullOrWhiteSpace($HostIp)) {
        return
    }

    $ifAlias = "vEthernet ($SwitchName)"
    $netAdapter = Get-NetAdapter -Name $ifAlias -ErrorAction SilentlyContinue
    if ($null -eq $netAdapter) {
        throw "vEthernet adapter not found: $ifAlias"
    }

    $existingIp = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $HostIp }
    if ($null -eq $existingIp) {
        New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $HostIp -PrefixLength $PrefixLength -ErrorAction Stop | Out-Null
        Write-Host "[NEW] Assigned $HostIp/$PrefixLength to $ifAlias"
    } else {
        Write-Host "[OK] Host IP already set on $ifAlias"
    }
}

function Ensure-SwitchInternalWithNat {
    param(
        [string]$SwitchName,
        [string]$HostIp = '10.255.255.1',
        [int]$PrefixLength = 24,
        [string]$NatName = 'VyosOobNat'
    )

    Ensure-SwitchPrivate -Name $SwitchName

    # Interface alias created by internal vmswitch
    $ifAlias = "vEthernet ($SwitchName)"
    $netAdapter = Get-NetAdapter -Name $ifAlias -ErrorAction SilentlyContinue
    if ($null -eq $netAdapter) {
        Write-Host "[WARN] vEthernet adapter not found for $SwitchName; host IP/NAT not configured yet: $ifAlias"
        return
    }

    # Assign host IP if not present
    $existingIp = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $HostIp }
    if ($null -eq $existingIp) {
        try {
            New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $HostIp -PrefixLength $PrefixLength -ErrorAction Stop | Out-Null
            Write-Host "[NEW] Assigned $HostIp/$PrefixLength to $ifAlias"
        } catch {
            Write-Host "[WARN] Failed to assign $HostIp to ${ifAlias}: $($_.Exception.Message)"
        }
    } else {
        Write-Host "[OK] Host IP already set on $ifAlias"
    }

    # Ensure NAT exists
    $nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
    $prefix = "$($HostIp -replace '\.\d+$','0')/$PrefixLength"
    if ($null -eq $nat) {
        try {
            New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $prefix -ErrorAction Stop | Out-Null
            Write-Host "[NEW] Created NAT $NatName for $prefix"
        } catch {
            Write-Host "[WARN] Failed to create NAT ${NatName}: $($_.Exception.Message)"
        }
    } else {
        Write-Host "[OK] NAT exists: $NatName"
    }
}

foreach ($name in $internalSwitches) {
    Ensure-SwitchPrivate -Name $name
}

# Configure OOB internal switch with NAT (10.255.255.0/24)
Ensure-SwitchInternalWithNat -SwitchName 'vyos-oob' -HostIp '10.255.255.1' -PrefixLength 24 -NatName 'VyosOobNat'

foreach ($ext in $externalSwitches) {
    if ($UseExternalAdapters -and -not [string]::IsNullOrWhiteSpace($ext.Adapter)) {
        Ensure-SwitchExternal -Name $ext.Name -AdapterName $ext.Adapter
    } else {
        if ($UseExternalAdapters -and [string]::IsNullOrWhiteSpace($ext.Adapter)) {
            Write-Host "[WARN] No adapter provided for $($ext.Name); creating Private switch instead."
        }
        Ensure-SwitchPrivate -Name $ext.Name
    }
}

Write-Host 'Done.'
