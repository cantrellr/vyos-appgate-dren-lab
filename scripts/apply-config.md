**apply-config.sh — Technical README**

- **Location:** scripts/apply-config.sh
- **Purpose:** Apply a VyOS configuration file to a running VyOS VM over SSH by streaming the config file into an interactive shell on the remote device.
- **Invocation:** `./scripts/apply-config.sh <user@host> <config-file.vyos>`

Detailed behavior
- The script validates two positional args: `USER_HOST` (`user@host`) and `CFG_FILE` (local path).
- It exits non‑zero when arguments are missing or when the specified config file does not exist.
- It uses `ssh -o StrictHostKeyChecking=accept-new "$USER_HOST" < "$CFG_FILE"` to send the config file contents over SSH to the remote shell.

Assumptions & usage notes
- The target host must accept the connecting user and allow running the commands contained in the `.vyos` file (usually `configure`, a set of `set` commands, `commit`/`save`, and `exit`).
- The `.vyos` file should contain the exact CLI commands you want executed; the script is intentionally minimal and streams the file raw to the remote shell.
- The script header mentions `load merge` and `commit-confirm` as patterns to support safe staging; those behaviors must be implemented inside the `.vyos` files themselves if desired (e.g., include `configure`, `load merge /tmp/partial.vyos`, `commit confirm 120`).

Security & operational notes
- `StrictHostKeyChecking=accept-new` will automatically add unknown host keys; in automated or CI environments prefer provisioning known_host entries or configuring a more restrictive policy.
- This script does not perform any parsing, templating, nor syntactic validation of the `.vyos` content — responsibility is on the operator.

Examples
- Apply local config to a VyOS VM over SSH:

  ./scripts/apply-config.sh vyos@10.255.255.11 configs/azure/az-core.vyos

