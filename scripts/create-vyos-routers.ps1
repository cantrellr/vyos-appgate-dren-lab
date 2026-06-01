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
Each router is created with 1 CPU and 1GB RAM by default.
#>

param(
        [string]$VhdPath = 'D:\Production_Data\HyperV\Hard Disk Templates\vyos-1.5.0-hyperv-amd64.vhdx',

        [string]$VirtualDiskRoot = 'D:\Production_Data\HyperV\Virtual Hard Disks\K8S',

    [string]$SwitchPrefix = 'vSwitch-',

    [string]$ExternalSwitchName = 'cotpa-vlans_vsw',

    [int]$ExternalVlanId = 9
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\modules\VyOSHyperVToolkit\VyOSHyperVToolkit.psd1') -Force

Invoke-VyosRouterLab -VhdPath 'D:\Production_Data\HyperV\Hard Disk Templates\vyos-1.5.0-hyperv-amd64.vhdx' -ExternalSwitchName 'cotpa-vlans_vsw' -ExternalVlanId 9 -Recreate
