#!/bin/bash
# Measure the REAL CPU clock of an AMD family 15h chip (Trinity/Richland/Kaveri era, 2012-2015). Linux often shows
# only the base clock; this reads the CPU cycle counters (APERF/MPERF) and its speed table (P-states).
# Read-only: nothing on the CPU is changed. Assumes 4 cores and a 2.5 GHz base clock (A10-5750M); edit BASE and
# the core list below for your chip.
# Installs msr-tools on the target over SSH (needs passwordless sudo there, or run the inner part by hand):
#   bash amd-fam15h-clock.sh user@host            # idle 10 s, then full load 60 s, sampled every 5 s
#   bash amd-fam15h-clock.sh user@host --remove   # uninstall msr-tools
set -e
HOST="${1:?usage: amd-fam15h-clock.sh user@host [--remove]}"
SSH="ssh $HOST"
if [ "${2:-}" = "--remove" ]; then
  $SSH 'sudo -n apt-get remove -y -qq msr-tools >/dev/null && echo "msr-tools removed."'; exit 0
fi
$SSH 'bash -s' <<'REMOTE'
set -e
dpkg -s msr-tools >/dev/null 2>&1 || { echo "Installing msr-tools..."; sudo -n apt-get install -y -qq msr-tools >/dev/null; }
sudo -n modprobe msr
echo "== speed table (P-states) the chip allows"
for i in 0 1 2 3 4 5 6 7; do
  v=$(sudo -n rdmsr -p 0 -c $((0xC0010064 + i)) 2>/dev/null) || continue
  python3 - "$v" "$i" <<'PY'
import sys
v, i = int(sys.argv[1], 16), sys.argv[2]
if not v >> 63 & 1: sys.exit()
fid, did, vid = v & 0x3F, (v >> 6) & 0x7, (v >> 9) & 0x7F
mhz = 100 * (fid + 0x10) / (1 << did)
print(f"  P{i}: {mhz:.0f} MHz at {1.55 - 0.00625 * vid:.3f} V")
PY
done
temp() { for h in /sys/class/hwmon/hwmon*; do [ "$(cat $h/name)" = k10temp ] && echo $(( $(cat $h/temp1_input) / 1000 )); done; }
BASE=2500   # your chip's base clock in MHz
real_mhz() {  # effective MHz per core over 1 s = BASE * dAPERF / dMPERF
  a0=(); m0=()
  for c in 0 1 2 3; do a0[$c]=$(sudo -n rdmsr -p $c -u 0xE8); m0[$c]=$(sudo -n rdmsr -p $c -u 0xE7); done
  sleep 1
  out=""
  for c in 0 1 2 3; do
    a=$(sudo -n rdmsr -p $c -u 0xE8); m=$(sudo -n rdmsr -p $c -u 0xE7)
    out="$out $(( BASE * (a - a0[c]) / (m - m0[c] + 1) ))"
  done
  echo "$out"
}
echo "== idle"
for _ in 1 2; do echo "  cores MHz:$(real_mhz)   CPU $(temp) C"; sleep 4; done
echo "== full load on all 4 cores for 60 s"
for c in 1 2 3 4; do timeout 62 sh -c 'while :; do :; done' & done
for _ in $(seq 12); do echo "  cores MHz:$(real_mhz)   CPU $(temp) C"; sleep 4; done
wait
echo "== after load"; echo "  cores MHz:$(real_mhz)   CPU $(temp) C"
REMOTE
