# Pascal lifeline: keep GTX 10-series and Tesla P-series cards running local AI

NVIDIA's Pascal cards (GTX 1050 to 1080 Ti, Titan X/Xp, Tesla P4/P40/P100, Quadro P-series) are cheap on the used
market and still useful for local AI. A used Tesla P40 has 24 GB of video memory. But NVIDIA is phasing them out,
and the tools people use fail on them in confusing ways. This kit pins a setup that keeps them working, and builds
llama.cpp so it actually uses the card.

> **STATUS (November 2026): built and checked without a card; NOT yet tested on a Pascal card.** We don't own
> one yet. On our 2013 laptop (no graphics card) `get-cuda.sh` installed the toolkit without sudo, and
> `build-llama.sh` built in 50 minutes, confirmed the Pascal GPU code (sm_60, sm_61) is inside, and made a 614 MB
> package. Unpacked in a fresh folder, that package found its bundled CUDA libraries and ran a small model on the
> CPU. `install-driver.sh`'s apt rule was checked without installing: it blocks the 590 branch and the open
> modules, and leaves the 580 packages alone. The driver install itself needs a card and hasn't been run.
> Whether it runs well on a real GTX 1080 or P40 is still unmeasured. Treat every speed claim elsewhere as
> unproven until our benchmark results appear in `bench/results/`.

## Why this is needed

| Piece | What's happening |
|---|---|
| Driver | The **580** branch is NVIDIA's last for Pascal. Security updates are planned until **October 2028**. Driver 590 and later don't support Pascal at all. |
| CUDA toolkit | CUDA 13 dropped Pascal. **CUDA 12.9** is the last version that can build for it, and it keeps working after that. |
| Linux distributions | They're moving Pascal off the default driver package (Arch already has), so a routine update can remove your card's driver. |
| AI software | A build only carries GPU code for the cards it was told about. Builds tuned to the machine that built them, and some projects' defaults, leave Pascal out, and then say "no compatible GPU found" on a GTX 1080. llama.cpp publishes no ready-made Linux CUDA builds. |
| Open-source driver | As far as we know, the open-source driver can't run Pascal at full speed, so there's no fallback after 2028. |

We don't need a new CUDA. CUDA 12.9 already works. The problem is keeping the 580 driver and the 12.9 toolkit in
place, and building software for the card on purpose.

## What's in the kit

| Script | What it does | Needs a card? | Needs sudo? |
|---|---|---|---|
| `check-gpu.sh` | Lists your NVIDIA cards and tells you whether this kit fits them. Changes nothing. | yes, to find one | no |
| `install-driver.sh` | Installs Ubuntu's packaged **580** driver (headless, pre-signed, so it works with Secure Boot on) and an apt rule that blocks every later branch. Security updates inside 580 still arrive. | no | yes |
| `get-cuda.sh` | Downloads the **CUDA 12.9.1** toolkit, checks it against NVIDIA's checksum, and installs only the toolkit (never the bundled driver). Can install into your home folder without sudo. | no | optional |
| `build-llama.sh` | Builds llama.cpp for Pascal, **fails if the Pascal code isn't in the result**, and packs a folder you can copy to any Ubuntu 24.04 machine that has the 580 driver. | no | no |
| `versions.env` | Every pinned version in one place. | | |

Everything is for **Ubuntu 24.04 LTS on x86_64**, our standard node setup (see
[headless-ubuntu-autoinstall](../headless-ubuntu-autoinstall/)).

## Steps

**On the machine with the Pascal card:**

1. `bash check-gpu.sh`: confirm it says Pascal.
2. `sudo bash install-driver.sh`: shows the plan, asks, installs. Then `sudo reboot`.
3. `bash check-gpu.sh` again: it should show compute capability 6.0 or 6.1 and driver 580.

**On any Ubuntu 24.04 PC, with or without a card (it can be the same machine):**

4. `sudo apt install build-essential cmake git libssl-dev`
5. `bash get-cuda.sh --prefix "$HOME/opt/cuda-12.9"` (about 5.9 GB download; keep `downloads/` as your offline copy).
6. `bash build-llama.sh --cuda "$HOME/opt/cuda-12.9"`: 50 minutes on our 2013 laptop. The result is
   `dist/llama.cpp-…-pascal-ubuntu24.04-x64.tar.gz` plus its SHA-256 checksum.

**Back on the card machine:**

7. Copy the `.tar.gz` over, unpack it, and run `./llama-server -m your-model.gguf -ngl 99`. `-ngl 99` puts the
   whole model on the card. The package carries the CUDA libraries it needs, so the card machine needs only the
   driver from step 2.

## Which cards, and roughly what fits

Model sizes are estimates from file sizes (Q4_K_M models, short chats). We haven't measured them on a card yet.

| Card | Video memory | Roughly fits | Notes |
|---|---|---|---|
| GTX 1050 Ti | 4 GB | 3–4B models | |
| GTX 1060 | 3 or 6 GB | 6 GB: 7–8B, short chats | Get the 6 GB version. |
| GTX 1070 / 1070 Ti / 1080 | 8 GB | 7–8B models comfortably | |
| GTX 1080 Ti, Titan X/Xp | 11–12 GB | up to ~14B models | |
| Tesla P4 | 8 GB | 7–8B models | Low power (75 W), passive cooling: needs a fan blowing through it. |
| Tesla P100 | 12 or 16 GB | up to ~14B models | Fast at half-precision math, unlike the rest. Passive cooling. |
| Tesla P40 | 24 GB | up to ~32B models | About $260 used (Nov 2026). Passive cooling: needs an add-on blower fan. Takes an 8-pin **CPU-style (EPS)** power cable, not a regular graphics-card plug. |

**What we expect, and will check:** most Pascal cards are very slow at half-precision math, which many AI tools
lean on. llama.cpp's 8-bit integer path should suit the GTX 10-series and P4/P40 better. The P100 lacks that
integer instruction but is fast at half precision. Our benchmarks will tell.

## After October 2028

The driver will keep working; it just stops getting security updates. The risks are newer Linux kernels the 580
driver can't build against, and distributions dropping the package. Our plan:

- Stay on **Ubuntu 24.04 LTS**, which Canonical supports until 2029 (2034 with free Ubuntu Pro for personal use),
  with its packaged 580 driver.
- Keep offline copies of the CUDA installer (`downloads/`), the llama.cpp package (`dist/`), and the driver packages.
- Track the community patches that keep old NVIDIA drivers building on new kernels, as people did for the 470 and
  390 branches.
- Build and benchmark llama.cpp's **Vulkan** backend as a second path that doesn't depend on CUDA.

## Undo

- Driver: `sudo apt remove 'nvidia-*580*' 'linux-modules-nvidia-580*'`, then
  `sudo rm /etc/apt/preferences.d/pascal-lifeline-nvidia`.
- Toolkit: delete the folder you gave `--prefix`.
- Builds: delete `work/` and `dist/`.

## Licences

The scripts are under this repo's licence. llama.cpp is MIT. The CUDA toolkit is NVIDIA's proprietary software,
downloaded from NVIDIA under their licence. The CUDA runtime and cuBLAS libraries that `build-llama.sh` copies into
the package are on NVIDIA's list of files apps may redistribute; check the licence yourself before redistributing
a package publicly. Use `--no-bundle` to leave them out.
