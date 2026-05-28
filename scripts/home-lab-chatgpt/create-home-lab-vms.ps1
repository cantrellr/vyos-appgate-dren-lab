<#
Creates Hyper‑V VMs for the home‑lab multicluster environment described in the
k8s‑mystical‑mesh ingress‑monitoring‑redesign branch.  This script provisions
12 VMs – four clusters of three nodes each (one control plane and two workers)
across three sites.  Each VM is created with 1 vCPU, 4 GB RAM, and four
network adapters corresponding to the kubes‑domain, storage, domain, and
segment1 networks.

Usage:

    .\create-home-lab-vms.ps1 -VhdPath C:\images\ubuntu-server.vhdx -SwitchPrefix 'vSwitch-'

The vSwitches must already exist.  Use `scripts/create-vyos-routers.ps1` to
provision the central and site routers and internal vSwitches.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$VhdPath,
    [string]$SwitchPrefix = 'vSwitch-'
)

if (-not (Test-Path $VhdPath)) { Write-Error "VHD path $VhdPath not found"; exit 1 }

# Destination path for the VM definitions and disks
$vmRoot = Join-Path $PSScriptRoot '..\..\configs\home-lab-chatgpt\nodes\vms'
New-Item -Path $vmRoot -ItemType Directory -Force | Out-Null

function Get-SiteSwitches($site) {
    return @(
        "${SwitchPrefix}$site-kubes",
        "${SwitchPrefix}$site-storage",
        "${SwitchPrefix}$site-domain",
        "${SwitchPrefix}$site-seg1"
    )
}

# Define the VM inventory.  Each entry includes the VM name and the site it
# belongs to; site names must match the prefixes used by
# create-vyos-routers.ps1.
$nodes = @(
    @{ Name='j64manager-ctrl01'; Site='dc1' },
    @{ Name='j64manager-work01'; Site='dc1' },
    @{ Name='j64manager-work02'; Site='dc1' },
    @{ Name='j64domain-ctrl01';  Site='dc1' },
    @{ Name='j64domain-work01';  Site='dc1' },
    @{ Name='j64domain-work02';  Site='dc1' },
    @{ Name='j52domain-ctrl01';  Site='dc2' },
    @{ Name='j52domain-work01';  Site='dc2' },
    @{ Name='j52domain-work02';  Site='dc2' },
    @{ Name='r01domain-ctrl01';  Site='dc3' },
    @{ Name='r01domain-work01';  Site='dc3' },
    @{ Name='r01domain-work02';  Site='dc3' }
)

foreach ($node in $nodes) {
    $vmName = $node.Name
    $site = $node.Site

    if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
        Write-Host "VM $vmName already exists, skipping"
        continue
    }

    Write-Host "Creating VM: $vmName"
    # Create VM with 4 GB RAM and attach the base image copy
    New-VM -Name $vmName -MemoryStartupBytes 4GB -Generation 2 -BootDevice VHD -Path (Join-Path $vmRoot $vmName) | Out-Null
    Set-VM -Name $vmName -ProcessorCount 1

    # Determine switch names for the site
    $switches = Get-SiteSwitches $site
    $swKubes   = $switches[0]
    $swStorage = $switches[1]
    $swDomain  = $switches[2]
    $swSeg1    = $switches[3]

    # Attach network adapters in deterministic order (eth0..eth3)
    Add-VMNetworkAdapter -VMName $vmName -SwitchName $swKubes -Name 'eth0' | Out-Null
    Add-VMNetworkAdapter -VMName $vmName -SwitchName $swStorage -Name 'eth1' | Out-Null
    Add-VMNetworkAdapter -VMName $vmName -SwitchName $swDomain -Name 'eth2' | Out-Null
    Add-VMNetworkAdapter -VMName $vmName -SwitchName $swSeg1 -Name 'eth3' | Out-Null

    # Attach a copy of the VHDX template.  The base image is not modified.
    $destVhd = Join-Path (Join-Path $vmRoot $vmName) "$vmName.vhdx"
    Copy-Item -Path $VhdPath -Destination $destVhd -Force
    Add-VMHardDiskDrive -VMName $vmName -Path $destVhd

    Write-Host "Created VM $vmName with 1 CPU, 4GB RAM, and VHD at $destVhd"
}

Write-Host 'All home‑lab VMs processed.  Verify with Get-VM.'