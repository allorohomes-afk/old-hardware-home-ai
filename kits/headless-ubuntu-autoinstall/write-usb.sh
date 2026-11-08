#!/bin/bash
# macOS: write the autoinstall ISO to a USB stick, after showing exactly which device and asking you to type its
# name. Refuses anything that isn't an external, removable USB disk. Reads the stick back, then checks the boot
# menu and user-data on it read-only. Run in Terminal (sudo needs a real terminal):
#   diskutil list external physical      # find your stick, e.g. disk4
#   bash write-usb.sh disk4
# On Linux, use:  sudo dd if=autoinstall.iso of=/dev/sdX bs=4M status=progress conv=fsync   (check sdX with lsblk!)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/node.env" ] && . "$HERE/node.env"
OUT="${OUT:-$HOME/.ai-node}"
DISK="${1:?usage: write-usb.sh diskN   (find N with: diskutil list external physical)}"
ISO="$OUT/autoinstall.iso"
[ -s "$ISO" ] || { echo "No ISO at $ISO: run build-iso.sh first."; exit 1; }
[ -t 0 ] || { echo "Run this in Terminal."; exit 1; }

info=$(diskutil info "$DISK")
for want in "Device Location: *External" "Protocol: *USB" "Removable Media: *Removable"; do
  grep -q "$want" <<<"$info" || { echo "STOP: $DISK fails the check '$want'."; exit 1; }
done
echo "About to ERASE this stick and write the autoinstall image to it:"
diskutil list "$DISK"
grep -E "Device / Media Name|Disk Size" <<<"$info"
read -r -p "Type the device name ($DISK) to continue, anything else to stop: " ok
[ "$ok" = "$DISK" ] || { echo "Stopped; nothing written."; exit 1; }

size=$(stat -f %z "$ISO")
diskutil unmountDisk "/dev/$DISK"
sudo dd if="$ISO" of="/dev/r$DISK" bs=4m status=progress
sync
echo "Reading it back..."
want=$(shasum -a 256 "$ISO" | cut -d' ' -f1)
got=$(sudo head -c "$size" "/dev/r$DISK" | shasum -a 256 | cut -d' ' -f1)
[ "$want" = "$got" ] && echo "VERIFIED: the stick matches the ISO." || { echo "MISMATCH: rewrite or use another stick."; exit 1; }

echo "Checking the files on the stick (read-only)..."
MNT=$(mktemp -d)
sudo mount -t cd9660 -o rdonly "/dev/$DISK" "$MNT" 2>/dev/null || sudo mount -t cd9660 -o rdonly "/dev/${DISK}s1" "$MNT"
grep -q "autoinstall ds=nocloud" "$MNT/boot/grub/grub.cfg" && echo "  boot menu has the autoinstall flag"
grep -q "hostname:" "$MNT/nocloud/user-data" && echo "  user-data present"
sudo umount "$MNT"; rmdir "$MNT"
diskutil eject "/dev/$DISK" && echo "Ejected. Label this stick: AUTOINSTALL - WIPES DISK."
