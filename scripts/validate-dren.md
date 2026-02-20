**validate-dren.sh — Technical README**

- **Location:** scripts/validate-dren.sh
- **Purpose:** Lightweight, on-box connectivity and policy checks to verify the constrained DREN path behavior from a VyOS edge router.
- **Invocation:** `bash scripts/validate-dren.sh <peer_dren_ip>`

What it checks
- ICMP: runs three `ping` probes to the peer DREN IP.
- TCP/22: attempts a TCP connect to port 22 and expects a timeout/failure (DREN policy should block non-allowed ports).
- TCP/443: attempts a TCP connect to port 443 and expects success or connection-refused (allowed by DREN policy); the test distinguishes fast fail vs timeout.
- TCP/80: attempts a TCP connect to port 80 and expects a timeout/failure (blocked by DREN policy).
- UDP/53: sends a single UDP payload to port 53 (send-only) — operator should verify counters or use tcpdump on the peer to confirm receipt.

Implementation notes
- Uses shell built-ins to exercise raw TCP sockets: `</dev/tcp/${PEER}/${PORT}` inside a `timeout` wrapper to short-circuit tests. This is a common POSIX trick that depends on bash’s `/dev/tcp` support.
- The script is intentionally permissive about interpreting failures: a successful TCP open prints `UNEXPECTED` when the policy should block.

Operational guidance
- Run this from `az-edge` or `onp-edge` to test the DREN peer (the other side of the DREN tunnel).
- The UDP/53 check only transmits a datagram — for reliable verification, combine with `tcpdump -n -i <dren-interface> port 53` on the destination or check firewall counters on VyOS.

Example

  bash scripts/validate-dren.sh 100.255.0.2

