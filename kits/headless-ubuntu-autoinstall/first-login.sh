#!/bin/bash
# First look at a new node: CPU features that matter for AI, memory, disks, disk health, temps, network, firewall.
#   ssh <user>@<ip> 'bash -s' < first-login.sh
# smartctl and ufw need sudo, so it asks for the user's password once.
echo "== $(hostname)  $(cat /etc/ai-node 2>/dev/null)"
echo "== CPU"
lscpu | grep -E "Model name|^CPU\(s\)|Thread|Core|MHz"
grep -qw avx2 /proc/cpuinfo && echo "AVX2: yes" || echo "AVX2: NO"
grep -qw avx /proc/cpuinfo && echo "AVX: yes" || echo "AVX: NO (expect slow AI on this CPU)"
echo "== memory"; free -h
echo "== disks"; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
D=$(lsblk -dno NAME,TYPE | awk '$2 == "disk" {print $1; exit}')
echo "== disk health (/dev/${D:-?})"
[ -n "$D" ] && sudo smartctl -a "/dev/$D" | grep -E "Device Model|overall-health|Power_On_Hours|Reallocated_Sector|Current_Pending|Offline_Uncorrectable|UDMA_CRC|Temperature_Celsius"
echo "== temperatures"; sensors 2>/dev/null || echo "(no sensors read yet: run sudo sensors-detect later)"
echo "== network"; ip -br a
echo "== firewall"; sudo ufw status | head -5
echo "== sudo needs a password?"; sudo -k; sudo -n true 2>/dev/null && echo "NO (passwordless!)" || echo "yes"
