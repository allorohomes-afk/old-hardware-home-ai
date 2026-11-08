# 03. Can you overclock an old laptop for AI? (Usually not.)

**Short version:** our 2013 AMD laptop has a 3.5 GHz turbo speed on paper, but the laptop's firmware switches
turbo off and locks it. Under a full AI load it holds its base 2.5 GHz. Better cooling doesn't change that,
because it isn't overheating; it simply isn't allowed to go faster.

## What we measured

- Laptop: HP Envy m6 (2013), AMD A10-5750M (base 2.5 GHz, turbo up to 3.5 GHz on paper), Ubuntu 24.04.
- Linux reports "2.5 GHz" for this chip whatever it's doing, so we read the CPU's own cycle counters instead
  (`APERF`/`MPERF`, via `tools/amd-fam15h-clock.sh`). That gives the real clock.
- Running an 8B model on all four cores: **2,489 MHz average, 2,496 MHz peak, 82–85 °C.**
- The chip's turbo control register shows turbo **disabled and locked** by the firmware. Linux can't unlock a
  locked bit.

## Why cooling won't help

The chip's heat limit on this laptop is 100 °C; it peaked at 85 °C. It never got close to slowing itself down.
A cooling pad makes it quieter, which is nice, but it won't make it faster.

## What might still matter

- **The charger.** Many laptops turn turbo off when they detect a weaker or non-original charger. If yours has
  a third-party or lower-watt charger, try the original one before anything else. (We haven't confirmed this
  on ours yet.)
- **A firmware setting.** Some laptops have a hidden turbo option in setup. Ours shows none.

## What we'd do instead

On a laptop like this, the gains come from the **model** (see [01](01-speeds-on-old-machines.md)), not the
clock. Use 3–4B models for chat, or give the laptop background work where speed doesn't matter.

## Undervolting and P-state hacks

We read the chip's speed table but did **not** change it. Writing these registers can crash or damage a
machine, and on a locked laptop the turbo states are blocked anyway. Not worth the risk for a few percent.
