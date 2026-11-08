#!/usr/bin/env python3
"""hive-bench context sweep: what happens as the prompt gets long.

For each size (default 2k, 8k, 16k, 32k tokens) it fills the prompt with made-up inventory, hides one fact
about 40% of the way in, and asks for it at the end. It records reading speed, writing speed with that much
context behind it, peak memory, and whether the model found the fact.

  python3 context.py --label hp-envy-m6 --machine "HP Envy m6 (2013)" --backend llama-server \\
      --model Llama-3.2-3B-Instruct-Q4_K_M --gguf ~/models/Llama-3.2-3B-Instruct-Q4_K_M.gguf
  python3 context.py ... --extra "-fa on -ctk q8_0 -ctv q8_0" --variant fa-kvq8   # the memory fixes
  python3 context.py ... --backend ollama --model llama3.2:3b                          # Ollama: num_ctx per size

llama-server is restarted for every size so each memory reading belongs to that size alone. A size is
skipped when the previous one predicts it would take longer than --max-minutes or wouldn't fit in memory.
"""
import argparse
import datetime
import json
import os
import platform
import random
import re
import sys
import time

import bench

HERE = os.path.dirname(os.path.abspath(__file__))
FACT = "Note for the record: the access code for the blue shed is 4817."
# The answer starts with the code, then keeps writing so the writing speed is measured over 64 tokens, not 4.
QUESTION = ("\n\nQuestion: what is the access code for the blue shed? Give the code first, then describe the "
            "inventory in a paragraph.")
TOKENS_PER_LINE = 24.5  # measured: 60 inventory lines came to ~1,500 tokens on Llama 3.2 and Qwen3 tokenizers


def room(size):
    """Context to allocate: tokenizers differ (Qwen3 counts ~10% more than Llama for the same text), plus the answer."""
    return int(size * 1.25) + 1024


def filled_prompt(target_tokens, nonce):
    rng = random.Random(target_tokens)
    things = ["boxes of nails", "rolls of tape", "bags of cement", "coils of wire", "cans of paint",
              "sheets of plywood", "buckets of screws", "spools of rope", "cartons of gloves", "drums of oil"]
    places = ["shed A", "shed B", "the north bay", "the loft", "the back lot", "bin 4", "rack 12", "the van"]
    n = max(10, int((target_tokens - 60) / TOKENS_PER_LINE))
    lines = ["Run %s. Inventory log:" % nonce]
    for i in range(1, n + 1):
        if i == int(n * 0.4):
            lines.append(FACT)
        lines.append("Item %d: %d %s stored in %s, last checked on day %d by crew %s." % (
            i, rng.randint(2, 90), rng.choice(things), rng.choice(places), rng.randint(1, 30),
            rng.choice("ABCDEFG")))
    return "\n".join(lines) + QUESTION


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--label", required=True)
    ap.add_argument("--machine", default="")
    ap.add_argument("--backend", choices=["ollama", "llama-server"], default="llama-server")
    ap.add_argument("--model", required=True)
    ap.add_argument("--gguf", help="llama-server: model file (the server is started per size)")
    ap.add_argument("--server", default="llama-server", help="llama-server binary")
    ap.add_argument("--extra", default="", help="extra llama-server flags, e.g. '-fa on -ctk q8_0 -ctv q8_0'")
    ap.add_argument("--variant", default="default", help="name for this setting, e.g. fa-kvq8")
    ap.add_argument("--url", help="Ollama address (default 127.0.0.1:11434); llama-server uses port 8099")
    ap.add_argument("--hardware-file")
    ap.add_argument("--sizes", default="2048,8192,16384,32768")
    ap.add_argument("--max-minutes", type=float, default=45, help="skip a size predicted to read longer than this")
    ap.add_argument("--gen-tokens", type=int, default=64)
    ap.add_argument("--nice", action="store_true", help="run the server at lowest CPU priority (Linux/macOS)")
    ap.add_argument("--notes", default="")
    a = ap.parse_args()

    if a.backend == "llama-server" and not a.gguf:
        sys.exit("--gguf is needed for llama-server.")
    url = a.url or ("http://127.0.0.1:11434" if a.backend == "ollama" else "http://127.0.0.1:8099")
    remote = bench.urllib.parse.urlparse(url).hostname not in ("127.0.0.1", "localhost", "::1")
    if a.hardware_file:
        with open(a.hardware_file, encoding="utf-8") as f:
            hw = json.load(f)
    elif remote:
        sys.exit("The server is on another machine: describe it with --hardware-file.")
    else:
        hw = bench.hardware()
    ram = (hw.get("ram_gb") or 0) * 2 ** 30
    bench.log("%s, %s GB RAM · %s · %s" % (hw.get("cpu"), hw.get("ram_gb"), a.model, a.variant))

    steps, runtime, prev = [], None, None
    for size in [int(s) for s in a.sizes.split(",")]:
        if prev and prev.get("prompt_tps"):
            minutes = size / prev["prompt_tps"] / 60 * 1.3  # reading gets slower per token as prompts grow
            if minutes > a.max_minutes:
                steps.append({"ctx": size, "skipped": "predicted %.0f min to read (limit %g)" % (minutes, a.max_minutes)})
                bench.log("  %6d: skipped, predicted %.0f min" % (size, minutes))
                continue
            if prev.get("peak_rss_gb") and ram:
                grow = (prev["peak_rss_gb"] - (steps[0].get("peak_rss_gb") or 0)) / max(1, prev["ctx"] - steps[0]["ctx"])
                need = prev["peak_rss_gb"] + grow * (size - prev["ctx"]) if grow > 0 else 0
                if need * 1e9 > ram * 0.85:
                    steps.append({"ctx": size, "skipped": "predicted %.1f GB, over 85%% of RAM" % need})
                    bench.log("  %6d: skipped, predicted %.1f GB" % (size, need))
                    continue

        server, sampler = None, None
        try:
            if a.backend == "llama-server":
                cmd = "%s%s -m %s -c %d -np 1 --port 8099 --host 127.0.0.1 %s" % (
                    "nice -n 19 " if a.nice else "", a.server, os.path.expanduser(a.gguf), room(size), a.extra)
                server, load_s = bench.launch(cmd.strip(), url, 1800)
                be = bench.LlamaServer(url, a.model, size, None, 7200)
                sampler = bench.PeakMemory(pid=server.pid)
            else:
                be = bench.Ollama(url, a.model, room(size), None, 7200)
                be.model_info()  # learns whether to switch thinking off
                sampler = bench.PeakMemory(name="ollama")
            if not remote:
                sampler.start()
            runtime = runtime or be.version()
            be.chat("Say hello.", 4)
            t0 = time.time()
            r = be.chat(filled_prompt(size, random.randint(0, 99999)), a.gen_tokens)
            found = "4817" in r["text"]
            # A runtime that silently cuts the prompt (Ollama does at its own limit) loses the fact: say so.
            truncated = bool(r["prompt_tokens"]) and r["prompt_tokens"] < size * 0.9
            step = {"ctx": size, "prompt_tokens": r["prompt_tokens"], "prompt_tps": r["prompt_tps"],
                    "gen_tps": r["gen_tps"], "wall_s": round(time.time() - t0, 1), "found_fact": found,
                    "answer": r["text"].strip()[:120], "truncated": truncated or None}
            if a.backend == "ollama":
                step.update(be.resident())
        except Exception as e:  # out of memory, timeout: record it and stop going bigger
            step = {"ctx": size, "error": "%s: %s" % (type(e).__name__, str(e)[:200])}
        finally:
            peak = sampler.stop() if sampler else 0
            if server:
                server.terminate()
                server.wait(timeout=30)
        step["peak_rss_gb"] = bench.gb(peak)
        steps.append(step)
        bench.log("  %6d: read %s tok/s · write %s tok/s · %s GB · fact %s · %s s" % (
            size, step.get("prompt_tps"), step.get("gen_tps"), step.get("peak_rss_gb") or step.get("model_mem_gb"),
            "found" if step.get("found_fact") else "MISSED", step.get("wall_s")) if "error" not in step
            else "  %6d: %s" % (size, step["error"]))
        if "error" in step:
            break
        prev = step

    out = {"schema": 1, "kind": "context-sweep", "label": a.label, "machine": a.machine, "notes": a.notes,
           "date": datetime.date.today().isoformat(), "hardware": hw, "variant": a.variant, "extra_flags": a.extra,
           "software": {"backend": a.backend, "runtime": runtime, "python": platform.python_version()},
           "model": {"name": a.model, "file": os.path.basename(a.gguf) if a.gguf else None}, "steps": steps}
    os.makedirs(os.path.join(HERE, "results", "context"), exist_ok=True)
    path = os.path.join(HERE, "results", "context",
                        re.sub(r"[^A-Za-z0-9._-]+", "_", "%s--%s--%s" % (a.label, a.model, a.variant)) + ".json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
    bench.log("Saved " + path)


if __name__ == "__main__":
    main()
