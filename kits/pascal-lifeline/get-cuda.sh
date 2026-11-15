#!/bin/bash
# Download NVIDIA's CUDA 12.9 toolkit (the last one that builds for Pascal), check it, and optionally install it.
#   bash get-cuda.sh                                   # download and check only, into ./downloads
#   bash get-cuda.sh --prefix "$HOME/opt/cuda-12.9"    # also install the toolkit there; no sudo needed
#   sudo bash get-cuda.sh --prefix /usr/local/cuda-12.9
#
# Only the toolkit is installed, never the driver bundled inside the installer (that one is 575; Pascal boxes
# use 580 from install-driver.sh). You need the toolkit only on the machine that BUILDS llama.cpp, and that
# machine needs no graphics card. Keep the downloaded file: it is your offline copy for after NVIDIA moves on.
# Needs about 5.9 GB for the download and 8 GB more while installing.
set -euo pipefail
cd "$(dirname "$0")"
. ./versions.env
PREFIX=""
[ "${1:-}" = "--prefix" ] && PREFIX="${2:?--prefix needs a folder}"

mkdir -p downloads
RUN="downloads/$CUDA_RUNFILE"
if [ ! -f "$RUN" ]; then
  echo "Downloading $CUDA_RUNFILE (about 5.9 GB)..."
  curl -fL --retry 3 -o "$RUN.part" "$CUDA_URL"
  mv "$RUN.part" "$RUN"
fi

echo "Checking the download..."
md5=$(md5sum "$RUN" | cut -d' ' -f1)
[ "$md5" = "$CUDA_MD5" ] || { echo "!! MD5 mismatch: got $md5, NVIDIA publishes $CUDA_MD5. Delete $RUN and retry."; exit 1; }
if [ "$CUDA_SHA256" != "__FILL__" ]; then
  sha=$(sha256sum "$RUN" | cut -d' ' -f1)
  [ "$sha" = "$CUDA_SHA256" ] || { echo "!! SHA-256 mismatch: got $sha"; exit 1; }
fi
echo "  OK: matches NVIDIA's published checksum"

[ -n "$PREFIX" ] || { echo "Downloaded and checked. To install: bash get-cuda.sh --prefix <folder>"; exit 0; }

mkdir -p "$PREFIX" downloads/tmp
echo "Installing the toolkit to $PREFIX (takes a while)..."
sh "$RUN" --silent --toolkit --toolkitpath="$PREFIX" --no-man-page --override --tmpdir="$PWD/downloads/tmp"
rm -rf downloads/tmp
"$PREFIX/bin/nvcc" --version | tail -2
echo "Done. Build with: bash build-llama.sh --cuda $PREFIX"
