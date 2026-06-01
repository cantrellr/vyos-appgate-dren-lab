$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:DefaultRouterConfigRoot = Join-Path $script:RepoRoot 'configs\home-lab\routers'
$script:DefaultVmRoot = Join-Path $script:RepoRoot 'configs\home-lab\vms\vyos'
$script:DefaultVirtualDiskRoot = 'D:\Production_Data\HyperV\Virtual Hard Disks\K8S'
$script:DefaultVhdPath = 'D:\Production_Data\HyperV\Hard Disk Templates\vyos-1.5.0-hyperv-amd64.vhdx'
$script:DefaultSwitchPrefix = 'vSwitch-'
$script:DefaultExternalSwitchName = 'cotpa-vlans_vsw'
$script:DefaultExternalVlanId = 9
$script:DefaultIsoStagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'vyos-router-nocloud-seed'

function Get-OscdimgPath {
    [CmdletBinding()]
    param()

    $oscdimg = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($null -eq $oscdimg) {
        throw 'oscdimg.exe was not found. Install the Windows ADK or add oscdimg.exe to PATH.'
    }

    return $oscdimg.Source
}

function Convert-VyosConfigToCloudInitUserData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "VyOS config not found: $ConfigPath"
    }

    $commands = @(
        Get-Content -Path $ConfigPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^(set|delete)\s+' }
    )

    if ($commands.Count -eq 0) {
        throw "No VyOS configuration commands found in $ConfigPath"
    }

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('#cloud-config')
    [void]$lines.Add('vyos_config_commands:')

    foreach ($command in $commands) {
        [void]$lines.Add("  - $command")
    }

    return $lines -join [Environment]::NewLine
}

function Get-VyosSeedMetaData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UserData
    )

    $normalizedName = $Name -replace '[^A-Za-z0-9._-]', '-'
    $normalizedName = $normalizedName.Trim('-')
    if ([string]::IsNullOrWhiteSpace($normalizedName)) {
        $normalizedName = 'vyos'
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $userDataBytes = [System.Text.Encoding]::UTF8.GetBytes($UserData)
        $hashBytes = $sha256.ComputeHash($userDataBytes)
    }
    finally {
        $sha256.Dispose()
    }

    $hash = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
    $instanceId = "vyos-$normalizedName-$($hash.Substring(0, 16))"

    @(
        "instance-id: $instanceId"
        "local-hostname: $Name"
        'dsmode: local'
    ) -join [Environment]::NewLine
}

function New-VyosSeedIso {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$IsoPath,

        [string]$VolumeLabel = 'cidata',

        [string]$StagingRoot = $script:DefaultIsoStagingRoot
    )

    if ($PSCmdlet.ShouldProcess($IsoPath, "Create NoCloud seed ISO for $Name")) {
        $stagePath = Join-Path $StagingRoot $Name
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
            $metaData = Get-VyosSeedMetaData -Name $Name -UserData $userData
            Set-Content -Path $metaDataPath -Value $metaData -Encoding ASCII

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

            $oscdimgPath = Get-OscdimgPath
            # Build an ISO9660/Joliet image (CDFS) labeled CIDATA for NoCloud detection.
            & $oscdimgPath -m -o -j1 "-l$VolumeLabel" $stagePath $IsoPath | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create NoCloud seed ISO for $Name at $IsoPath"
            }

            return Get-Item -Path $IsoPath
        }
        finally {
            if (Test-Path $stagePath) {
                Remove-Item -Path $stagePath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Get-VyosSiteSwitches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('dc1', 'dc2', 'dc3')]
        [string]$Site,

        [string]$SwitchPrefix = $script:DefaultSwitchPrefix
    )

    @(
        "${SwitchPrefix}$Site-kubes"
        "${SwitchPrefix}$Site-storage"
        "${SwitchPrefix}$Site-domain"
        "${SwitchPrefix}$Site-seg1"
        "${SwitchPrefix}transit"
    )
}

function Ensure-VyosInternalSwitch {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if (Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue) {
        Write-Verbose "vSwitch exists: $Name"
        return
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Create internal vSwitch')) {
        New-VMSwitch -Name $Name -SwitchType Internal | Out-Null
        Write-Verbose "Created internal vSwitch: $Name"
    }
}

function Remove-VyosLab {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string[]]$Names = @('router-center', 'router-dc1', 'router-dc2', 'router-dc3'),

        [string]$VmRoot = $script:DefaultVmRoot,

        [string]$VirtualDiskRoot = $script:DefaultVirtualDiskRoot,

        [switch]$CleanupFiles
    )

    foreach ($name in $Names) {
        $vm = Get-VM -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $vm) {
            if ($PSCmdlet.ShouldProcess($name, 'Remove VyOS router VM')) {
                if ($vm.State -ne 'Off') {
                    Stop-VM -Name $name -TurnOff -Force -ErrorAction SilentlyContinue | Out-Null
                }

                Remove-VM -Name $name -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }

        if ($CleanupFiles) {
            $vmPath = Join-Path $VmRoot $name
            $diskPath = Join-Path $VirtualDiskRoot $name
            foreach ($path in @($vmPath, $diskPath)) {
                if (Test-Path $path) {
                    if ($PSCmdlet.ShouldProcess($path, 'Remove router files')) {
                        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
}

function New-VyosHyperVVm {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Switches,

        [switch]$ExternalUplink,

        [string]$VhdPath = $script:DefaultVhdPath,

        [string]$VirtualDiskRoot = $script:DefaultVirtualDiskRoot,

        [string]$VmRoot = $script:DefaultVmRoot,

        [string]$RouterConfigRoot = $script:DefaultRouterConfigRoot,

        [int]$MemoryMB = 1024,

        [int]$ProcessorCount = 1,

        [int]$ExternalVlanId = $script:DefaultExternalVlanId
    )

    if (-not (Test-Path $VhdPath)) {
        throw "VHD path $VhdPath not found"
    }

    if (-not (Test-Path $RouterConfigRoot)) {
        throw "Router config root $RouterConfigRoot not found"
    }

    $vmPath = Join-Path $VmRoot $Name
    $diskPath = Join-Path $VirtualDiskRoot $Name
    $configPath = Join-Path $RouterConfigRoot "$Name.vyos"
    $destVhd = Join-Path $diskPath "$Name.vhdx"
    $seedIsoPath = Join-Path $diskPath "$Name-seed.iso"

    foreach ($switchName in $Switches) {
        if (-not (Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue)) {
            throw "Required switch not found: $switchName"
        }
    }

    if (-not (Test-Path $vmPath)) {
        New-Item -Path $vmPath -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path $diskPath)) {
        New-Item -Path $diskPath -ItemType Directory -Force | Out-Null
    }

    $vmExists = $null -ne (Get-VM -Name $Name -ErrorAction SilentlyContinue)

    if (-not $vmExists) {
        if ($PSCmdlet.ShouldProcess($Name, 'Create Gen2 VyOS VM')) {
            New-VM -Name $Name -MemoryStartupBytes ($MemoryMB * 1MB) -Generation 2 -NoVHD -Path $vmPath | Out-Null
            Set-VM -Name $Name -ProcessorCount $ProcessorCount | Out-Null
        }
    }

    $expectedNicNames = for ($index = 0; $index -lt $Switches.Count; $index++) { "eth$index" }

    $currentAdapters = @(Get-VMNetworkAdapter -VMName $Name -ErrorAction SilentlyContinue)
    foreach ($adapter in $currentAdapters) {
        if ($expectedNicNames -notcontains $adapter.Name) {
            if ($PSCmdlet.ShouldProcess($Name, "Remove unexpected adapter $($adapter.Name)")) {
                Remove-VMNetworkAdapter -VMName $Name -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }

    foreach ($index in 0..($Switches.Count - 1)) {
        $nicName = "eth$index"
        $switchName = $Switches[$index]
        $adapter = Get-VMNetworkAdapter -VMName $Name -Name $nicName -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($null -eq $adapter) {
            if ($PSCmdlet.ShouldProcess($Name, "Attach $nicName to $switchName")) {
                Add-VMNetworkAdapter -VMName $Name -SwitchName $switchName -Name $nicName | Out-Null
            }
        }
        elseif ($adapter.SwitchName -ne $switchName) {
            if ($PSCmdlet.ShouldProcess($Name, "Reconnect $nicName to $switchName")) {
                Connect-VMNetworkAdapter -VMName $Name -Name $nicName -SwitchName $switchName | Out-Null
            }
        }
    }

    if (-not (Test-Path $destVhd)) {
        if ($PSCmdlet.ShouldProcess($destVhd, 'Copy VyOS template VHDX')) {
            Copy-Item -Path $VhdPath -Destination $destVhd -Force
        }
    }

    $hardDisk = Get-VMHardDiskDrive -VMName $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $hardDisk) {
        if ($PSCmdlet.ShouldProcess($Name, 'Attach cloned VHDX')) {
            Add-VMHardDiskDrive -VMName $Name -Path $destVhd | Out-Null
        }
    }

    New-VyosSeedIso -Name $Name -ConfigPath $configPath -IsoPath $seedIsoPath | Out-Null

    $dvdDrive = Get-VMDvdDrive -VMName $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $dvdDrive) {
        if ($PSCmdlet.ShouldProcess($Name, 'Update seed ISO attachment')) {
            Set-VMDvdDrive -VMName $Name -Path $seedIsoPath | Out-Null
        }
    }
    else {
        if ($PSCmdlet.ShouldProcess($Name, 'Attach seed ISO')) {
            Add-VMDvdDrive -VMName $Name -Path $seedIsoPath | Out-Null
        }
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Disable automatic checkpoints')) {
        Set-VM -Name $Name -AutomaticCheckpointsEnabled $false | Out-Null
    }

    $bootDisk = Get-VMHardDiskDrive -VMName $Name | Select-Object -First 1
    if ($null -ne $bootDisk) {
        if ($PSCmdlet.ShouldProcess($Name, 'Set disk-first boot and disable secure boot')) {
            Set-VMFirmware -VMName $Name -EnableSecureBoot Off -FirstBootDevice $bootDisk | Out-Null
        }
    }

    if ($ExternalUplink) {
        if ($PSCmdlet.ShouldProcess($Name, "Apply VLAN $ExternalVlanId to eth0")) {
            Set-VMNetworkAdapterVlan -VMName $Name -VMNetworkAdapterName 'eth0' -Access -VlanId $ExternalVlanId | Out-Null
        }
    }

    Get-VM -Name $Name
}

function Start-VyosHyperVVm {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VmName,

        [int]$WaitTimeSec = 0
    )

    if ($PSCmdlet.ShouldProcess($VmName, 'Start VyOS VM')) {
        Start-VM -Name $VmName | Out-Null
    }

    if ($WaitTimeSec -gt 0) {
        Start-Sleep -Seconds $WaitTimeSec
    }

    Get-VM -Name $VmName
}

function Invoke-VyosRouterLab {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$VhdPath = $script:DefaultVhdPath,

        [string]$VirtualDiskRoot = $script:DefaultVirtualDiskRoot,

        [string]$SwitchPrefix = $script:DefaultSwitchPrefix,

        [string]$ExternalSwitchName = $script:DefaultExternalSwitchName,

        [int]$ExternalVlanId = $script:DefaultExternalVlanId,

        [switch]$Recreate
    )

    if (-not (Test-Path $VhdPath)) {
        throw "VHD path $VhdPath not found"
    }

    $siteNames = @('dc1', 'dc2', 'dc3')
    foreach ($site in $siteNames) {
        foreach ($switchName in (Get-VyosSiteSwitches -Site $site -SwitchPrefix $SwitchPrefix)) {
            Ensure-VyosInternalSwitch -Name $switchName
        }
    }

    Ensure-VyosInternalSwitch -Name "${SwitchPrefix}transit"

    if (-not (Get-VMSwitch -Name $ExternalSwitchName -ErrorAction SilentlyContinue)) {
        throw "External switch '$ExternalSwitchName' was not found. Create it first and bind it to the physical NIC carrying VLAN $ExternalVlanId."
    }

    if ($Recreate) {
        Remove-VyosLab -CleanupFiles -VirtualDiskRoot $VirtualDiskRoot | Out-Null
    }

    $routers = @(
        @{ Name = 'router-center'; Switches = @($ExternalSwitchName, "${SwitchPrefix}transit"); External = $true },
        @{ Name = 'router-dc1'; Switches = @(Get-VyosSiteSwitches -Site 'dc1' -SwitchPrefix $SwitchPrefix); External = $false },
        @{ Name = 'router-dc2'; Switches = @(Get-VyosSiteSwitches -Site 'dc2' -SwitchPrefix $SwitchPrefix); External = $false },
        @{ Name = 'router-dc3'; Switches = @(Get-VyosSiteSwitches -Site 'dc3' -SwitchPrefix $SwitchPrefix); External = $false }
    )

    foreach ($router in $routers) {
        if ($router.External) {
            New-VyosHyperVVm -Name $router.Name -Switches $router.Switches -ExternalUplink -VhdPath $VhdPath -VirtualDiskRoot $VirtualDiskRoot -ExternalVlanId $ExternalVlanId | Out-Null
        }
        else {
            New-VyosHyperVVm -Name $router.Name -Switches $router.Switches -VhdPath $VhdPath -VirtualDiskRoot $VirtualDiskRoot | Out-Null
        }
    }

    Get-VM -Name @('router-center', 'router-dc1', 'router-dc2', 'router-dc3')
}

Export-ModuleMember -Function Convert-VyosConfigToCloudInitUserData, Get-VyosSeedMetaData, New-VyosSeedIso, New-VyosHyperVVm, Start-VyosHyperVVm, Remove-VyosLab, Invoke-VyosRouterLab