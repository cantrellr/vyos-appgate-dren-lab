<#
Create Hyper-V vSwitches used by the multicluster lab.

NOTE: This helper creates Internal switches; change `-SwitchType` and `-NetAdapterName`
to match your host network adapters for External switches.
#>

$sites = @('dc1','dc2','dc3')

$switches = @()
foreach ($s in $sites) {
    $switches += @{ Name = "vSwitch-$s-kubes"; Adapter = '<Adapter-Name-1>' }
    $switches += @{ Name = "vSwitch-$s-storage"; Adapter = '<Adapter-Name-1>' }
    $switches += @{ Name = "vSwitch-$s-domain"; Adapter = '<Adapter-Name-1>' }
    $switches += @{ Name = "vSwitch-$s-seg1"; Adapter = '<Adapter-Name-1>' }
}

# Central transit switch
$switches += @{ Name = 'vSwitch-transit'; Adapter = '<Adapter-Name-Transit>' }

foreach ($s in $switches) {
    if (-not (Get-VMSwitch -Name $s.Name -ErrorAction SilentlyContinue)) {
        Write-Host "Creating vSwitch $($s.Name) (adapter: $($s.Adapter))"
        if ($s.Adapter -like '<Adapter-Name*>' -or $s.Adapter -eq '<Adapter-Name-Transit>') {
            # Placeholder adapter names detected — create internal switch for lab use
            New-VMSwitch -Name $s.Name -SwitchType Internal | Out-Null
        } else {
            # Try creating external switch bound to adapter name provided by user
            try {
                New-VMSwitch -Name $s.Name -NetAdapterName $s.Adapter -SwitchType External | Out-Null
            } catch {
                Write-Warning "Failed to create External switch for adapter $($s.Adapter). Creating Internal switch instead."
                New-VMSwitch -Name $s.Name -SwitchType Internal | Out-Null
            }
        }
    } else {
        Write-Host "vSwitch $($s.Name) already exists, skipping."
    }
}

Write-Host 'Done. Verify switches with: Get-VMSwitch'
