#!/usr/bin/env python3
"""Turn every results/*.json from bench.py into RESULTS.md: one comparison table plus machine details."""
import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def cell(v, suffix=""):
    return "—" if v in (None, "") else "%s%s" % (v, suffix)


def main():
    rows = []
    for path in sorted(glob.glob(os.path.join(HERE, "results", "*.json"))):
        with open(path, encoding="utf-8") as f:
            rows.append(json.load(f))
    rows.sort(key=lambda r: (r.get("label", ""), -(r.get("gen_tps", {}).get("median") or 0)))

    out = ["# Hive bench results", "",
           "Same script, same prompts, temperature 0. Writing and reading speeds are tokens per second "
           "(median of the runs); quality is ten easy questions with one right answer each.", "",
           "| Machine | Model | Quant | Runtime | Load (s) | Writing tok/s | Reading tok/s | Peak memory (GB) | Quality |",
           "|---|---|---|---|---:|---:|---:|---:|---:|"]
    for r in rows:
        m, q = r.get("model", {}), r.get("quality")
        out.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            r.get("machine") or r.get("label"), m.get("name"), cell(m.get("quant") or m.get("file")),
            r.get("software", {}).get("runtime"), cell(r.get("load_s")), cell(r.get("gen_tps", {}).get("median")),
            cell(r.get("prompt_tps", {}).get("median")), cell(r.get("model_mem_gb") or r.get("peak_rss_gb")),
            "%d/%d" % (q["score"], q["out_of"]) if q else "—"))

    out += ["", "## Machines", "", "| Machine | CPU | Cores | RAM (GB) | CPU features | GPU | OS |",
            "|---|---|---:|---:|---|---|---|"]
    seen = set()
    for r in rows:
        key = r.get("machine") or r.get("label")
        if key in seen:
            continue
        seen.add(key)
        h = r.get("hardware", {})
        out.append("| %s | %s | %s/%s | %s | %s | %s | %s |" % (
            key, h.get("cpu"), cell(h.get("physical_cores")), cell(h.get("logical_cores")), cell(h.get("ram_gb")),
            ", ".join(h.get("cpu_features") or []) or "—", cell(h.get("gpu")), h.get("os")))

    notes = [(r.get("machine") or r.get("label"), r.get("model", {}).get("name"), n)
             for r in rows for n in (r.get("notes"), r.get("speed_note"), r.get("memory_note")) if n]
    if notes:
        out += ["", "## Notes", ""] + ["- **%s / %s:** %s" % n for n in notes]

    with open(os.path.join(HERE, "RESULTS.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print("Wrote RESULTS.md (%d runs)" % len(rows))


if __name__ == "__main__":
    main()
