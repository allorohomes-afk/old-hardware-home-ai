# 05. First boot of a used tower server (Dell PowerEdge T20)

Used entry-level tower servers like the Dell PowerEdge T20 (2014) are cheap, quiet, take up to 32 GB of ECC
RAM, and many were sold with a Xeon CPU with AVX2 (ours wasn't; see Problem 4). They make good home AI boxes.
Ours arrived with one 4 GB stick, a 1 TB hard drive and a small graphics card.

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

## Problem 2: installed fine, then sat silent: a dead BIOS battery

- We installed Ubuntu Server with no screen, using `kits/headless-ubuntu-autoinstall`. The install ran by itself
  and powered off after about 14 minutes, which means it succeeded.
- After removing the USB stick and powering on: solid white light, but **no network activity at all**.
- **What the screen showed** (once we connected one): *"Invalid configuration information"* and *"Time-of-day not
  set: please run SETUP program. To continue press F1."* The machine was **waiting for a key press** before it
  would even start Ubuntu.
- **Cause:** the coin battery on the motherboard (CR2032) was dead, so the firmware forgot its settings and clock
  every time it lost power.
- **Fix:** replace the CR2032 (a few dollars at any drugstore, + side up), then in setup (F2) set the date and time,
  **POST Behavior → Keyboard Errors: Disable**, **Power Management → AC Recovery: Power On**, Apply, Exit.
- The boot order was fine: Ubuntu was already first in the UEFI list.

**Lesson:** on any used machine more than a few years old, **expect a dead coin battery**. If it powers on but never
appears on the network, it's probably stopped at a "press F1" screen. Keep a keyboard and one way to see the screen
for the first setup. Check every video port on the back before buying an adapter: ours had a port we'd missed.

## Problem 3: Ubuntu started, but with no network (a bug in our kit, now fixed)

- Ubuntu reached its login prompt, but the wired port was switched off (`networkctl` showed it as **unmanaged**),
  our SSH key was missing, and password logins over SSH were on.
- **Cause:** our kit switched off `cloud-init` (Ubuntu's first-boot setup tool) so nothing would run or download at
  first boot. But on Ubuntu 24.04 that same tool is what applies the installer's network, SSH key and
  password-login settings. Turning it off skipped all three. The user account and password did apply, because a
  different step creates them.
- **Workaround we used:** log in at the keyboard and add a network file by hand, then copy the key with
  `ssh-copy-id`, then switch off password logins.
- **Fix in the kit:** cloud-init stays off, and the kit now writes those three settings itself during the install.
  We tested the new steps against a stand-in install folder. **A full reinstall with the fixed kit hasn't been
  done yet**; we'll update this page when it has.

## Problem 4: the CPU wasn't what we hoped

- `lscpu` showed an **Intel Pentium G3220**: 2 cores, **no AVX at all**. That's the cheapest chip this model was sold
  with. Without AVX, AI models run far slower, and with 4 GB RAM only the smallest ones fit.
- The common fix for this model is a used **Xeon E3-1200 v3** (Dell's own guide lists the E3-1225 v3), which adds AVX2,
  plus DDR3 **ECC unbuffered** RAM (not "registered") up to 32 GB.
- How fast an AI model writes text on these machines depends mostly on memory speed, so expect the upgraded box to
  write at roughly the same speed as other DDR3 machines (see findings/01), with faster prompt reading and room for
  bigger models. We'll measure before and after.

**Lesson:** "used tower server" doesn't mean "Xeon". **Ask the seller for the exact CPU model** (or a photo of the
system information screen) before buying.

## Settings worth changing once you can see setup

- **POST Behavior → Keyboard Errors: Disable** and **Warnings and Errors: Continue on Warnings**, so it never
  stops at boot waiting for a key.
- **System Configuration → SATA Operation: AHCI.**
- **Power Management → AC Recovery: Power On**, so it comes back by itself after a power cut.
