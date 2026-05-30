<#
Create VyOS router VMs and the internal lab switches for the multicluster lab.

Topology summary:
  - Site switches are internal only.
  - The transit switch is internal only.
  - The central router is the only VM that connects to the host's external
    switch, which should be the Hyper-V switch bound to the physical NIC that
    carries VLAN 9.

Usage:
    .\create-vyos-routers.ps1 -ExternalSwitchName 'cotpa-vlans_vsw' -ExternalVlanId 9

This creates one central router plus one site router per site.
Each router is created with 1 CPU and 256MB RAM by default.
#>

param(
        [string]$VhdPath = 'D:\Production_Data\HyperV\Hard Disk Templates\vyos-1.4.4-hyperv-amd64.vhdx',

        [string]$VirtualDiskRoot = 'D:\Production_Data\HyperV\Virtual Hard Disks\K8S',

    [string]$SwitchPrefix = 'vSwitch-',

    [string]$ExternalSwitchName = 'cotpa-vlans_vsw',

    [int]$ExternalVlanId = 9
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $VhdPath)) {
    Write-Error "VHD path $VhdPath not found"
    exit 1
}

New-Item -Path $VirtualDiskRoot -ItemType Directory -Force | Out-Null

$vmRoot = Join-Path $PSScriptRoot '..\configs\home-lab\vms\vyos'
New-Item -Path $vmRoot -ItemType Directory -Force | Out-Null

$routerConfigRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\configs\home-lab\routers')).Path
$isoStagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'vyos-router-nocloud-seed'
New-Item -Path $isoStagingRoot -ItemType Directory -Force | Out-Null

$script:OscdimgPath = $null

function Get-OscdimgPath {
    if ($null -ne $script:OscdimgPath) {
        return $script:OscdimgPath
    }

    $oscdimg = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($null -eq $oscdimg) {
        throw 'oscdimg.exe was not found. Install Oscdimg or add it to PATH.'
    }

    $script:OscdimgPath = $oscdimg.Source
    return $script:OscdimgPath
}

function Convert-VyosConfigToCloudInitUserData {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath
    )

    $commands = @(
        Get-Content -Path $ConfigPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^(set|delete)\s+' }
    )

    if ($commands.Count -eq 0) {
        throw "No VyOS configuration commands found in $ConfigPath"
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('#cloud-config')
    $lines.Add('vyos_config_commands:')

    foreach ($command in $commands) {
        $lines.Add("  - $command")
    }

    return $lines -join [System.Environment]::NewLine
}

function New-NoCloudSeedIso {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$IsoPath
    )

    $stagePath = Join-Path $isoStagingRoot $Name
    if (Test-Path $stagePath) {
        Remove-Item -Path $stagePath -Recurse -Force
    }

    New-Item -Path $stagePath -ItemType Directory -Force | Out-Null

    try {
        $userDataPath = Join-Path $stagePath 'user-data'
        $metaDataPath = Join-Path $stagePath 'meta-data'
        $networkConfigPath = Join-Path $stagePath 'network-config'

        $userData = Convert-VyosConfigToCloudInitUserData -ConfigPath $ConfigPath
        Set-Content -Path $userDataPath -Value $userData -Encoding ASCII
        New-Item -Path $metaDataPath -ItemType File -Force | Out-Null

        $networkConfig = @'
version: 2
ethernets:
  eth0:
    dhcp4: false
    dhcp6: false
'@
        Set-Content -Path $networkConfigPath -Value $networkConfig -Encoding ASCII

        if (Test-Path $IsoPath) {
            Remove-Item -Path $IsoPath -Force
        }

        $volumeLabel = 'CIDATA'

        $oscdimgPath = Get-OscdimgPath
        & $oscdimgPath -m -o -u2 -udfver102 "-l$volumeLabel" $stagePath $IsoPath
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create NoCloud seed ISO for $Name at $IsoPath"
        }
    }
    finally {
        if (Test-Path $stagePath) {
            Remove-Item -Path $stagePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-SiteSwitches {
    param([Parameter(Mandatory = $true)][string]$Site)

    @(
        "${SwitchPrefix}$Site-kubes"
        "${SwitchPrefix}$Site-storage"
        "${SwitchPrefix}$Site-domain"
        "${SwitchPrefix}$Site-seg1"
        "${SwitchPrefix}transit"
    )
}

function Ensure-InternalSwitch {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "[OK] vSwitch exists: $Name"
        return
    }

    New-VMSwitch -Name $Name -SwitchType Internal | Out-Null
    Write-Host "[NEW] Internal vSwitch created: $Name"
}

function Ensure-VMFromVhd {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Switches,
        [switch]$ExternalUplink
    )

    $vmPath = Join-Path $vmRoot $Name
    New-Item -Path $vmPath -ItemType Directory -Force | Out-Null

    $diskPath = Join-Path $VirtualDiskRoot $Name
    New-Item -Path $diskPath -ItemType Directory -Force | Out-Null

    $configPath = Join-Path $routerConfigRoot "$Name.vyos"
    if (-not (Test-Path $configPath)) {
        throw "Router config $configPath not found"
    }

    $destVhd = Join-Path $diskPath "$Name.vhdx"
    $seedIsoPath = Join-Path $diskPath "$Name-seed.iso"

    $vmExists = $null -ne (Get-VM -Name $Name -ErrorAction SilentlyContinue)

    if ($vmExists) {
        Write-Host "VM $Name already exists, ensuring config ISO and VM settings"
    } else {
        Write-Host "Creating VyOS VM: $Name"
        New-VM -Name $Name -MemoryStartupBytes 256MB -Generation 2 -NoVHD -Path $vmPath | Out-Null
        Set-VM -Name $Name -ProcessorCount 1 | Out-Null

        # Remove the default unmanaged adapter so eth0..ethN are deterministic.
        $defaultAdapter = Get-VMNetworkAdapter -VMName $Name -Name 'Network Adapter' -ErrorAction SilentlyContinue
        if ($null -ne $defaultAdapter) {
            Remove-VMNetworkAdapter -VMName $Name -Name 'Network Adapter' -Confirm:$false
        }

        $index = 0
        foreach ($switchName in $Switches) {
            $nicName = "eth$index"
            Add-VMNetworkAdapter -VMName $Name -SwitchName $switchName -Name $nicName | Out-Null
            $index += 1
        }

    }

    if (-not (Get-VMHardDiskDrive -VMName $Name -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        Copy-Item -Path $VhdPath -Destination $destVhd -Force
        Add-VMHardDiskDrive -VMName $Name -Path $destVhd | Out-Null
    } elseif (-not (Test-Path $destVhd)) {
        Copy-Item -Path $VhdPath -Destination $destVhd -Force
    }

    New-NoCloudSeedIso -Name $Name -ConfigPath $configPath -IsoPath $seedIsoPath

    $dvdDrive = Get-VMDvdDrive -VMName $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $dvdDrive) {
        Set-VMDvdDrive -VMName $Name -Path $seedIsoPath | Out-Null
    } else {
        Add-VMDvdDrive -VMName $Name -Path $seedIsoPath | Out-Null
    }

    Set-VM -Name $Name -AutomaticCheckpointsEnabled $false | Out-Null

    # Ensure disk-first boot for Gen2 VMs.
    $bootDisk = Get-VMHardDiskDrive -VMName $Name | Select-Object -First 1
    if ($null -ne $bootDisk) {
        Set-VMFirmware -VMName $Name -EnableSecureBoot Off -FirstBootDevice $bootDisk | Out-Null
    }

    if ($ExternalUplink) {
        Set-VMNetworkAdapterVlan -VMName $Name -VMNetworkAdapterName 'eth0' -Access -VlanId $ExternalVlanId | Out-Null
        Write-Host "[NEW] Applied VLAN $ExternalVlanId to eth0 on $Name"
    }

    Write-Host "Ready VM $Name with 1 CPU, 256MB RAM, VHD at $destVhd, and NoCloud seed ISO at $seedIsoPath"
}

$sites = @('dc1', 'dc2', 'dc3')
foreach ($site in $sites) {
    foreach ($switchName in (Get-SiteSwitches -Site $site)) {
        Ensure-InternalSwitch -Name $switchName
    }
}

Ensure-InternalSwitch -Name "${SwitchPrefix}transit"

$routers = @(
    @{ Name = 'router-center'; Switches = @($ExternalSwitchName, "${SwitchPrefix}transit"); External = $true },
    @{ Name = 'router-dc1'; Switches = @(Get-SiteSwitches -Site 'dc1'); External = $false },
    @{ Name = 'router-dc2'; Switches = @(Get-SiteSwitches -Site 'dc2'); External = $false },
    @{ Name = 'router-dc3'; Switches = @(Get-SiteSwitches -Site 'dc3'); External = $false }
)

if (-not (Get-VMSwitch -Name $ExternalSwitchName -ErrorAction SilentlyContinue)) {
    throw "External switch '$ExternalSwitchName' was not found. Create it first and bind it to the physical NIC carrying VLAN $ExternalVlanId."
}

foreach ($router in $routers) {
    if ($router.External) {
        Ensure-VMFromVhd -Name $router.Name -Switches $router.Switches -ExternalUplink
    } else {
        Ensure-VMFromVhd -Name $router.Name -Switches $router.Switches
    }
}

Write-Host 'All VyOS routers processed. Verify with Get-VM and Get-VMSwitch.'
