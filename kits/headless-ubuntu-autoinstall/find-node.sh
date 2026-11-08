#!/bin/bash
# Find the new node on your home network: ping-sweep the /24, then list every host with SSH open that isn't in
# KNOWN (your other machines). macOS or Linux.
#   bash find-node.sh 192.168.1        # first three parts of your network address
#   KNOWN="192.168.1.1 192.168.1.20" bash find-node.sh 192.168.1
NET="${1:?usage: find-node.sh 192.168.1   (the first three parts of your network address)}"
KNOWN="${KNOWN:-}"
# ping -W is milliseconds on macOS but seconds on Linux;
# nc: macOS needs -G for a connect timeout; Linux uses -w
[ "$(uname)" = Darwin ] && { W=1000; NC="-G 2"; } || { W=1; NC="-w 2"; }
for i in $(seq 1 254); do ping -c1 -W "$W" "$NET.$i" >/dev/null 2>&1 & done; wait
echo "Hosts with SSH open (KNOWN hidden):"
neighbours() {  # addresses that actually answered (skip "incomplete" / FAILED entries)
  if command -v arp >/dev/null; then arp -an | grep -v incomplete | awk -F'[()]' '{print $2}'
  else ip neigh | grep -vE 'FAILED|INCOMPLETE' | awk '{print $1}'; fi
}
for ip in $(neighbours | awk -v n="$NET." 'index($0, n) == 1' | sort -t. -k4 -n -u); do
  case " $KNOWN " in *" $ip "*) continue;; esac
  if nc -z $NC "$ip" 22 2>/dev/null; then
    echo "  $ip  $(ssh-keyscan -T 3 "$ip" 2>&1 | grep -m1 -o 'SSH-2.0-[^ ]*')"
  fi
done
echo "A fresh Ubuntu 24.04 shows OpenSSH_9.6p1. Log in with: ssh <user>@<ip>"
echo "Note: while the installer is still running, it also answers on port 22 but refuses your key. Wait for it"
echo "to power off, remove the stick, power on, then log in."
