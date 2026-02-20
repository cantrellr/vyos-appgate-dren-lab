**export-vyos-hwids.ps1 — Technical README**

- **Location:** scripts/export-vyos-hwids.ps1
- **Purpose:** Query the Hyper‑V VM network adapters for MAC addresses and produce VyOS `set interfaces ethernet <if> hw-id '<mac>'` lines for each VM, suitable for pasting into VyOS configs to pin MAC-to-interface mappings.
- **Invocation:** `.uild\export-vyos-hwids.ps1 [-VmNamePatterns @('vyos-az-*','vyos-onp-*')] [-OutputPath <path>]`

Behavior
- Gathers VM names by expanding the provided `VmNamePatterns` (defaults to `vyos-az-*`, `vyos-onp-*`) via `Get-VM -Name <pattern>`.
- For each matched VM, enumerates `Get-VMNetworkAdapter -VMName <vm>` and converts adapter MAC addresses into a normalized colon-separated lower-case form.
- Emits lines in the form: `set interfaces ethernet <adapter.Name> hw-id '<mac>'` with a comment header `# <vmName>`.
- If `-OutputPath` is not specified the script prints to stdout; otherwise it writes UTF‑8 output to the target file.

Implementation details
- `Convert-MacAddress` normalizes formats like `00-15-5D-...` or `00155D...` into `00:15:5d:...`.
- Sorts adapter records by `Name` to produce deterministic ordering.

Use cases & examples
- Use after the VMs are created and network adapters have stable MAC addresses to generate a hw-id config file that can be committed into VyOS configurations.

Example
- Write hw-id lines to `artifacts\vyos-hwids.vyos`:

  .\scripts\export-vyos-hwids.ps1 -OutputPath artifacts\vyos-hwids.vyos

