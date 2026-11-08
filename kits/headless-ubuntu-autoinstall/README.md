# Headless Ubuntu Server autoinstall

Turn a spare PC into an AI node **without a screen, keyboard or mouse**: build a USB stick on your main computer,
plug it into the spare one, power on, wait, and log in over SSH.

> **STATUS (November 2026): partly verified.** On our first machine (a Dell PowerEdge T20) the install ran
> unattended and powered off by itself after about 14 minutes, which means it finished. **The first boot after
> install has NOT been verified yet:** that machine didn't start Ubuntu, and we haven't seen its screen yet
> (see [findings/05](../../findings/05-used-server-first-boot.md)). Until that's resolved, keep a way to see
> the screen on hand, and expect to fix the boot order in the BIOS.

The result: Ubuntu Server 24.04 LTS, your SSH key only (no password logins), a firewall that allows SSH from your
home network and nothing else, and sudo that asks for a password.

> **WARNING: the stick wipes a disk with no questions asked.** It only wipes a disk whose model matches
> `DISK_MODEL`, which protects other machines it might get plugged into. Label the stick, and don't leave it
> plugged into anything.

## You need

- The Ubuntu Server 24.04.5 ISO (`ubuntu-24.04.5-live-server-amd64.iso`) from ubuntu.com.
- `xorriso` (macOS: `brew install xorriso`; Linux: `sudo apt install xorriso`), `openssl`, `python3`.
- A USB stick of 4 GB or more (it gets erased).
- An SSH key (`ssh-keygen -t ed25519` if you don't have one).
- The spare PC wired to your router with Ethernet. The installer needs internet.
- **Recommended:** one way to see the spare PC's screen for the first boot (see
  [findings/05](../../findings/05-used-server-first-boot.md)).

## Steps

1. `cp node.env.example node.env` and edit it: hostname, user name, time zone, your home network, and the
   **model of the disk to wipe** (from the spare PC's BIOS, or a photo of the drive label; use a glob like `'ST1000*'`).
2. `bash set-password.sh`: the password is typed twice, and only its hash is saved, outside the repo.
3. `bash build-iso.sh`: checks the ISO, builds `autoinstall.iso`, and verifies it.
4. `bash write-usb.sh diskN` (macOS): asks you to type the device name before it erases anything, then reads
   the stick back to verify it.
5. At the spare PC: stick in a **back** USB port, Ethernet in, power on. If it doesn't boot from USB on its
   own, press the boot-menu key (F12 on Dells) and choose the UEFI USB entry.
6. Wait. It **powers itself off** when it's done (about 15 minutes on our hardware). If it's still on after
   45 minutes with the disk light quiet, something went wrong; look at the screen.
7. **Remove the stick**, then power on.
8. On your main computer: `bash find-node.sh 192.168.1` (your network), then `ssh <user>@<ip>`.
9. `ssh <user>@<ip> 'bash -s' < first-login.sh` for a first look: CPU features, RAM, disk health, temperatures.

## Choices made on purpose

- **Nothing that phones home during install:** no geo-IP lookup, no installer self-update, no extra drivers or
  snaps. Add tools like VPNs yourself later, over SSH, once you can see the box.
- **Only SSH open**, and only from your home network.
- **No swap partition.** Add a swap file later if you need one.
- **It powers off instead of rebooting**, so a forgotten stick can't start a second install.
