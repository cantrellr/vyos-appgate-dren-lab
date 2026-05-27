<#
Create Hyper-V vSwitches used by the multicluster lab.

NOTE: This helper creates Internal switches; change `-SwitchType` and `-NetAdapterName`
to match your host network adapters for External switches.
#>

$switches = @(
    @{ Name = 'vSwitch-j64manager'; Adapter = '<Adapter-Name-1>' },
    @{ Name = 'vSwitch-j64domain';  Adapter = '<Adapter-Name-2>' },
    @{ Name = 'vSwitch-j52domain';  Adapter = '<Adapter-Name-3>' },
    @{ Name = 'vSwitch-r01domain';  Adapter = '<Adapter-Name-4>' }
)

foreach ($s in $switches) {
    if (-not (Get-VMSwitch -Name $s.Name -ErrorAction SilentlyContinue)) {
        Write-Host "Creating vSwitch $($s.Name) (adapter: $($s.Adapter))"
        if ($s.Adapter -eq '<Adapter-Name-1>' -or $s.Adapter -eq '<Adapter-Name-2>' -or $s.Adapter -eq '<Adapter-Name-3>' -or $s.Adapter -eq '<Adapter-Name-4>') {
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
