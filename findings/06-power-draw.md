# 06. What does an old AI box cost to run?

**These are ESTIMATES (November 2026), not measurements yet.** We'll replace them with readings from a plug-in
power meter.

## Dell PowerEdge T20 (Haswell CPU, 1 RAM stick, 1 hard drive, small graphics card)

| State | What it looks like | Watts at the wall | Per year if it stayed there 24/7, at $0.15/kWh |
|---|---|---|---|
| Idle | On, nothing running | 25–35 W | ~$33–46 |
| Mid | Family chat now and then, a few cores busy in bursts | 45–60 W | ~$59–79 |
| High | A model running on every core, nonstop | 75–95 W with a Xeon; ~55–65 W with a Pentium | ~$99–125 |

A realistic day (mostly idle, some bursts) should average **30–40 W, roughly $40–55 a year**.

## Tips

- **A graphics card you don't use still costs 5–10 W.** On a headless box, remove it, but **only if the CPU has
  built-in graphics**; otherwise the machine won't pass its self-test without one.
- **Measure, don't guess.** A plug-in power meter (about $15–20) tells you within a watt. Measure idle, a chat,
  and a long full-load run.
- **Your price per kWh matters more than the watts.** Multiply: watts × 8.76 = kWh per year if left on 24/7.
  Then multiply by your price per kWh.

## Coming next

Measured idle / mid / high numbers for every machine in [01](01-speeds-on-old-machines.md), so you can compare
cost per answer, not just speed.
