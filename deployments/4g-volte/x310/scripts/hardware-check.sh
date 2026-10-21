#!/usr/bin/env bash
set -euo pipefail
if [ "${LAIN5G_DRY_RUN:-false}" = true ]; then
  echo "DRY RUN: 4G LTE X310 hardware-check plan; no device, network, UHD, Docker, or file access was performed"
  exit 0
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="$script_dir/../../common/.env"
[ -f "$env_file" ] && set -a && source "$env_file" && set +a
addr="${USRP_ADDR:-192.168.10.2}"
image="${LAIN5G_UHD_IMAGE:-lain5g-lab/srsran4g-uhd:local}"
status=PASS
check(){ printf '%-22s %s %s\n' "$1" "$2" "$3"; [ "$2" = FAIL ] && status=FAIL; return 0; }
host_addr_show(){
  local out=""
  if command -v ip >/dev/null 2>&1; then out="$(ip -o addr show 2>/dev/null || true)"; fi
  if printf '%s\n' "$out" | grep -Eq '192\.168\.(10|30)\.'; then printf '%s\n' "$out"; return 0; fi
  if docker image inspect "$image" >/dev/null 2>&1; then
    out="$(docker run --rm --network host "$image" ip -o addr show 2>/dev/null || true)"
  fi
  printf '%s\n' "$out"
}
x310_reachable(){
  if command -v ping >/dev/null 2>&1; then ping -c 1 -W 1 "$1" >/dev/null 2>&1 || return 1; return 0; fi
  if docker image inspect "$image" >/dev/null 2>&1; then
    docker run --rm --network host "$image" ping -c 1 -W 1 "$1" >/dev/null 2>&1 || return 1; return 0
  fi
  return 1
}
addr_output="$(host_addr_show)"
if printf '%s\n' "$addr_output" | grep -Eq '192\.168\.(10|30)\.'; then
  check ethernet_link PASS "compatible local subnet found"
else
  check ethernet_link WARNING "no typical X310 local subnet found"
fi
x310_reachable "$addr" && check x310_ping PASS "X310 responds at $addr" || { check x310_ping FAIL "X310 did not respond at $addr"; }
if command -v uhd_find_devices >/dev/null 2>&1; then
  out="$(uhd_find_devices --args "addr=$addr" 2>&1 || true)"
elif docker image inspect "$image" >/dev/null 2>&1; then
  out="$(docker run --rm --network host "$image" uhd_find_devices --args "addr=$addr" 2>&1 || true)"
else
  out=""
  check uhd_find_devices FAIL "uhd_find_devices missing and image $image not found"
fi
if [ -n "$out" ]; then
  printf '%s\n' "$out" > /tmp/lain5g-uhd-find-devices.log
  if printf '%s\n' "$out" | grep -Eiq 'product: X300|type: x300|addr:'; then
    check uhd_find_devices PASS "X310/X300 family device found"
  else
    check uhd_find_devices FAIL "UHD did not report an X310/X300 family device"
  fi
  serial="$(printf '%s\n' "$out" | sed -n 's/.*serial: *//Ip' | head -n1)"
  [ -n "$serial" ] && echo "serial_redacted=${serial:0:3}***${serial: -2}"
fi
echo "status=$status"
test "$status" != FAIL
