#!/bin/bash
# Build llama.cpp for Pascal cards, prove the Pascal GPU code is in it, and pack it to copy to other machines.
#   bash build-llama.sh --cuda "$HOME/opt/cuda-12.9"        # toolkit from get-cuda.sh
#   bash build-llama.sh --cuda /usr/local/cuda-12.9 --jobs 8
#   bash build-llama.sh ... --no-bundle                     # leave NVIDIA's CUDA libraries out of the package
#
# No graphics card needed. Ubuntu 24.04 needs: sudo apt install build-essential cmake git libssl-dev
# The trap this avoids: a build only carries GPU code for the cards it was told about. A "native" build
# covers only the card in the build machine (none, here), and some projects' defaults leave Pascal out, so
# the result says "no compatible GPU found" on a GTX 1080 or P40. This script names the Pascal GPU code
# explicitly (CUDA_ARCHS in versions.env) and refuses to package a build that doesn't contain it.
#
# The package runs on any Ubuntu 24.04 x86_64 machine with only the 580 driver installed: it carries the
# CUDA runtime and cuBLAS libraries it needs (NVIDIA lets apps ship these), and CPU code for every CPU
# generation, so the same files work on an old Xeon or a new desktop.
set -euo pipefail
cd "$(dirname "$0")"
. ./versions.env
CUDA=/usr/local/cuda-12.9; JOBS=$(nproc); BUNDLE=1
while [ $# -gt 0 ]; do
  case $1 in
    --cuda) CUDA=$2; shift 2 ;;
    --jobs) JOBS=$2; shift 2 ;;
    --no-bundle) BUNDLE=0; shift ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done
die() { echo "!! $*" >&2; exit 1; }

NVCC="$CUDA/bin/nvcc"
[ -x "$NVCC" ] || die "no nvcc in $CUDA/bin. Run get-cuda.sh first, or pass --cuda <folder>"
"$NVCC" --version | grep -q "release ${CUDA_VERSION%.*}" || die "$NVCC is not CUDA ${CUDA_VERSION%.*}"
for t in cmake git g++; do command -v $t >/dev/null || die "$t missing: sudo apt install build-essential cmake git libssl-dev"; done

SRC=work/llama.cpp-$LLAMA_TAG
if [ ! -d "$SRC" ]; then
  mkdir -p work
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$LLAMA_TAG" https://github.com/ggml-org/llama.cpp "$SRC"
fi
got=$(git -C "$SRC" rev-parse HEAD)
[ "$got" = "$LLAMA_COMMIT" ] || die "llama.cpp $LLAMA_TAG is commit $got, expected $LLAMA_COMMIT"

BUILD=work/build-$LLAMA_TAG
echo "Configuring: CUDA $CUDA_VERSION, GPU code for compute $CUDA_ARCHS..."
cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=ON -DCUDAToolkit_ROOT="$CUDA" -DCMAKE_CUDA_COMPILER="$NVCC" -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHS" \
  -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH='$ORIGIN' \
  -DBUILD_SHARED_LIBS=ON -DLLAMA_BUILD_TESTS=OFF > "$BUILD.configure.log" 2>&1 \
  || { tail -30 "$BUILD.configure.log"; die "configure failed (full log: $BUILD.configure.log)"; }

echo "Building with $JOBS jobs (50 min on a 2013 laptop; log: $BUILD.log)..."
start=$(date +%s)
cmake --build "$BUILD" -j "$JOBS" > "$BUILD.log" 2>&1 || { tail -30 "$BUILD.log"; die "build failed"; }
mins=$(( ($(date +%s) - start) / 60 ))

CUDALIB=$(ls "$BUILD"/bin/libggml-cuda.so* 2>/dev/null | head -1)
[ -n "$CUDALIB" ] || die "the build has no libggml-cuda.so"
echo "Checking the GPU code inside $(basename "$CUDALIB")..."
found=$("$CUDA/bin/cuobjdump" --list-elf "$CUDALIB" | grep -oE 'sm_[0-9]+' | sort -u | tr '\n' ' ')
for a in ${CUDA_ARCHS//;/ }; do
  echo "$found" | grep -qw "sm_$a" || die "no sm_$a code in the build (found: $found). It would not run on that card."
done
echo "  OK: contains $found"

NAME=llama.cpp-$LLAMA_TAG-cuda$CUDA_VERSION-pascal-ubuntu24.04-x64
OUT=dist/$NAME
rm -rf "$OUT"; mkdir -p "$OUT"
cp -a "$BUILD"/bin/* "$OUT"/
if [ $BUNDLE = 1 ]; then
  for lib in libcudart.so.12 libcublas.so.12 libcublasLt.so.12; do
    real=$(readlink -f "$CUDA/lib64/$lib") || die "missing $CUDA/lib64/$lib"
    cp "$real" "$OUT/"; ln -sf "$(basename "$real")" "$OUT/$lib"
  done
fi

echo "Smoke test on this machine (no graphics card needed)..."
"$OUT/llama-server" --version 2>&1 | grep -m1 -E 'version' | sed 's/^/  /'
"$OUT/llama-cli" --list-devices 2>&1 | sed 's/^/  /' | head -8

cat > "$OUT/BUILD-INFO.txt" <<EOF
llama.cpp $LLAMA_TAG ($LLAMA_COMMIT)
CUDA $CUDA_VERSION, GPU code: $found
Built $(date -u +%Y-%m-%d) on $(. /etc/os-release; echo "$PRETTY_NAME"), $(g++ --version | head -1), $mins min
CPU code: all x86_64 variants (picked at run time). NVIDIA CUDA libraries bundled: $([ $BUNDLE = 1 ] && echo yes || echo no)
Needs: NVIDIA driver $DRIVER_BRANCH (kits/pascal-lifeline/install-driver.sh)
Run:  ./llama-server -m model.gguf -ngl 99     (-ngl 99 = put every layer on the card)
Made by old-hardware-home-ai kits/pascal-lifeline
EOF

echo "Packing..."
tar -C dist -czf "dist/$NAME.tar.gz" "$NAME"
(cd dist && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
echo "Done in $mins min of building:"
ls -lh "dist/$NAME.tar.gz" | awk '{print "  " $5 "  " $9}'
cat "dist/$NAME.tar.gz.sha256" | sed 's/^/  /'
