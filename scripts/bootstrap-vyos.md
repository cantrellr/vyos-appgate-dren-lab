**bootstrap-vyos.ps1 — Technical README**

- **Location:** scripts/bootstrap-vyos.ps1
- **Purpose:** Build a cloud-init/config ISO (either NoCloud or a simple config-only ISO) that contains VyOS configuration and optional cloud-init payloads, and optionally attach it to a Hyper‑V VM's DVD drive.
- **Invocation (PowerShell):** `.ootstrap-vyos.ps1 -ConfigPath <path> -VmName <name> [-IsoOutputPath <path>] [-IsoMode <ConfigOnly|NoCloud>] [options]`

Primary responsibilities
- Reads a VyOS `configs/*.vyos` file and converts it into one of two ISO modes:
  - `ConfigOnly`: writes a `config.vyos` plus an `apply-config.sh` helper which mounts the CD-ROM and applies the config on the target VM (the ISO label `VYOSCFG`).
  - `NoCloud`: emits `user-data`, `meta-data`, and optional `network-config` files suitable for EC2/NoCloud cloud-init ingestion (ISO label `CIDATA`).
- Optionally disables DHCP for `eth0` by emitting a `network-config` file in the NoCloud mode.
- Writes the ISO using `oscdimg.exe`, `mkisofs`, or `genisoimage`, depending on what's available.
- Optionally attaches the produced ISO to a Hyper‑V VM's DVD drive unless `-SkipAttach` is passed.

Key parameters
- `-ConfigPath` (required): path to the local `.vyos` config file.
- `-VmName` (required): VM name used to derive ISO filenames and for final attachment.
- `-IsoMode`: `ConfigOnly` (default) or `NoCloud` (cloud-init seed). `ConfigOnly` creates `config.vyos` and `apply-config.sh`; `NoCloud` builds `user-data`/`meta-data`.
- `-DisableDhcpEth0`: emits network-config disabling DHCP for `eth0` in NoCloud mode.
- `-SkipAttach`: Do not attach ISO to VM — useful when generating ISO only.

Implementation details
- `Get-VyosHostNameFromConfig` scans the config file for `set system host-name` using a regex and returns the host name to help select an ISO output basename.
- For `ConfigOnly` the script removes CLI control words (`configure`, `commit`, `save`, `exit`) before writing the `config.vyos` file and constructs a small `apply-config.sh` which mounts the CD-ROM, sources `config.vyos` in a `configure` session, `commit`/`save` and reboots.
- Temporary work happens in a random temp directory under the working root; that directory is always removed in a `finally` block.
- ISO creation order: prefer `oscdimg.exe` (Windows ADK), then `mkisofs`, then `genisoimage`.

Dependencies
- PowerShell (Windows). Requires either `oscdimg.exe` (Windows ADK) or `mkisofs`/`genisoimage` in PATH to produce ISOs.
- If attaching to Hyper‑V: the `Hyper-V` PowerShell module cmdlets `Get-VMDvdDrive`, `Add-VMDvdDrive` and `Set-VMDvdDrive` must be available.

Operational notes & caveats
- The script writes UTF‑8 files without BOM for `config.vyos` and `apply-config.sh`.
- The produced `apply-config.sh` expects to run inside a VyOS appliance with basic mount tools and that the CD-ROM device will be `/dev/sr1`, `/dev/sr0`, or `/dev/cdrom`.
- When using `NoCloud` mode, the `user-data` is plain cloud-init content with the VyOS CLI commands embedded under `vyos_config_commands` — cloud-init must support that custom field or a wrapper must be used on the VM to transform cloud-init into VyOS CLI actions.

Example
- Create a config-only ISO and attach it to VM `vyos-az-core`:

  .\scripts\bootstrap-vyos.ps1 -ConfigPath configs\azure\core.vyos -VmName vyos-az-core

