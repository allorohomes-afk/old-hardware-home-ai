#!/bin/bash
# Find the new node on your home network: ping-sweep the /24, then list every host with SSH open that isn't in
# KNOWN (your other machines). macOS or Linux.
#   bash find-node.sh 192.168.1        # first three parts of your network address
#   KNOWN="192.168.1.1 192.168.1.20" bash find-node.sh 192.168.1
NET="${1:?usage: find-node.sh 192.168.1   (the first three parts of your network address)}"
KNOWN="${KNOWN:-}"
for i in $(seq 1 254); do ping -c1 -W1 "$NET.$i" >/dev/null 2>&1 & done; wait
echo "Hosts with SSH open (KNOWN hidden):"
for ip in $(arp -an | awk -F'[()]' -v n="$NET." 'index($2, n) == 1 {print $2}' | sort -t. -k4 -n -u); do
  case " $KNOWN " in *" $ip "*) continue;; esac
  if nc -z -w 2 "$ip" 22 2>/dev/null; then
    echo "  $ip  $(ssh-keyscan -T 3 "$ip" 2>&1 | grep -m1 -o 'SSH-2.0-[^ ]*')"
  fi
done
echo "A fresh Ubuntu 24.04 shows OpenSSH_9.6p1 Ubuntu. Log in with: ssh <user>@<ip>"
echo "Note: while the installer is still running, it also answers on port 22 but refuses your key. Wait for it"
echo "to power off, remove the stick, power on, then log in."
