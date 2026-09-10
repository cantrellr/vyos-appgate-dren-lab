#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: test-ntp.sh <server-or-ip> [timeout-seconds]

Sends a real NTP client request over UDP/123 and validates that the reply is a
usable synchronization source. The test does not change the local system clock.

Success requires:
  - an NTP reply within the timeout;
  - server mode 4 (server) or 5 (broadcast);
  - leap indicator other than 3 (unsynchronized);
  - stratum between 1 and 15.

Examples:
  ./scripts/tools/test-ntp.sh 1.0.1.34
  ./scripts/tools/test-ntp.sh ntp.example.internal 5
USAGE
}

SERVER="${1:-}"
TIMEOUT_SECONDS="${2:-5}"

if [[ -z "${SERVER}" || "${SERVER}" == "-h" || "${SERVER}" == "--help" ]]; then
  usage
  [[ -n "${SERVER}" ]] && exit 0 || exit 2
fi

[[ "${TIMEOUT_SECONDS}" =~ ^[1-9][0-9]*$ ]] || {
  echo "ERROR: timeout must be a positive integer number of seconds." >&2
  exit 2
}

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 is required for the dependency-free NTP probe." >&2
  exit 2
}

python3 - "${SERVER}" "${TIMEOUT_SECONDS}" <<'PY'
import socket
import struct
import sys
import time

server = sys.argv[1]
timeout = float(sys.argv[2])
NTP_EPOCH = 2208988800


def ntp_to_unix(data: bytes) -> float:
    seconds, fraction = struct.unpack("!II", data)
    return (seconds - NTP_EPOCH) + (fraction / 2**32)


def ms(value: float) -> str:
    return f"{value * 1000:.3f} ms"

request = bytearray(48)
# LI=0, VN=4, Mode=3 (client)
request[0] = 0x23

t1 = time.time()
try:
    addresses = socket.getaddrinfo(server, 123, type=socket.SOCK_DGRAM)
except socket.gaierror as exc:
    print(f"FAIL server={server} reason=dns-resolution error={exc}")
    sys.exit(1)

last_error = None
for family, socktype, proto, _canonname, sockaddr in addresses:
    sock = socket.socket(family, socktype, proto)
    sock.settimeout(timeout)
    try:
        t1 = time.time()
        sock.sendto(request, sockaddr)
        payload, peer = sock.recvfrom(512)
        t4 = time.time()
        if len(payload) < 48:
            last_error = f"short NTP reply ({len(payload)} bytes)"
            continue

        first = payload[0]
        leap = (first >> 6) & 0x3
        version = (first >> 3) & 0x7
        mode = first & 0x7
        stratum = payload[1]
        poll = struct.unpack("!b", payload[2:3])[0]
        precision = struct.unpack("!b", payload[3:4])[0]
        root_delay = struct.unpack("!I", payload[4:8])[0] / 65536.0
        root_dispersion = struct.unpack("!I", payload[8:12])[0] / 65536.0

        t2 = ntp_to_unix(payload[32:40])
        t3 = ntp_to_unix(payload[40:48])
        delay = (t4 - t1) - (t3 - t2)
        offset = ((t2 - t1) + (t3 - t4)) / 2

        peer_text = peer[0] if isinstance(peer, tuple) else str(peer)
        leap_text = {0: "normal", 1: "last-minute-61-seconds", 2: "last-minute-59-seconds", 3: "unsynchronized"}[leap]

        print(f"server={server}")
        print(f"peer={peer_text}")
        print(f"version={version}")
        print(f"mode={mode}")
        print(f"stratum={stratum}")
        print(f"leap={leap} ({leap_text})")
        print(f"poll={poll}")
        print(f"precision={precision}")
        print(f"rootDelay={root_delay:.6f}s")
        print(f"rootDispersion={root_dispersion:.6f}s")
        print(f"roundTripDelay={ms(delay)}")
        print(f"estimatedClockOffset={ms(offset)}")

        failures = []
        if mode not in (4, 5):
            failures.append(f"unexpected mode {mode}")
        if leap == 3:
            failures.append("server reports unsynchronized leap indicator (LI=3)")
        if not (1 <= stratum <= 15):
            failures.append(f"invalid synchronization stratum {stratum}")

        if failures:
            print("FAIL reason=" + "; ".join(failures))
            sys.exit(1)

        print("PASS usableNtpSource=true udp123=true clockChanged=false")
        sys.exit(0)
    except (socket.timeout, OSError) as exc:
        last_error = str(exc)
    finally:
        sock.close()

print(f"FAIL server={server} reason=no-valid-ntp-response timeout={timeout:.0f}s error={last_error or 'unknown'}")
sys.exit(1)
PY
