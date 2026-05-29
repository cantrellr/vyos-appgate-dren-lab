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
        [string]$VhdPath = 'D:\Production_Data\HyperV\Hard Disk Templates\vyos-1.5.0-hyperv-amd64.vhdx',

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

    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "VM $Name already exists, skipping"
        return
    }

    $vmPath = Join-Path $vmRoot $Name
    New-Item -Path $vmPath -ItemType Directory -Force | Out-Null

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

    if ($ExternalUplink) {
        Set-VMNetworkAdapterVlan -VMName $Name -VMNetworkAdapterName 'eth0' -Access -VlanId $ExternalVlanId | Out-Null
        Write-Host "[NEW] Applied VLAN $ExternalVlanId to eth0 on $Name"
    }

    $diskPath = Join-Path $VirtualDiskRoot $Name
    New-Item -Path $diskPath -ItemType Directory -Force | Out-Null

    $destVhd = Join-Path $diskPath "$Name.vhdx"
    Copy-Item -Path $VhdPath -Destination $destVhd -Force
    Add-VMHardDiskDrive -VMName $Name -Path $destVhd | Out-Null

    # Ensure disk-first boot for Gen2 VMs.
    $bootDisk = Get-VMHardDiskDrive -VMName $Name | Select-Object -First 1
    if ($null -ne $bootDisk) {
        Set-VMFirmware -VMName $Name -FirstBootDevice $bootDisk | Out-Null
    }

    Write-Host "Created VM $Name with 1 CPU, 256MB RAM, and VHD at $destVhd"
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
