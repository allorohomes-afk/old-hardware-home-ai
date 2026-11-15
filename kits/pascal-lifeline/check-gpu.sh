#!/bin/bash
# Which NVIDIA cards are in this machine, and does this kit fit them? Changes nothing.
#   bash check-gpu.sh
# Works before any driver is installed: it reads the PCI device IDs. Once the driver is in, it also asks
# nvidia-smi for the compute capability (6.0 / 6.1 = Pascal).
set -uo pipefail

classify() {  # PCI device ID (hex, no 0x) -> generation and what to do
  local id=$((16#$1))
  if   (( id >= 0x15f0 && id <= 0x15ff )); then echo "Pascal (GP100, e.g. Tesla P100) | this kit, arch 60"
  elif (( id >= 0x1b00 && id <= 0x1d7f )); then echo "Pascal (GP102-GP108, e.g. GTX 10-series, P40) | this kit, arch 61"
  elif (( id >= 0x1d80 && id <= 0x1dff )); then echo "Volta (e.g. Titan V, V100) | 580 driver + CUDA 12.9 still work; set CUDA_ARCHS=70"
  elif (( id >= 0x1340 && id <= 0x13ff )) || (( id >= 0x1400 && id <= 0x17ff )); then
                                                echo "Maxwell (e.g. GTX 900-series) | 580 driver + CUDA 12.9 still work; set CUDA_ARCHS=\"50;52\""
  elif (( id >= 0x1e00 )); then                 echo "Turing or newer | you don't need this kit: current drivers and CUDA support it"
  else                                          echo "Kepler or older | not supported by the 580 driver or CUDA 12; try llama.cpp's Vulkan build"
  fi
}

if ! command -v lspci >/dev/null; then echo "lspci not found: sudo apt install pciutils"; exit 2; fi
cards=$(lspci -nn | grep -E '\[03(00|02)\]' | grep -i '\[10de:' || true)
if [ -z "$cards" ]; then echo "No NVIDIA graphics card found."; exit 1; fi

echo "$cards" | while read -r line; do
  id=$(echo "$line" | grep -oiE '\[10de:[0-9a-f]{4}\]' | cut -c7-10)
  echo "${line#*: }"
  echo "  -> $(classify "$id")"
done

if command -v nvidia-smi >/dev/null && nvidia-smi >/dev/null 2>&1; then
  echo
  echo "Driver is loaded:"
  nvidia-smi --query-gpu=index,name,compute_cap,memory.total,driver_version --format=csv,noheader | sed 's/^/  /'
else
  echo
  echo "No NVIDIA driver loaded yet. Next step: sudo bash install-driver.sh"
fi
