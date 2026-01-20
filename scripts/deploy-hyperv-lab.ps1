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
    [string]$ConfigIsoMode = 'ConfigOnly'
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

if (-not (Test-Path $InstallIsoPath)) {
    throw "Install ISO not found: $InstallIsoPath"
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

$vmDefinitions = @(
    @{ Name = 'vyos-az-proton-ext'; Config = 'configs\azure\external.vyos'; Switches = @('az-wan') },
    @{ Name = 'vyos-az-proton-out'; Config = 'configs\azure\outside.vyos'; Switches = @('az-wan','az-dren') },
    @{ Name = 'vyos-az-proton-grey'; Config = 'configs\azure\grey.vyos'; Switches = @('az-dren','az-sdpc','az-sdpg','az-sdpt','az-avd') },
    @{ Name = 'vyos-az-proton-inside'; Config = 'configs\azure\inside.vyos'; Switches = @('az-sdpc','az-domain','az-domsvc') },
    @{ Name = 'vyos-az-proton-dev'; Config = 'configs\azure\developer.vyos'; Switches = @('az-sdpc','az-dev','az-devsvc') },
    @{ Name = 'vyos-az-proton-sandbox'; Config = 'configs\azure\sandbox.vyos'; Switches = @('az-sdpc','az-seg') },
    @{ Name = 'vyos-onp-out'; Config = 'configs\onprem\outside.vyos'; Switches = @('onp-underlay','onp-dren') },
    @{ Name = 'vyos-onp-grey'; Config = 'configs\onprem\grey.vyos'; Switches = @('onp-dren','onp-sdpc','onp-sdpg','onp-sdpt','onp-avd') },
    @{ Name = 'vyos-onp-inside'; Config = 'configs\onprem\inside.vyos'; Switches = @('onp-sdpc','onp-domain','onp-domsvc') },
    @{ Name = 'vyos-onp-dev'; Config = 'configs\onprem\developer.vyos'; Switches = @('onp-sdpc','onp-dev','onp-devsvc') },
    @{ Name = 'vyos-onp-sandbox'; Config = 'configs\onprem\sandbox.vyos'; Switches = @('onp-sdpc','onp-seg','onp-hwil') }
)

function Ensure-Vm {
    param(
        [string]$Name,
        [string[]]$Switches
    )

    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "[OK] VM exists: $Name"
        return
    }

    $vhdPath = Join-Path $VhdRoot ($Name + '.vhdx')
    $firstSwitch = $Switches[0]

    New-VM -Name $Name -Generation 1 -MemoryStartupBytes $MemoryStartupBytes -NewVHDPath $vhdPath -NewVHDSizeBytes 40GB -SwitchName $firstSwitch | Out-Null
    Rename-VMNetworkAdapter -VMName $Name -NewName 'eth0' | Out-Null

    for ($i = 1; $i -lt $Switches.Count; $i++) {
        $switch = $Switches[$i]
        $nicName = "eth$($i)"
        Add-VMNetworkAdapter -VMName $Name -SwitchName $switch -Name $nicName | Out-Null
    }

    Set-VMProcessor -VMName $Name -Count $CpuCount | Out-Null
    Set-VMBios -VMName $Name -StartupOrder @('CD','IDE','LegacyNetworkAdapter','Floppy') | Out-Null
    Set-VMMemory -VMName $Name -DynamicMemoryEnabled $DynamicMemoryEnabled | Out-Null
    Set-VM -VMName $Name -AutomaticCheckpointsEnabled $AutomaticCheckpointsEnabled | Out-Null

    Write-Host "[NEW] VM created: $Name ($($Switches.Count) NICs)"
}

function Set-VmDvds {
    param(
        [string]$Name,
        [string]$InstallIso,
        [string]$ConfigIso
    )

    $dvd0 = Get-VMDvdDrive -VMName $Name | Where-Object { $_.ControllerNumber -eq 1 -and $_.ControllerLocation -eq 0 }
    if ($null -eq $dvd0) {
        Add-VMDvdDrive -VMName $Name -ControllerNumber 1 -ControllerLocation 0 -Path $InstallIso | Out-Null
    } else {
        Set-VMDvdDrive -VMName $Name -ControllerNumber 1 -ControllerLocation 0 -Path $InstallIso | Out-Null
    }

    $dvd1 = Get-VMDvdDrive -VMName $Name | Where-Object { $_.ControllerNumber -eq 1 -and $_.ControllerLocation -eq 1 }
    if ($null -eq $dvd1) {
        Add-VMDvdDrive -VMName $Name -ControllerNumber 1 -ControllerLocation 1 -Path $ConfigIso | Out-Null
    } else {
        Set-VMDvdDrive -VMName $Name -ControllerNumber 1 -ControllerLocation 1 -Path $ConfigIso | Out-Null
    }

    Write-Host "[OK] DVD order set: $Name"
}

function Test-VmDvds {
    param(
        [string]$Name,
        [string]$InstallIso,
        [string]$ConfigIso
    )

    $dvd0 = Get-VMDvdDrive -VMName $Name | Where-Object { $_.ControllerNumber -eq 1 -and $_.ControllerLocation -eq 0 }
    $dvd1 = Get-VMDvdDrive -VMName $Name | Where-Object { $_.ControllerNumber -eq 1 -and $_.ControllerLocation -eq 1 }

    if ($null -eq $dvd0 -or $null -eq $dvd1) {
        return $false
    }

    return ($dvd0.Path -eq $InstallIso -and $dvd1.Path -eq $ConfigIso)
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
        Ensure-Vm -Name $vmName -Switches $vm.Switches
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

        if (-not $ReattachDvds -and (Test-VmDvds -Name $vmName -InstallIso $InstallIsoPath -ConfigIso $configIsoPath)) {
            Write-Host "[OK] DVDs already set: $vmName"
        } else {
            Set-VmDvds -Name $vmName -InstallIso $InstallIsoPath -ConfigIso $configIsoPath
        }
    }
}

Write-Host 'Done.'
