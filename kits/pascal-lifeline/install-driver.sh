#!/bin/bash
# Install NVIDIA's 580 driver branch, the last one that supports Pascal, and stop apt from ever leaving it.
#   sudo bash install-driver.sh          # shows the plan and asks first
#   sudo bash install-driver.sh --yes
#
# For Ubuntu 24.04 LTS on a headless AI box. It installs:
#   - Ubuntu's own packaged 580 driver, headless (no desktop parts), with Canonical's pre-signed kernel module,
#     so it works with Secure Boot on and needs no compiling.
#   - An apt rule that blocks every later branch (590 and up, which dropped Pascal) and the "open" kernel
#     modules (which never supported Pascal). Security updates inside the 580 branch still arrive as usual.
set -euo pipefail
cd "$(dirname "$0")"
. ./versions.env
B=$DRIVER_BRANCH
PIN=/etc/apt/preferences.d/pascal-lifeline-nvidia
YES=0; [ "${1:-}" = "--yes" ] && YES=1

die() { echo "!! $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"
. /etc/os-release
[ "$ID" = ubuntu ] && [ "$VERSION_ID" = 24.04 ] || die "this kit is for Ubuntu 24.04 LTS (found $PRETTY_NAME)"
[ "$(uname -m)" = x86_64 ] || die "this kit is for x86_64 PCs"

# The pre-signed module package must match the kernel line: the original 24.04 kernel or the newer "HWE" one.
if dpkg-query -W -f='${Status}' linux-image-generic-hwe-24.04 2>/dev/null | grep -q 'ok installed'; then
  FLAVOUR=generic-hwe-24.04
elif dpkg-query -W -f='${Status}' linux-image-generic 2>/dev/null | grep -q 'ok installed'; then
  FLAVOUR=generic
else
  die "unrecognised kernel ($(uname -r)); install linux-generic, reboot into it, and run this again"
fi
PKGS="nvidia-headless-no-dkms-$B nvidia-utils-$B linux-modules-nvidia-$B-$FLAVOUR"

echo "Plan:"
echo "  1. Write $PIN (blocks NVIDIA driver branches after $B, and the open kernel modules)"
echo "  2. apt install $PKGS"
echo "  3. You reboot, then run: bash check-gpu.sh"
command -v mokutil >/dev/null && echo "  Secure Boot: $(mokutil --sb-state 2>/dev/null | head -1) (fine either way: the module is pre-signed)"
if [ $YES = 0 ]; then
  read -r -p "Go ahead? [y/N] " a
  [ "$a" = y ] || [ "$a" = Y ] || { echo "Nothing changed."; exit 0; }
fi

cat > "$PIN" <<EOF
# Written by old-hardware-home-ai kits/pascal-lifeline. Pascal GPUs need NVIDIA's $B driver branch.
# Branches 590 and later dropped Pascal; the "open" kernel modules never supported it. Delete this file to undo.
Explanation: later NVIDIA driver branches (no Pascal support)
Package: /^(lib)?nvidia-.*-(59[0-9]|[6-9][0-9][0-9])(-server)?(-open)?$/ /^linux-(modules|objects|signatures)-nvidia-(59[0-9]|[6-9][0-9][0-9])-/
Pin: version *
Pin-Priority: -1

Explanation: open kernel modules (no Pascal support)
Package: /^(lib)?nvidia-.*-open$/ /^linux-(modules|objects|signatures)-nvidia-[0-9]+-open-/
Pin: version *
Pin-Priority: -1
EOF
echo "Wrote $PIN"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y $PKGS

echo
echo "Done. Reboot now (sudo reboot), then run: bash check-gpu.sh"
echo "It should list your card with compute capability 6.0 or 6.1 and driver $B.x."
