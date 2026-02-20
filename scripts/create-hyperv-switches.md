**create-hyperv-switches.ps1 — Technical README**

- **Location:** scripts/create-hyperv-switches.ps1
- **Purpose:** Provision the set of Hyper‑V virtual switches used by the lab, optionally bound to physical adapters for external connectivity, and configure an OOB internal switch with host-side NAT.
- **Invocation:** `.	ools\create-hyperv-switches.ps1 [-AzureExternalAdapterName <name>] [-OnPremUnderlayAdapterName <name>] [-UseExternalAdapters]`

Behavior and algorithm
- Maintains two lists: `internalSwitches` (many private/internal switches used by router NICs) and `externalSwitches` (mapping of names to optional physical adapters for `az-wan` and `onp-ext`).
- For all `internalSwitches` the script calls `Ensure-SwitchPrivate` which creates a Private `VMSwitch` unless it already exists.
- For `vyos-oob` it calls `Ensure-SwitchInternalWithNat` which ensures the internal switch exists, assigns a host IPv4 address (`10.255.255.1/24` by default) to the host vEthernet interface, and ensures a `New-NetNat` NAT object exists to allow host NAT for VMs attached to the OOB network.
- For external switches, if `-UseExternalAdapters` is passed and a corresponding adapter name is provided, `Ensure-SwitchExternal` creates an External vSwitch bound to that adapter. If `-UseExternalAdapters` is set but no adapter specified, or if `-UseExternalAdapters` is not set, the script creates a Private switch instead (but logs a warning).

Key functions
- `Assert-AdapterExists`: validates a provided adapter name using `Get-NetAdapter` and returns a helpful error that lists available adapters on failure.
- `Ensure-SwitchPrivate`: idempotently creates a Private vSwitch when missing.
- `Ensure-SwitchExternal`: idempotently creates an External vSwitch and binds it to the specified adapter.
- `Ensure-SwitchInternalWithNat`: after creating a Private switch ensures host IP and `New-NetNat` (idempotent checks and warnings on failures).

Dependencies & permissions
- Must be run as a user with privileges to create vSwitches (`Hyper‑V` feature); running in an elevated PowerShell session is implied.
- Utilizes `Get-NetAdapter`, `New-VMSwitch`, `New-NetIPAddress`, and `New-NetNat` — available on modern Windows with Hyper‑V and networking modules.

Operational notes
- Host IP assignment relies on the vEthernet interface alias `vEthernet (<switch-name>)`; if naming differs or network policies restrict adding IPs the script will warn and skip.
- NAT creation uses a simple /24 prefix derived from the host IP and defaults to NAT name `VyosOobNat`.

Examples
- Create switches and bind external adapters:

  .\scripts\create-hyperv-switches.ps1 -AzureExternalAdapterName 'Ethernet 2' -OnPremUnderlayAdapterName 'Ethernet 3' -UseExternalAdapters

