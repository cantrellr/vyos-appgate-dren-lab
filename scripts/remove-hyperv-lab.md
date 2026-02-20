**remove-hyperv-lab.ps1 — Technical README**

- **Location:** scripts/remove-hyperv-lab.ps1
- **Purpose:** Tear down the Hyper‑V lab by removing VMs, optional VHDs, vSwitches, generated ISOs, and hardware ID output files. Supports safety via `ShouldProcess` semantics.
- **Invocation:** `.	ools\remove-hyperv-lab.ps1 [-RemoveVhds] [-RemoveSwitches] [-RemoveIsos] [-RemoveHwIds]` (run in elevated PowerShell)

Behavior and safety
- Accepts lists of VM and Switch names with sensible defaults matching the lab inventory. Uses `Get-VM -Name <vm>` to detect presence and then `Remove-VM` when `ShouldProcess` approves the action.
- If `-RemoveVhds` is passed the script finds VHD paths attached to the removed VM and also deletes those files from disk after VM removal.
- If `-RemoveSwitches` is passed it iterates the `SwitchNames` list and attempts `Remove-VMSwitch -Force`, logging warnings on failure.
- After VM/switch removal the script optionally removes ISO files in the `artifacts\vyos-config-iso` working directory and the `artifacts\vyos-hwids.vyos` file.

Idempotency & common workflows
- The script is written to be safe when invoked multiple times: it checks for resource existence and skips absent items.
- Use `-RemoveVhds` when you want to free disk space; otherwise keep VHDX files to speed future redeploys.

Examples
- Remove VMs and ISOs, but keep VHDs and switches:

  .\scripts\remove-hyperv-lab.ps1 -RemoveIsos

 - Remove everything including VHDs and switches (destructive):

  .\scripts\remove-hyperv-lab.ps1 -RemoveVhds -RemoveSwitches -RemoveIsos -RemoveHwIds

