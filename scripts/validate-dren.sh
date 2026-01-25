#!/usr/bin/env bash
set -euo pipefail

# validate-dren.sh
# Run this on a VyOS edge router (Azure or On-prem) to quickly validate DREN policy behavior.
#
# Usage:
#   bash validate-dren.sh <peer_dren_ip>
# Example:
#   bash validate-dren.sh 100.255.0.2

PEER="${1:-}"
if [[ -z "${PEER}" ]]; then
  echo "Usage: $0 <peer_dren_ip>"
  exit 2
fi

echo "[*] ICMP: ping ${PEER}"
ping -c 3 "${PEER}" || true
echo

echo "[*] TCP/22 (should DROP / timeout)"
timeout 4 bash -c "</dev/tcp/${PEER}/22" && echo "UNEXPECTED: TCP/22 reachable" || echo "OK: TCP/22 blocked (expected)"
echo

echo "[*] TCP/443 (should ALLOW; likely 'connection refused' if nothing listening)"
timeout 4 bash -c "</dev/tcp/${PEER}/443" && echo "OK: TCP/443 connected" || echo "OK: TCP/443 reached far side (refused/failed fast) OR blocked (timeout) — confirm with counters"
echo

echo "[*] TCP/80 (should DROP / timeout)"
timeout 4 bash -c "</dev/tcp/${PEER}/80" && echo "UNEXPECTED: TCP/80 reachable" || echo "OK: TCP/80 blocked (expected)"
echo

echo "[*] UDP/53 (send-only). Use firewall counters or tcpdump on peer to confirm receipt."
bash -c "echo test >/dev/udp/${PEER}/53" || true
echo "Sent UDP/53 datagram(s)."
