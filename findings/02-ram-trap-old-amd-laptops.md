# 02. The RAM trap on old AMD laptops

**Short version:** many 2012–2014 AMD laptops can use 2 × 8 GB = 16 GB, but only with 8 GB sticks built from
**sixteen** memory chips. Most 8 GB DDR3L sticks sold new today use **eight** larger chips, and these older
laptops only see **half** of them (4 GB).

## What happened

- Laptop: HP Envy m6 (2013), AMD A10-5750M ("Richland"), 2 slots, came with 2 × 4 GB DDR3L-1600.
- We added a new 8 GB DDR3L-1600 SODIMM (Gigastone GS-DDR3-SO1600CL11-8GB-R). It has **8 chips** on it.
- Result: the laptop counted it as **4 GB**. Total stayed at 8 GB instead of 12 GB.
- Linux showed the same thing in the firmware's own memory map (`dmesg | grep e820`), so it isn't a Linux
  driver problem: the laptop's memory controller only addresses half of each chip.

## Why

DDR3 chips come in sizes. Older memory controllers from that era (AMD's 2012–2013 laptop chips, and some Intel
ones from the same years) were built for chips up to **4 Gbit** each. Newer 8 GB sticks use eight **8 Gbit**
chips, and the old controller can only reach half of each one.

An 8 GB stick made from sixteen 4 Gbit chips (eight on each side) works fine.

## How to buy the right stick

Look for all three:

1. **"2Rx8"** in the label or listing (two ranks, ×8 chips). "1Rx8" 8 GB sticks are almost always the
   8-chip kind that fails.
2. **16 chips**: eight on each side. Ask the seller for a photo of both sides if the listing doesn't show it.
3. **Used / pulled from an old laptop** is often the safest source: sticks made in 2012–2014 were built with the
   older 4 Gbit chips.

## Things that do NOT fix it

- Drivers, kernel settings or a different OS. The firmware hands the OS a memory map that's already half size.
- BIOS settings. The HP firmware on this laptop has no memory options.

## If you already bought the wrong stick

Return it if you can. It still works as a 4 GB stick in these laptops, and at full 8 GB in newer machines
(2015+).

## Side note: reading the stick's label from Linux didn't work

We tried reading the stick's built-in label (SPD) with `i2c-tools` / `decode-dimms`. This laptop's firmware
claims the memory bus for itself, so Linux can't reach it ("no SMBus adapter"). Looking at the stick and
counting the chips is faster and more reliable.
