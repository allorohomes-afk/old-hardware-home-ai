# 05. First boot of a used tower server (Dell PowerEdge T20)

Used entry-level tower servers like the Dell PowerEdge T20 (2014) are cheap, quiet, take up to 32 GB of ECC
RAM, and many have a Xeon CPU with AVX2. They make good home AI boxes. Ours arrived with one 4 GB stick, a 1 TB
hard drive and a small graphics card.

## Problem 1: six beeps and a blinking amber power light

- **Symptom:** at power-on it beeped six times (in a 4 + 2 rhythm), the power button blinked **amber**, and it
  never reached the network.
- **Cause:** the RAM stick had worked loose in shipping.
- **Fix:** unplug the power, hold the power button 5 seconds, then press the stick into the slot labelled
  **DIMM1** until **both clips snap shut on their own**.
- After the fix it powered on and off a few times over 5–10 seconds (normal: the board re-checks memory after a
  change), then stayed on with a **solid white** light.

**Lesson:** on a used Dell, **blinking amber + beeps = a hardware part failed its self-test**. A missing monitor
or keyboard never turns the light amber. Reseat the RAM first: it's the most common cause and costs nothing.

## Problem 2: installed fine, then didn't boot

- We installed Ubuntu Server with no screen, using `kits/headless-ubuntu-autoinstall`. The install ran by itself
  and powered off after about 14 minutes, which means it succeeded.
- After removing the USB stick and powering on: solid white light, but **no network activity at all**. It never
  even asked the router for an address, so Linux wasn't starting.
- **Most likely cause:** the firmware's boot list doesn't include the new Ubuntu entry yet, so it stops at a
  "No boot device" screen. Some Dell firmware ignores the entry the installer adds.
- **Status: not yet confirmed.** We need a screen once to see it. The fix we expect: setup (F2) → Boot
  Sequence → Boot List Option **UEFI** → add or tick **ubuntu** (file `\EFI\ubuntu\shimx64.efi` on the hard
  drive) → Apply. We'll update this page with what it really was.

**Lesson:** even for a "headless" box, have **one way to see the screen** for the first setup. If its only
video port is DVI, a $6 DVI-to-HDMI adapter and any TV will do.

## Settings worth changing once you can see setup

- **POST Behavior → Keyboard Errors: Disable** and **Warnings and Errors: Continue on Warnings**, so it never
  stops at boot waiting for a key.
- **System Configuration → SATA Operation: AHCI.**
- **Power Management → AC Recovery: Power On**, so it comes back by itself after a power cut.
