#!/bin/bash
# Build an unattended Ubuntu Server autoinstall ISO for a headless node.
# Fills user-data.template from node.env, the password hash (set-password.sh) and your SSH public key, embeds
# user-data + meta-data at /nocloud on the ISO, and boots the first menu entry with "autoinstall" after 3 s.
# xorriso's "-boot_image any replay" keeps the stock ISO's BIOS and UEFI boot structure.
# Needs: xorriso, openssl, python3 (macOS: brew install xorriso). Optional: uv (to check the YAML).
#   cp node.env.example node.env && $EDITOR node.env
#   bash set-password.sh && bash build-iso.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/node.env" ] || { echo "Copy node.env.example to node.env and edit it first."; exit 1; }
. "$HERE/node.env"
SHA_WANT=97f3d7ffb032c3eb3b23d2c8be9cc76e60c2c1f2c0146ba5ba9fe01cafae0fd8   # ubuntu-24.04.5-live-server-amd64.iso
HASH_FILE=$OUT/password-hash
B=$OUT/build
umask 077

[ -s "$HASH_FILE" ] || { echo "No password hash yet: run set-password.sh first."; exit 1; }
grep -q '^\$6\$' "$HASH_FILE" || { echo "$HASH_FILE is not a SHA-512 crypt hash."; exit 1; }
echo "Checking the stock ISO..."
[ "$(shasum -a 256 "$ISO" | cut -d' ' -f1)" = "$SHA_WANT" ] || { echo "ISO checksum mismatch: re-download it (or update SHA_WANT for a newer ISO)."; exit 1; }

rm -rf "$B"; mkdir -p "$B/nocloud"
python3 - "$HERE/user-data.template" "$HASH_FILE" "$KEY" "$B/nocloud/user-data" \
  "$NODE_HOSTNAME" "$NODE_USER" "$TIMEZONE" "$LAN_CIDR" "$DISK_MODEL" <<'PY'
import re, sys
tpl, hash_file, key_file, out, host, user, tz, cidr, disk = sys.argv[1:]
s = open(tpl).read()
for k, v in {
    "__PASSWORD_HASH__": open(hash_file).read().strip(),
    "__SSH_PUBKEY__": open(key_file).read().strip(),
    "__HOSTNAME__": host, "__USERNAME__": user, "__TIMEZONE__": tz,
    "__LAN_CIDR__": cidr, "__DISK_MODEL__": disk,
}.items():
    s = s.replace(k, v)
assert not re.search(r"__[A-Z_]+__", s), "unfilled placeholder"
open(out, "w").write(s)
PY
printf 'instance-id: %s\nlocal-hostname: %s\n' "$NODE_HOSTNAME" "$NODE_HOSTNAME" > "$B/nocloud/meta-data"
if command -v uv >/dev/null; then
  uv run -q --with pyyaml python -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); a=d["autoinstall"]; print("user-data OK:", a["identity"]["hostname"], "| keys:", len(a["ssh"]["authorized-keys"]), "| disk match:", a["storage"]["layout"]["match"])' "$B/nocloud/user-data"
else
  echo "(uv not found: skipped the YAML check)"
fi

xorriso -osirrox on -indev "$ISO" -extract /boot/grub/grub.cfg "$B/grub.cfg" >/dev/null 2>&1
chmod u+w "$B/grub.cfg"
python3 - "$B/grub.cfg" "$NODE_HOSTNAME" <<'PY'
import sys
p, host = sys.argv[1:]; s = open(p).read()
old = "\tlinux\t/casper/vmlinuz  ---"
assert s.count(old) == 1, "unexpected grub.cfg layout; not changing it"
s = s.replace("set timeout=30", "set timeout=3")
s = s.replace('menuentry "Try or Install Ubuntu Server" {', f'menuentry "Autoinstall {host} (WIPES the target disk)" {{')
s = s.replace(old, "\tlinux\t/casper/vmlinuz autoinstall ds=nocloud\\;s=/cdrom/nocloud/ ---")
open(p, "w").write(s)
PY

rm -f "$OUT/autoinstall.iso"
xorriso -indev "$ISO" -outdev "$OUT/autoinstall.iso" \
  -map "$B/nocloud" /nocloud \
  -map "$B/grub.cfg" /boot/grub/grub.cfg \
  -boot_image any replay 2>&1 | grep -E "Writing to|FAILURE|SORRY|Written" || true

echo "== checking the new ISO"
xorriso -osirrox on -indev "$OUT/autoinstall.iso" -extract /boot/grub/grub.cfg "$B/check-grub.cfg" -extract /nocloud/user-data "$B/check-user-data" >/dev/null 2>&1
grep -q "autoinstall ds=nocloud" "$B/check-grub.cfg" && echo "  grub: autoinstall flag present"
cmp -s "$B/check-user-data" "$B/nocloud/user-data" && echo "  user-data embedded and identical"
xorriso -indev "$OUT/autoinstall.iso" -report_el_torito plain 2>/dev/null | grep -E "El Torito boot img" | sed 's/^/  /'
ls -la "$OUT/autoinstall.iso"
