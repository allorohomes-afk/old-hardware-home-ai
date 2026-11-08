#!/bin/bash
# Scan everything git would publish for personal information before a push. Exit 1 if anything is found.
#   bash scripts/privacy-check.sh
# Checks: IP addresses (except documentation/example ones), MAC addresses, email addresses, home-folder paths,
# private keys, and every word in your PRIVATE denylist. The denylist lives OUTSIDE the repo, so the names in it
# are never published:  ~/.config/old-hardware-home-ai/denylist.txt  (one word or phrase per line, case-insensitive)
cd "$(git rev-parse --show-toplevel)" || exit 2
DENY="${DENYLIST:-$HOME/.config/old-hardware-home-ai/denylist.txt}"
FILES=$(git ls-files --cached --others --exclude-standard)
bad=0
hit() { echo "!! $1"; echo "$2" | sed 's/^/     /' | head -10; bad=1; }

# IPv4, minus loopback, 0.0.0.0, and the example ranges used in the docs
ips=$(grep -nIoE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' $FILES 2>/dev/null |
  grep -vE ':(127\.0\.0\.1|0\.0\.0\.0|192\.168\.1\.[0-9]+|192\.0\.2\.[0-9]+|198\.51\.100\.[0-9]+|203\.0\.113\.[0-9]+)$' || true)
# keep only real-looking addresses (all four parts <= 255, first part >= 10)
ips=$(echo "$ips" | awk -F: 'NF>=3 {split($NF,o,"."); if (o[1]>=10 && o[1]<=255 && o[2]<=255 && o[3]<=255 && o[4]<=255) print}')
[ -n "$ips" ] && hit "IP addresses" "$ips"

macs=$(grep -nIoiE '\b([0-9a-f]{1,2}:){5}[0-9a-f]{1,2}\b' $FILES 2>/dev/null || true)
[ -n "$macs" ] && hit "MAC addresses" "$macs"

emails=$(grep -nIoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' $FILES 2>/dev/null | grep -v 'noreply@anthropic.com' || true)
[ -n "$emails" ] && hit "Email addresses" "$emails"

homes=$(grep -nIoE '/(Users|home)/[A-Za-z0-9._-]+' $FILES 2>/dev/null || true)
[ -n "$homes" ] && hit "Home-folder paths with a user name" "$homes"

keys=$(grep -nIlE 'BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY|\$6\$[./A-Za-z0-9]{8,}\$' $FILES 2>/dev/null || true)
[ -n "$keys" ] && hit "Private keys or password hashes" "$keys"

media=$(echo "$FILES" | grep -iE '\.(jpe?g|heic|png|mov|mp4)$' || true)
[ -n "$media" ] && hit "Photos/videos (check for faces, serial labels, location data before publishing)" "$media"

if [ -s "$DENY" ]; then
  while IFS= read -r w; do
    [ -z "$w" ] || [ "${w#\#}" != "$w" ] && continue
    m=$(grep -nIiF -- "$w" $FILES 2>/dev/null || true)
    [ -n "$m" ] && hit "Denylisted word (from your private list)" "$(echo "$m" | cut -d: -f1,2)"
  done < "$DENY"
else
  echo "?? No private denylist at $DENY: names, hostnames and serial numbers were NOT checked."; bad=1
fi

[ $bad = 0 ] && echo "privacy-check: clean ($(echo "$FILES" | wc -l | tr -d ' ') files)" || { echo "privacy-check: FIX THE ABOVE before publishing"; exit 1; }
