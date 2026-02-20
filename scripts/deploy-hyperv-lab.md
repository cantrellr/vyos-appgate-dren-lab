**deploy-hyperv-lab.ps1 — Technical README**

- **Location:** scripts/deploy-hyperv-lab.ps1
- **Purpose:** Full Hyper‑V lab orchestration for the VyOS AppGate+DREN lab: create switches, create VMs (optionally from a VHD template or install ISO), build/attach per-VM config ISOs, set DVD/boot order, and optionally export VM hardware IDs.
- **Invocation:** Run from an elevated PowerShell prompt. Example:

  .\scripts\deploy-hyperv-lab.ps1 -RepoRoot (Get-Location) -InstallIsoPath 'C:\path\vyos.iso' -UseVhdTemplate -VhdTemplatePath 'C:\templates\vyos.vhdx'

High-level workflow
- Preflight checks (`Assert-Preflight`): confirms running as Administrator, Hyper‑V PowerShell module availability, and (optionally) presence of an ISO creation tool when building config ISOs.
- Uses `scripts\create-hyperv-switches.ps1` to create the lab switches when `-CreateSwitches` is set.
- Defines a `vmDefinitions` array with 11 VM definitions (name, config path, and list of switches to attach). This array is the authoritative mapping of VM -> config -> NIC order for the lab.
- For each VM definition:
  - `Ensure-Vm`: idempotently creates the VM, creating or reusing VHDX files from either a VHD template (fast path) or by creating a new VHDX. It renames the first network adapter to `eth0` and adds `eth1..ethN` in order.
  - Create per-VM config ISO via `scripts\bootstrap-vyos.ps1` (unless config ISO exists and `-RebuildConfigIsos` not specified).
  - `Set-VmDvds`: attach the install ISO and config ISO in appropriate DVD controller/locations. Logic differs when using a VHD template vs fresh install to minimize DVD usage.
  - When using a VHD template and Gen2 VMs, it also configures VM firmware boot order to prefer the disk.
- Optionally start all VMs and run `export-vyos-hwids.ps1` to capture MAC -> `set interfaces ethernet ... hw-id` lines.

Important flags & behaviors
- `-UseVhdTemplate`: copy an existing VHDX template per VM rather than creating a new VHD from install ISO. Faster and commonly used for lab restores.
- `-OverwriteExistingVhd`: when set, removes existing VHDX before writing a new one from template.
- `-CreateConfigIsos` / `-RebuildConfigIsos`: control ISO generation; when creating ISOs, `-ConfigIsoMode` (`ConfigOnly|NoCloud`) controls the format.
- `-AttachDvds` / `-ReattachDvds`: control whether DVDs are attached to VMs.
- `-ExportHwIds`: prompts user to start VMs and run the hw-id export helper script, which produces `artifacts\vyos-hwids.vyos` by default.

Idempotency & safety
- `Ensure-Vm`, `Ensure-Switch`, and the DVD handling functions attempt to be idempotent: they check for existing resources and either reuse or update them.
- The script writes helpful status lines (`[OK]`, `[NEW]`, `[INFO]`, `[WARN]`).

Dependencies & required environment
- Must run on a Windows host with Hyper‑V role installed and the Hyper‑V PowerShell module available.
- If `-CreateConfigIsos` is set, requires `oscdimg.exe` or `mkisofs`/`genisoimage` available in PATH (or installed via Windows ADK).

Operational notes
- NIC order matters: `eth0` is OOB and is the first adapter added; subsequent `ethN` adapters follow the `Switches` list in each `vmDefinitions` entry — do not reorder switches arbitrarily.
- If using a template VHDX, the script attempts to copy and reuse VHDX files; this speeds deployment but requires that the template is compatible with the target VM generation and firmware settings.

Example: minimal deploy creating VMs and config ISOs

  .\scripts\deploy-hyperv-lab.ps1 -RepoRoot (Get-Location) -InstallIsoPath 'C:\Downloads\vyos.iso' -CreateSwitches -CreateVms -CreateConfigIsos

