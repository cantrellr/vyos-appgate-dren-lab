<#
Create Hyper-V VMs for the multicluster lab.

Usage:
  .\create-multicluster-vms.ps1 -VhdPath C:\images\ubuntu-server.vhdx -SwitchPrefix 'vSwitch-'

This script expects the vSwitches to already exist (use configs/nodes/network/vswitches/create-multicluster-switches.ps1).
The user will supply the path to the base VHDX image to attach to each VM. It will not modify the VHDX.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$VhdPath,
    [string]$SwitchPrefix = 'vSwitch-'
)

if (-not (Test-Path $VhdPath)) { Write-Error "VHD path $VhdPath not found"; exit 1 }

$vmRoot = "$PSScriptRoot\..\configs\nodes\vms"
New-Item -Path $vmRoot -ItemType Directory -Force | Out-Null

function siteSwitches($site) {
    return @(
        "${SwitchPrefix}$site-kubes",
        "${SwitchPrefix}$site-storage",
        "${SwitchPrefix}$site-domain",
        "${SwitchPrefix}$site-seg1"
    )
}

$nodes = @(
    @{ Name='dc1manager-ctrl01'; Switches = siteSwitches('dc1') },
    @{ Name='dc1manager-work01'; Switches = siteSwitches('dc1') },
    @{ Name='dc1domain-ctrl01';  Switches = siteSwitches('dc1') },
    @{ Name='dc1domain-work01';  Switches = siteSwitches('dc1') },
    @{ Name='dc2domain-ctrl01';  Switches = siteSwitches('dc2') },
    @{ Name='dc2domain-work01';  Switches = siteSwitches('dc2') },
    @{ Name='dc3domain-ctrl01';  Switches = siteSwitches('dc3') },
    @{ Name='dc3domain-work01';  Switches = siteSwitches('dc3') }
)

foreach ($node in $nodes) {
    $vmName = $node.Name
    if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) { Write-Host "VM $vmName already exists, skipping"; continue }

    Write-Host "Creating VM: $vmName"
    New-VM -Name $vmName -MemoryStartupBytes 4GB -Generation 2 -BootDevice VHD -Path "$vmRoot\$vmName" | Out-Null
    Set-VM -Name $vmName -ProcessorCount 1

    # Attach network adapters - explicit mapping to per-network vSwitches:
    # eth0 -> kubes-domain
    # eth1 -> storage (netapp)
    # eth2 -> domain (management)
    # eth3 -> segment1
    $swKubes = $node.Switches[0]
    $swStorage = $node.Switches[1]
    $swDomain = $node.Switches[2]
    $swSeg1 = $node.Switches[3]

    Add-VMNetworkAdapter -VMName $vmName -SwitchName $swKubes -Name "eth0" | Out-Null
    Add-VMNetworkAdapter -VMName $vmName -SwitchName $swStorage -Name "eth1" | Out-Null
    Add-VMNetworkAdapter -VMName $vmName -SwitchName $swDomain -Name "eth2" | Out-Null
    Add-VMNetworkAdapter -VMName $vmName -SwitchName $swSeg1 -Name "eth3" | Out-Null

    # Attach existing VHD as drive
    $destVhd = "$vmRoot\$vmName\$vmName.vhdx"
    Copy-Item -Path $VhdPath -Destination $destVhd -Force
    Add-VMHardDiskDrive -VMName $vmName -Path $destVhd

    Write-Host "Created VM $vmName with 1 CPU, 4GB RAM, and VHD at $destVhd"
}

Write-Host 'All VMs processed. Verify with Get-VM'
