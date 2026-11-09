# Old Hardware, Home AI

**Run your own private AI at home on computers people are throwing away.**

This is a working notebook from a family home lab. We run local AI models (chat, coding help, homework help)
on a mix of old machines: a 2012 all-in-one desktop, a 2013 laptop, a used tower server, and a couple of newer
laptops for comparison. No cloud subscription, no data leaving the house, and nothing here needs a graphics card.

We publish what we measure, including what **didn't** work, so you can skip our mistakes. Everything here is
free and open source.

## Our mission

Powerful AI shouldn't depend on money for new hardware or monthly subscriptions. We want families at every income
level, in the US and around the world, to be able to run a private AI at home on computers they already have, or
can get for very little. So we test cheap and old machines, measure everything, and publish all of it, including
what fails.

## Who this is for

- You have an old PC or laptop (roughly 2012 or newer) and want a private AI assistant at home.
- You can't or don't want to pay for a new GPU, a cloud subscription, or a new computer.
- You're comfortable typing commands, or willing to learn.

## What we found so far

| Finding | Short version | Details |
|---|---|---|
| Old desktops are usable | A 2012 Intel i3 with 16 GB RAM wrote **6–11 tokens per second** (roughly 5–8 words) with small modern models: about reading speed. | [findings/01](findings/01-speeds-on-old-machines.md) |
| Pick the model before the hardware | IBM Granite 4.0 H-Tiny (7B in size, only ~1B working at a time) wrote about **1.7× faster** than Llama 3.2 3B on the same machines, and held its speed far better in long chats. It needs more RAM (about 7 GB). The old-desktop comparison is being rerun under identical conditions. | [findings/01](findings/01-speeds-on-old-machines.md) |
| Old AMD laptops have a RAM trap | Many 2012–2014 AMD laptops only see **half** of a modern 8 GB stick. Check the chip count before you buy. | [findings/02](findings/02-ram-trap-old-amd-laptops.md) |
| Cooling won't make a locked laptop faster | Our 2013 laptop's turbo boost is locked off in firmware; it holds 2.5 GHz under load at 82–85 °C either way. | [findings/03](findings/03-laptop-boost-locked.md) |
| Check speculative decoding is really on | Our first test showed no gain, but the server wasn't actually guessing (a flag changed in llama.cpp). Rerun pending; the page shows how to check. | [findings/04](findings/04-speculative-decoding.md) |
| Used servers: RAM, battery, CPU | Our used tower server's RAM had come loose in shipping, its BIOS battery was dead, and its CPU turned out to be a Pentium with no AVX. Check all three. | [findings/05](findings/05-used-server-first-boot.md) |
| Power is cheap | An old tower server should idle around 25–35 W, about **$35–45 a year** (estimate, measurement pending). | [findings/06](findings/06-power-draw.md) |

## What's in here

- `findings/`: one page per thing we learned, with the numbers.
- `kits/headless-ubuntu-autoinstall/`: build a USB stick that installs Ubuntu Server on a spare PC with **no
  screen, keyboard or mouse**, ready for SSH. **Status: the install and first boot work; a bug we found at first
  boot is fixed, and the fix awaits a full reinstall test** (see [findings/05](findings/05-used-server-first-boot.md)).
- `bench/`: the exact benchmark script and every raw result file behind our speed tables.
- `tools/`: small scripts we used to measure things (real CPU clock on old AMD chips, speculative-decoding test).
- `scripts/privacy-check.sh`: the scan we run before every push, so no addresses, names or serial numbers leak.

## The basic recipe

1. **Any 64-bit PC from about 2012 on, with 8–16 GB RAM.** RAM matters more than CPU speed: it decides how big
   a model you can load. 16 GB lets you run 7–8B models; 8 GB is comfortable for 3–4B models.
2. **Check for AVX** (`grep -o avx /proc/cpuinfo | head -1` on Linux). Every machine in our tables has it.
   CPUs without AVX (some Pentium and Celeron models) are much slower for AI.
3. **Install Ubuntu Server** (free), then [llama.cpp](https://github.com/ggml-org/llama.cpp) or
   [Ollama](https://ollama.com) (both free).
4. **Start with a small model:** IBM Granite 4.0 H-Tiny, Qwen3 4B Instruct or Llama 3.2 3B, at the Q4_K_M
   size. Move up only if the speed is acceptable.
5. **Add a chat page** like [Open WebUI](https://github.com/open-webui/open-webui) so the whole family can use
   it from a phone or browser on your home network.

## Honesty rules for this repo

- Measured numbers say so, with the date and the machine. Estimates are labelled **ESTIMATE**.
- Failed experiments stay in. A "no gain" result saves the next person a weekend.
- No personal information: no addresses, names, serial numbers or network details. See
  `scripts/privacy-check.sh`.

## Add your machine

Ran something on your own old hardware? Run [`bench/bench.py`](bench/) and open an issue with the result file, or
just tell us the machine, RAM, CPU, model and the tokens per second you got. The more machines, the more useful this gets for everyone.

## License

MIT. Use it, copy it, teach with it.
