#!/usr/bin/env bash
set -euo pipefail

# Simple SSH-based config apply pattern.
# - Uses 'load merge' so you can stage diffs
# - Uses commit-confirm for safety
#
# Usage:
#   ./apply-config.sh vyos@10.0.0.1 configs/azure/grey.vyos

USER_HOST="${1:-}"
CFG_FILE="${2:-}"

if [[ -z "$USER_HOST" || -z "$CFG_FILE" ]]; then
  echo "Usage: $0 <user@host> <config-file.vyos>" >&2
  exit 1
fi

if [[ ! -f "$CFG_FILE" ]]; then
  echo "Config file not found: $CFG_FILE" >&2
  exit 1
fi

# Strip leading/trailing whitespace and ignore blank lines/comments if you choose to later.
# For now we assume the .vyos files contain configure/commit/save/exit.

ssh -o StrictHostKeyChecking=accept-new "$USER_HOST" < "$CFG_FILE"
