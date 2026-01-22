param(
    [string]$RepoRoot,
    [string]$InstallIsoPath = 'C:\Users\adminlocal\Downloads\vyos-2025.11-generic-amd64.iso',
    [string]$IsoWorkingRoot,
    [UInt64]$MemoryStartupBytes = 1GB,
    [int]$CpuCount = 1,
    [bool]$DynamicMemoryEnabled = $false,
    [bool]$AutomaticCheckpointsEnabled = $false,
    [switch]$UseExternalAdapters,
    [string]$AzureExternalAdapterName,
    [string]$OnPremUnderlayAdapterName,
    [string]$VmRoot,
    [string]$VhdRoot,
    [switch]$CreateSwitches = $true,
    [switch]$CreateVms = $true,
    [switch]$CreateConfigIsos = $true,
    [switch]$AttachDvds = $true,
    [switch]$RebuildConfigIsos,
    [switch]$ReattachDvds,
    [switch]$SkipPreflight,
    [switch]$DisableDhcpEth0,
    [ValidateSet('ConfigOnly','NoCloud')]
    [string]$ConfigIsoMode = 'ConfigOnly',
    [switch]$UseVhdTemplate,
    [string]$VhdTemplatePath = 'E:\Hard Disk Templates\vyos-1.4.4-hyperv-amd64.vhdx',
    [ValidateSet(0,1,2)]
    [int]$VmGeneration = 0,
    [bool]$SecureBootEnabled = $false,
    [ValidateSet('MicrosoftUEFICertificateAuthority','MicrosoftWindows')]
    [string]$SecureBootTemplate = 'MicrosoftUEFICertificateAuthority',
    [switch]$OverwriteExistingVhd
)

$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Preflight {
    param([bool]$CheckIsoTool)

    if (-not (Test-IsAdmin)) {
        throw 'This script must be run as Administrator.'
    }

    if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
        throw 'Hyper-V PowerShell module not found. Enable the Hyper-V feature and retry.'
    }

    Import-Module Hyper-V -ErrorAction Stop

    if (-not (Get-Command -Name Get-VMHost -ErrorAction SilentlyContinue)) {
        throw 'Hyper-V cmdlets not available. Ensure the Hyper-V role is installed.'
    }

    if ($CheckIsoTool) {
        $oscdimg = Get-Command -Name oscdimg.exe -ErrorAction SilentlyContinue
        $mkisofs = Get-Command -Name mkisofs -ErrorAction SilentlyContinue
        $geniso = Get-Command -Name genisoimage -ErrorAction SilentlyContinue

        if (-not $oscdimg -and -not $mkisofs -and -not $geniso) {
            throw 'ISO tool not found. Install Windows ADK (oscdimg.exe) or mkisofs/genisoimage to build config ISOs.'
        }
    }
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$createSwitchesScript = Join-Path $RepoRoot 'scripts\create-hyperv-switches.ps1'
$bootstrapScript = Join-Path $RepoRoot 'scripts\bootstrap-vyos.ps1'

if (-not (Test-Path $createSwitchesScript)) {
    throw "Missing script: $createSwitchesScript"
}

if (-not (Test-Path $bootstrapScript)) {
    throw "Missing script: $bootstrapScript"
}

if (-not $UseVhdTemplate) {
    if (-not (Test-Path $InstallIsoPath)) {
        throw "Install ISO not found: $InstallIsoPath"
    }
}

if ($UseVhdTemplate -and [string]::IsNullOrWhiteSpace($VhdTemplatePath)) {
    throw 'VhdTemplatePath is required when UseVhdTemplate is specified.'
}

if ($UseVhdTemplate -and (-not (Test-Path $VhdTemplatePath))) {
    throw "VHDX template not found: $VhdTemplatePath"
}

if (-not $SkipPreflight) {
    Assert-Preflight -CheckIsoTool:$CreateConfigIsos
}

$vmHost = Get-VMHost
if ([string]::IsNullOrWhiteSpace($VmRoot)) {
    $VmRoot = $vmHost.VirtualMachinePath
}

if ([string]::IsNullOrWhiteSpace($VhdRoot)) {
    $VhdRoot = $vmHost.VirtualHardDiskPath
}

if ([string]::IsNullOrWhiteSpace($IsoWorkingRoot)) {
    $IsoWorkingRoot = Join-Path $RepoRoot 'artifacts\vyos-config-iso'
}

if ($CreateVms -and (-not [string]::IsNullOrWhiteSpace($VhdRoot))) {
    $existingVhds = Get-ChildItem -Path $VhdRoot -Filter 'vyos-*.vhdx' -ErrorAction SilentlyContinue
    if ($existingVhds) {
        Write-Host '[WARN] Existing VyOS VHDX files found. Use -OverwriteExistingVhd to replace, or keep to reuse.'
    }
}

if ($UseVhdTemplate -and $ConfigIsoMode -ne 'NoCloud') {
    Write-Host '[WARN] For VHDX boot, forcing ConfigIsoMode=NoCloud.'
    $ConfigIsoMode = 'NoCloud'
}

$effectiveGeneration = if ($VmGeneration -eq 0) {
    if ($UseVhdTemplate) { 2 } else { 1 }
} else {
    $VmGeneration
}

$vmDefinitions = @(
    @{ Name = 'vyos-az-ext'; Config = 'configs\azure\external.vyos'; Switches = @('Default Switch','az-wan') },
    @{ Name = 'vyos-az-out'; Config = 'configs\azure\outside.vyos'; Switches = @('az-wan','az-dren') },
    @{ Name = 'vyos-az-grey'; Config = 'configs\azure\grey.vyos'; Switches = @('az-dren','az-sdpc','az-sdpg','az-sdpt','az-avd') },
    @{ Name = 'vyos-az-inside'; Config = 'configs\azure\inside.vyos'; Switches = @('az-sdpc','az-domain','az-domsvc') },
    @{ Name = 'vyos-az-dev'; Config = 'configs\azure\developer.vyos'; Switches = @('az-sdpc','az-dev','az-devsvc') },
    @{ Name = 'vyos-az-sandbox'; Config = 'configs\azure\sandbox.vyos'; Switches = @('az-sdpc','az-seg') },
    @{ Name = 'vyos-onp-out'; Config = 'configs\onprem\outside.vyos'; Switches = @('onp-dren','az-dren') },
    @{ Name = 'vyos-onp-grey'; Config = 'configs\onprem\grey.vyos'; Switches = @('onp-dren','onp-sdpc','onp-sdpg','onp-sdpt','onp-avd') },
    @{ Name = 'vyos-onp-inside'; Config = 'configs\onprem\inside.vyos'; Switches = @('onp-sdpc','onp-domain','onp-domsvc') },
    @{ Name = 'vyos-onp-dev'; Config = 'configs\onprem\developer.vyos'; Switches = @('onp-sdpc','onp-dev','onp-devsvc') },
    @{ Name = 'vyos-onp-sandbox'; Config = 'configs\onprem\sandbox.vyos'; Switches = @('onp-sdpc','onp-seg','onp-hwil') }
)

function Ensure-Vm {
    param(
        [string]$Name,
        [string[]]$Switches,
        [int]$Generation,
        [bool]$UseVhdTemplate,
        [string]$VhdTemplatePath,
        [switch]$OverwriteExistingVhd
    )

    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "[OK] VM exists: $Name"
        return
    }

    $vhdPath = Join-Path $VhdRoot ($Name + '.vhdx')
    $firstSwitch = $Switches[0]

    if ($UseVhdTemplate) {
        if (Test-Path $vhdPath) {
            if ($OverwriteExistingVhd) {
                Remove-Item -Path $vhdPath -Force
                Write-Host "[INFO] Removed existing VHDX: $vhdPath"
            } else {
                Write-Host "[INFO] Reusing existing VHDX: $vhdPath"
            }
        }

        if (-not (Test-Path $vhdPath)) {
            Copy-Item -Path $VhdTemplatePath -Destination $vhdPath -Force
            Write-Host "[INFO] Copied VHDX template to: $vhdPath"
        }

        New-VM -Name $Name -Generation $Generation -MemoryStartupBytes $MemoryStartupBytes -NoVHD -SwitchName $firstSwitch | Out-Null
        Add-VMHardDiskDrive -VMName $Name -Path $vhdPath | Out-Null
    } else {
        if (Test-Path $vhdPath) {
            if ($OverwriteExistingVhd) {
                Remove-Item -Path $vhdPath -Force
                Write-Host "[INFO] Removed existing VHDX: $vhdPath"
                New-VM -Name $Name -Generation 1 -MemoryStartupBytes $MemoryStartupBytes -NewVHDPath $vhdPath -NewVHDSizeBytes 40GB -SwitchName $firstSwitch | Out-Null
            } else {
                Write-Host "[INFO] Reusing existing VHDX: $vhdPath"
                New-VM -Name $Name -Generation 1 -MemoryStartupBytes $MemoryStartupBytes -NoVHD -SwitchName $firstSwitch | Out-Null
                Add-VMHardDiskDrive -VMName $Name -Path $vhdPath | Out-Null
            }
        } else {
            New-VM -Name $Name -Generation 1 -MemoryStartupBytes $MemoryStartupBytes -NewVHDPath $vhdPath -NewVHDSizeBytes 40GB -SwitchName $firstSwitch | Out-Null
        }
    }
    Rename-VMNetworkAdapter -VMName $Name -NewName 'eth0' | Out-Null

    for ($i = 1; $i -lt $Switches.Count; $i++) {
        $switch = $Switches[$i]
        $nicName = "eth$($i)"
        Add-VMNetworkAdapter -VMName $Name -SwitchName $switch -Name $nicName | Out-Null
    }

    Set-VMProcessor -VMName $Name -Count $CpuCount | Out-Null
    if ($Generation -eq 2) {
        if ($SecureBootEnabled) {
            Set-VMFirmware -VMName $Name -EnableSecureBoot On -SecureBootTemplate $SecureBootTemplate | Out-Null
        } else {
            Set-VMFirmware -VMName $Name -EnableSecureBoot Off | Out-Null
        }
    } else {
        Set-VMBios -VMName $Name -StartupOrder @('CD','IDE','LegacyNetworkAdapter','Floppy') | Out-Null
    }
    Set-VMMemory -VMName $Name -DynamicMemoryEnabled $DynamicMemoryEnabled | Out-Null
    Set-VM -VMName $Name -AutomaticCheckpointsEnabled $AutomaticCheckpointsEnabled | Out-Null

    Write-Host "[NEW] VM created: $Name ($($Switches.Count) NICs)"
}

function Set-VmDvds {
    param(
        [string]$Name,
        [string]$InstallIso,
        [string]$ConfigIso,
        [bool]$UseVhdTemplate
    )

    $vm = Get-VM -Name $Name -ErrorAction Stop
    $isGen2 = $vm.Generation -eq 2

    $controllerNumber = if ($isGen2) { 0 } else { 1 }
    $existingDvds = Get-VMDvdDrive -VMName $Name | Where-Object { $_.ControllerNumber -eq $controllerNumber }
    $diskLocations = Get-VMHardDiskDrive -VMName $Name | Where-Object { $_.ControllerNumber -eq $controllerNumber } | Select-Object -ExpandProperty ControllerLocation
    $usedLocations = @($diskLocations + ($existingDvds | Select-Object -ExpandProperty ControllerLocation)) | Sort-Object -Unique

    $validLocations = if ($isGen2) { 0..63 } else { 0..1 }
    $firstFree = $validLocations | Where-Object { $usedLocations -notcontains $_ } | Select-Object -First 1

    if ($UseVhdTemplate) {
        $dvd0 = $existingDvds | Select-Object -First 1
        if ($null -ne $dvd0) {
            Set-VMDvdDrive -VMName $Name -ControllerNumber $dvd0.ControllerNumber -ControllerLocation $dvd0.ControllerLocation -Path $ConfigIso | Out-Null
        } else {
            if ($null -eq $firstFree) {
                throw "No available DVD locations on controller $controllerNumber for $Name."
            }
            Add-VMDvdDrive -VMName $Name -ControllerNumber $controllerNumber -ControllerLocation $firstFree -Path $ConfigIso | Out-Null
        }

        $extraDvds = $existingDvds | Select-Object -Skip 1
        if ($extraDvds) {
            $extraDvds | ForEach-Object { Remove-VMDvdDrive -VMName $Name -ControllerNumber $_.ControllerNumber -ControllerLocation $_.ControllerLocation }
        }
    } else {
        $dvd0 = $existingDvds | Select-Object -First 1
        $dvd1 = $existingDvds | Select-Object -Skip 1 -First 1

        if ($null -ne $dvd0) {
            Set-VMDvdDrive -VMName $Name -ControllerNumber $dvd0.ControllerNumber -ControllerLocation $dvd0.ControllerLocation -Path $InstallIso | Out-Null
        } else {
            if ($null -eq $firstFree) {
                throw "No available DVD locations on controller $controllerNumber for $Name."
            }
            Add-VMDvdDrive -VMName $Name -ControllerNumber $controllerNumber -ControllerLocation $firstFree -Path $InstallIso | Out-Null
            $usedLocations = @($usedLocations + $firstFree) | Sort-Object -Unique
            $firstFree = $validLocations | Where-Object { $usedLocations -notcontains $_ } | Select-Object -First 1
        }

        if ($null -ne $dvd1) {
            Set-VMDvdDrive -VMName $Name -ControllerNumber $dvd1.ControllerNumber -ControllerLocation $dvd1.ControllerLocation -Path $ConfigIso | Out-Null
        } else {
            if ($null -eq $firstFree) {
                throw "No available DVD locations on controller $controllerNumber for $Name."
            }
            Add-VMDvdDrive -VMName $Name -ControllerNumber $controllerNumber -ControllerLocation $firstFree -Path $ConfigIso | Out-Null
        }
    }

    Write-Host "[OK] DVD set on $Name (controller $controllerNumber)"
}

function Test-VmDvds {
    param(
        [string]$Name,
        [string]$InstallIso,
        [string]$ConfigIso,
        [bool]$UseVhdTemplate
    )

    $dvds = Get-VMDvdDrive -VMName $Name

    if ($UseVhdTemplate) {
        if ($dvds.Count -ne 1) {
            return $false
        }

        return ($dvds[0].Path -eq $ConfigIso)
    }

    if ($dvds.Count -lt 2) {
        return $false
    }

    $paths = $dvds | Select-Object -ExpandProperty Path
    return ($paths -contains $InstallIso -and $paths -contains $ConfigIso)
}

if ($CreateSwitches) {
    & $createSwitchesScript -AzureExternalAdapterName $AzureExternalAdapterName -OnPremUnderlayAdapterName $OnPremUnderlayAdapterName -UseExternalAdapters:$UseExternalAdapters | Out-Host
}

foreach ($vm in $vmDefinitions) {
    $vmName = $vm.Name
    $configPath = Join-Path $RepoRoot $vm.Config
    $isoSuffix = if ($ConfigIsoMode -eq 'NoCloud') { 'seed' } else { 'configonly' }
    $configIsoPath = Join-Path $IsoWorkingRoot ("$vmName.$isoSuffix.iso")

    if (-not (Test-Path $configPath)) {
        throw "Config file not found for ${vmName}: $configPath"
    }

    if ($CreateVms) {
        Ensure-Vm -Name $vmName -Switches $vm.Switches -Generation $effectiveGeneration -UseVhdTemplate:$UseVhdTemplate -VhdTemplatePath $VhdTemplatePath -OverwriteExistingVhd:$OverwriteExistingVhd
    }

    if ($CreateConfigIsos) {
        if ((-not $RebuildConfigIsos) -and (Test-Path $configIsoPath)) {
            Write-Host "[OK] Config ISO exists: $configIsoPath"
        } else {
            & $bootstrapScript -ConfigPath $configPath -VmName $vmName -IsoOutputPath $configIsoPath -IsoWorkingRoot $IsoWorkingRoot -SkipAttach -DisableDhcpEth0:$DisableDhcpEth0 -IsoMode $ConfigIsoMode | Out-Host
        }
    }

    if ($AttachDvds) {
        if (-not (Test-Path $configIsoPath)) {
            throw "Config ISO not found for ${vmName}: $configIsoPath"
        }

        if (-not $ReattachDvds -and (Test-VmDvds -Name $vmName -InstallIso $InstallIsoPath -ConfigIso $configIsoPath -UseVhdTemplate:$UseVhdTemplate)) {
            Write-Host "[OK] DVDs already set: $vmName"
        } else {
            Set-VmDvds -Name $vmName -InstallIso $InstallIsoPath -ConfigIso $configIsoPath -UseVhdTemplate:$UseVhdTemplate
        }
    }

    if ($UseVhdTemplate -and $effectiveGeneration -eq 2) {
        $disk = Get-VMHardDiskDrive -VMName $vmName | Select-Object -First 1
        $dvd = Get-VMDvdDrive -VMName $vmName | Select-Object -First 1
        if ($null -ne $disk) {
            if ($null -ne $dvd) {
                Set-VMFirmware -VMName $vmName -BootOrder $disk, $dvd | Out-Null
            } else {
                Set-VMFirmware -VMName $vmName -BootOrder $disk | Out-Null
            }
        }
    }
}

Write-Host 'Done.'
