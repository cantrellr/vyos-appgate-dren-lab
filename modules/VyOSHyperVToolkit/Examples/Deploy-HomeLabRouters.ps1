Import-Module (Join-Path $PSScriptRoot '..\VyOSHyperVToolkit.psd1') -Force

Invoke-VyosRouterLab -VhdPath 'D:\Production_Data\HyperV\Hard Disk Templates\vyos-1.5.0-hyperv-amd64.vhdx' -ExternalSwitchName 'cotpa-vlans_vsw' -ExternalVlanId 9 -Recreate -Verbose