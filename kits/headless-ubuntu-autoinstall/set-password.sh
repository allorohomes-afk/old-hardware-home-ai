#!/bin/bash
# Ask for the node user's password (typed twice, never shown or saved) and store only its SHA-512 crypt hash in
# $OUT/password-hash (mode 600, outside git). Run in a real terminal, which can hide what you type:
#   bash set-password.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/node.env" ] && . "$HERE/node.env"
OUT="${OUT:-$HOME/.ai-node}"
[ -t 0 ] || { echo "Run this in a real terminal (it needs one to hide the password)."; exit 1; }
read -rs -p "Password for the node user: " p1; echo
read -rs -p "Same again: " p2; echo
[ "$p1" = "$p2" ] || { echo "They don't match; nothing saved."; exit 1; }
[ ${#p1} -ge 8 ] || { echo "Use at least 8 characters; nothing saved."; exit 1; }
umask 077
mkdir -p "$OUT"
printf '%s' "$p1" | openssl passwd -6 -stdin > "$OUT/password-hash"
unset p1 p2
echo "Saved the hash (not the password) to $OUT/password-hash"
