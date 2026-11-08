#!/usr/bin/env python3
"""hive-bench: one script, same tests, any machine.

Measures how long a local model takes to load, how fast it reads a prompt and writes an answer, how much
memory it holds, and whether it gets ten easy questions right. Standard library only (Python 3.8+), so the
same file runs on an old Linux laptop, a Windows PC or a Mac.

  python3 bench.py --label hp-envy-m6 --machine "HP Envy m6 (2013)" --backend ollama --model llama3.2:3b
  python3 bench.py --label hp-envy-m6 --backend llama-server --model bonsai-8b \\
      --launch "./llama-server -m Bonsai-8B.gguf -c 4096 --port 8099" --url http://127.0.0.1:8099

Results go to results/<label>--<model>.json; report.py turns them into one table. Nothing identifying is
saved: no hostname, user name, IP address, server URL or file path. Only hardware, software versions and
numbers.
"""
import argparse
import ctypes
import datetime
import json
import os
import platform
import random
import re
import shlex
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

SCHEMA = 1
SEED = 42

GEN_PROMPT = ("Write a long, detailed story about a lighthouse keeper who finds a message in a bottle. "
              "Keep writing until you are stopped.")

QUALITY = [  # (question, regex the answer must match, case-sensitive)
    ("What is 17 + 26? Answer with just the number.", r"\b43\b", False),
    ("What is the capital of Australia? Answer with one word.", r"canberra", False),
    ("Spell the word 'house' backwards. Answer with just the letters.", r"esuoh", False),
    ("A train leaves at 3:15 PM and the trip takes 2 hours 50 minutes. What time does it arrive? "
     "Answer like 6:05 PM.", r"6:05\s*p\.?\s*m", False),
    ("Which is heavier: a kilogram of feathers or a kilogram of steel? Answer in a few words.",
     r"same|equal|neither|both", False),
    ("Put these numbers in order from smallest to largest: 42, 7, 19, 3, 25. "
     "Answer with just the numbers separated by commas.", r"3,\s*7,\s*19,\s*25,\s*42", False),
    ("What is the chemical symbol for gold? Answer with just the symbol.", r"\bAu\b", True),
    ("Tom is taller than Ann. Ann is taller than Bo. Who is the shortest? Answer with one word.",
     r"\bbo\b", False),
    ("How many days are in a leap year? Answer with just the number.", r"\b366\b", False),
    ("Translate 'thank you' into Spanish. Answer with just the translation.", r"gracias", False),
]


def long_prompt(nonce):
    """About 1,000 tokens of made-up inventory, the same on every machine. The nonce goes first so a
    runtime can't reuse the previous run's work (prompt caching would inflate the reading speed)."""
    rng = random.Random(7)
    things = ["boxes of nails", "rolls of tape", "bags of cement", "coils of wire", "cans of paint",
              "sheets of plywood", "buckets of screws", "spools of rope", "cartons of gloves", "drums of oil"]
    places = ["shed A", "shed B", "the north bay", "the loft", "the back lot", "bin 4", "rack 12", "the van"]
    lines = ["Run %s. Inventory sheet:" % nonce]
    for i in range(1, 61):
        lines.append("Item %d: %d %s stored in %s, last checked on day %d by crew %s." % (
            i, rng.randint(2, 90), rng.choice(things), rng.choice(places), rng.randint(1, 30),
            rng.choice("ABCDEFG")))
    lines.append("Summarize this inventory in three sentences.")
    return "\n".join(lines)


# ── small helpers ─────────────────────────────────────────────────────────

def log(msg):
    print(msg, file=sys.stderr, flush=True)


def run(cmd, timeout=10):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return out.stdout.strip()
    except Exception:
        return ""


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def http(url, body=None, timeout=60):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode() or "null")


def powershell(expr):
    return run(["powershell", "-NoProfile", "-Command", expr], timeout=30)


def gb(n_bytes):
    return round(n_bytes / 1e9, 2) if n_bytes else None


def ram_gb(n_bytes):
    """Installed RAM in GiB, so a 16 GB machine reads 16, not 17.18."""
    return round(n_bytes / 2 ** 30, 1) if n_bytes else None


# ── hardware and OS ───────────────────────────────────────────────────────

def hardware():
    system = platform.system()
    hw = {"arch": platform.machine(), "logical_cores": os.cpu_count()}
    if system == "Linux":
        cpuinfo = read("/proc/cpuinfo")
        m = re.search(r"^model name\s*:\s*(.+)$", cpuinfo, re.M)
        hw["cpu"] = m.group(1).strip() if m else platform.processor()
        cores = set(re.findall(r"^physical id\s*:\s*(\d+)\s*\n(?:.*\n)*?core id\s*:\s*(\d+)", cpuinfo, re.M))
        hw["physical_cores"] = len(cores) or None
        m = re.search(r"^flags\s*:\s*(.+)$", cpuinfo, re.M)
        flags = set(m.group(1).split()) if m else set()
        hw["cpu_features"] = [f for f in ("sse4_2", "avx", "f16c", "fma", "avx2", "avx512f", "avx512_vnni",
                                          "avx_vnni") if f in flags] or (["neon"] if "asimd" in cpuinfo else [])
        m = re.search(r"^MemTotal:\s*(\d+) kB", read("/proc/meminfo"), re.M)
        hw["ram_gb"] = ram_gb(int(m.group(1)) * 1024) if m else None
        os_name = re.search(r'^PRETTY_NAME="?([^"\n]+)', read("/etc/os-release"), re.M)
        hw["os"] = os_name.group(1) if os_name else "Linux " + platform.release()
    elif system == "Darwin":
        hw["cpu"] = run(["sysctl", "-n", "machdep.cpu.brand_string"]) or platform.processor()
        hw["physical_cores"] = int(run(["sysctl", "-n", "hw.physicalcpu"]) or 0) or None
        hw["ram_gb"] = ram_gb(int(run(["sysctl", "-n", "hw.memsize"]) or 0))
        if platform.machine() == "arm64":
            hw["cpu_features"] = ["neon"]
        else:
            hw["cpu_features"] = [f for f in ("avx1_0", "avx2_0", "avx512f")
                                  if run(["sysctl", "-n", "hw.optional." + f]) == "1"]
        hw["os"] = "macOS " + (run(["sw_vers", "-productVersion"]) or platform.mac_ver()[0])
    elif system == "Windows":
        hw["cpu"] = powershell("(Get-CimInstance Win32_Processor).Name") or platform.processor()
        hw["physical_cores"] = int((powershell("(Get-CimInstance Win32_Processor).NumberOfCores") or "0")
                                   .split()[0]) or None
        hw["ram_gb"] = ram_gb(int(powershell("(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory") or 0))
        present = ctypes.windll.kernel32.IsProcessorFeaturePresent
        hw["cpu_features"] = [n for n, pf in (("avx", 39), ("avx2", 40), ("avx512f", 41)) if present(pf)]
        hw["os"] = "Windows " + platform.release() + " (" + platform.version() + ")"
    gpu = run(["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader"])
    hw["gpu"] = gpu.splitlines()[0] if gpu else None
    return hw


# ── memory sampling ───────────────────────────────────────────────────────

def rss_bytes(pid=None, name=None):
    """Resident memory of one process, or the sum of every process whose program name contains `name`."""
    system = platform.system()
    total = 0
    if system == "Linux":
        pids = [str(pid)] if pid else [p for p in os.listdir("/proc") if p.isdigit()]
        for p in pids:
            if name and name not in read("/proc/%s/comm" % p):
                continue
            m = re.search(r"^VmRSS:\s*(\d+) kB", read("/proc/%s/status" % p), re.M)
            total += int(m.group(1)) * 1024 if m else 0
    elif system == "Darwin":
        args = ["ps", "-o", "rss=,command=", "-p", str(pid)] if pid else ["ps", "-axo", "rss=,command="]
        for line in run(args).splitlines():
            parts = line.split(None, 1)
            if len(parts) == 2 and (pid or name in os.path.basename(parts[1].split()[0])):
                total += int(parts[0]) * 1024
    elif system == "Windows":
        args = ["tasklist", "/FO", "CSV", "/NH"] + (["/FI", "PID eq %d" % pid] if pid else [])
        for line in run(args).splitlines():
            cols = [c.strip('"') for c in line.split('","')]
            if len(cols) >= 5 and (pid or name.lower() in cols[0].lower()):
                total += int(re.sub(r"\D", "", cols[4]) or 0) * 1024
    return total


class PeakMemory(threading.Thread):
    def __init__(self, pid=None, name=None):
        super().__init__(daemon=True)
        # not self.name: Thread already uses that for its own label
        self.pid, self.match, self.peak, self.stop_flag = pid, name, 0, threading.Event()

    def run(self):
        while not self.stop_flag.is_set():
            self.peak = max(self.peak, rss_bytes(self.pid, self.match))
            self.stop_flag.wait(1.0)

    def stop(self):
        self.stop_flag.set()
        if self.is_alive():
            self.join(timeout=5)
        return self.peak


# ── backends ──────────────────────────────────────────────────────────────

class Ollama:
    proc_name = "ollama"

    def __init__(self, url, model, ctx, threads, timeout):
        self.url, self.model, self.timeout = url.rstrip("/"), model, timeout
        self.options = {"temperature": 0, "seed": SEED, "num_ctx": ctx}
        if threads:
            self.options["num_thread"] = threads

    def version(self):
        return "ollama " + http(self.url + "/api/version", timeout=10).get("version", "?")

    def model_info(self):
        show = http(self.url + "/api/show", {"model": self.model}, timeout=30)
        d = show.get("details", {})
        # Thinking models would spend the answer budget thinking; switch it off so they're timed on answers.
        self.think = "thinking" in (show.get("capabilities") or [])
        return {"thinking_off": self.think or None, "name": self.model, "family": d.get("family"), "params": d.get("parameter_size"),
                "quant": d.get("quantization_level"), "format": d.get("format")}

    def load_seconds(self):
        """Unload the model, then time a one-token request: Ollama reports the load on its own."""
        http(self.url + "/api/generate", {"model": self.model, "keep_alive": 0}, timeout=60)
        time.sleep(2)
        r = http(self.url + "/api/generate", {"model": self.model, "prompt": "Hi", "stream": False,
                                              "options": dict(self.options, num_predict=1)}, timeout=self.timeout)
        return round(r.get("load_duration", 0) / 1e9, 2)

    def chat(self, prompt, max_tokens):
        t0 = time.time()
        r = http(self.url + "/api/chat", {"model": self.model, "stream": False, "keep_alive": "10m",
                                          "messages": [{"role": "user", "content": prompt}],
                                          "options": dict(self.options, num_predict=max_tokens),
                                          **({"think": False} if getattr(self, "think", False) else {})},
                 timeout=self.timeout)
        pe, pd = r.get("prompt_eval_count", 0), r.get("prompt_eval_duration", 0)
        ec, ed = r.get("eval_count", 0), r.get("eval_duration", 0)
        return {"text": r.get("message", {}).get("content", ""), "prompt_tokens": pe, "gen_tokens": ec,
                "prompt_tps": round(pe / (pd / 1e9), 2) if pd else None,
                "gen_tps": round(ec / (ed / 1e9), 2) if ed else None, "wall_s": round(time.time() - t0, 2)}

    def resident(self):
        for m in http(self.url + "/api/ps", timeout=10).get("models", []):
            if m.get("name") == self.model or m.get("model") == self.model:
                return {"model_mem_gb": gb(m.get("size")), "gpu_mem_gb": gb(m.get("size_vram"))}
        return {}


class LlamaServer:
    """llama.cpp's llama-server, or any fork of it (PrismML's Bonsai build included)."""
    proc_name = "llama-server"

    def __init__(self, url, model, ctx, threads, timeout):
        self.url, self.model, self.timeout = url.rstrip("/"), model, timeout

    def version(self):
        try:
            p = http(self.url + "/props", timeout=10)
            return "llama-server " + str(p.get("build_info") or "?")
        except Exception:
            return "llama-server ?"

    def model_info(self):
        info = {"name": self.model}
        try:
            p = http(self.url + "/props", timeout=10)
            path = p.get("model_path") or ""
            info["file"] = os.path.basename(path.replace("\\", "/")) or None  # never the full path
            info["ctx"] = (p.get("default_generation_settings") or {}).get("n_ctx")
        except Exception:
            pass
        return info

    def load_seconds(self):
        return None  # only known when this script launches the server (see --launch)

    def chat(self, prompt, max_tokens):
        t0 = time.time()
        r = http(self.url + "/v1/chat/completions",
                 {"model": self.model, "messages": [{"role": "user", "content": prompt}], "stream": False,
                  "max_tokens": max_tokens, "temperature": 0, "seed": SEED, "cache_prompt": False},
                 timeout=self.timeout)
        wall = time.time() - t0
        text = ((r.get("choices") or [{}])[0].get("message") or {}).get("content", "")
        t = r.get("timings") or {}
        if t:
            return {"text": text, "prompt_tokens": t.get("prompt_n"), "gen_tokens": t.get("predicted_n"),
                    "prompt_tps": round(t.get("prompt_per_second") or 0, 2) or None,
                    "gen_tps": round(t.get("predicted_per_second") or 0, 2) or None, "wall_s": round(wall, 2)}
        u = r.get("usage") or {}  # older builds: whole-request speed only, marked approximate
        ct = u.get("completion_tokens", 0)
        return {"text": text, "prompt_tokens": u.get("prompt_tokens"), "gen_tokens": ct, "prompt_tps": None,
                "gen_tps": round(ct / wall, 2) if wall else None, "wall_s": round(wall, 2), "approx": True}

    def resident(self):
        return {}


def launch(cmd, url, timeout):
    """Start the server ourselves so the load time and its exact memory can be measured."""
    log("Starting server: " + cmd)
    proc = subprocess.Popen(cmd if os.name == "nt" else shlex.split(cmd),
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    t0 = time.time()
    while time.time() - t0 < timeout:
        if proc.poll() is not None:
            sys.exit("The server exited during startup (code %s). Run the --launch command by hand to see why."
                     % proc.returncode)
        try:
            if http(url.rstrip("/") + "/health", timeout=5).get("status") == "ok":
                return proc, round(time.time() - t0, 2)
        except (urllib.error.URLError, OSError, ValueError, AttributeError):
            pass
        time.sleep(0.5)
    proc.terminate()
    sys.exit("The server didn't become ready within %d s." % timeout)


# ── the run ───────────────────────────────────────────────────────────────

def summary(values):
    vals = [v for v in values if v]
    return {"runs": values, "median": round(statistics.median(vals), 2) if vals else None}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--label", required=True, help="short machine id for file names, e.g. hp-envy-m6")
    ap.add_argument("--machine", default="", help='public description, e.g. "HP Envy m6 laptop (2013)"')
    ap.add_argument("--backend", choices=["ollama", "llama-server"], default="ollama")
    ap.add_argument("--model", required=True, help="model name (Ollama tag, or a label for llama-server)")
    ap.add_argument("--url", help="server address (default: Ollama 127.0.0.1:11434, llama-server :8080)")
    ap.add_argument("--launch", help="llama-server only: command that starts the server, timed for load")
    ap.add_argument("--repeats", type=int, default=3, help="runs per speed test, median reported")
    ap.add_argument("--gen-tokens", type=int, default=128, help="tokens to write in the writing test")
    ap.add_argument("--ctx", type=int, default=4096, help="context size (Ollama; pass -c in --launch)")
    ap.add_argument("--threads", type=int, help="CPU threads (Ollama); default lets the runtime decide")
    ap.add_argument("--timeout", type=int, default=1800, help="seconds per request; old machines need long")
    ap.add_argument("--skip-quality", action="store_true")
    ap.add_argument("--notes", default="", help="anything worth knowing, e.g. 'on battery'")
    ap.add_argument("--hardware-file", help="JSON describing the server's machine, when it isn't this one")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "results"))
    a = ap.parse_args()

    url = a.url or ("http://127.0.0.1:11434" if a.backend == "ollama" else "http://127.0.0.1:8080")
    Backend = Ollama if a.backend == "ollama" else LlamaServer
    be = Backend(url, a.model, a.ctx, a.threads, a.timeout)

    remote = urllib.parse.urlparse(url).hostname not in ("127.0.0.1", "localhost", "::1")
    if remote and not a.hardware_file:
        sys.exit("The server is on another machine: describe it with --hardware-file (see README).")
    if a.hardware_file:  # testing a server on another machine (e.g. a Windows PC that throttles SSH sessions)
        with open(a.hardware_file, encoding="utf-8") as f:
            hw = json.load(f)
    else:
        log("Reading hardware...")
        hw = hardware()
    log("  %s, %s GB RAM, %s" % (hw.get("cpu"), hw.get("ram_gb"), hw.get("os")))

    server, load_s = None, None
    if a.launch:
        if a.backend != "llama-server":
            sys.exit("--launch is for llama-server; Ollama measures its own load time.")
        server, load_s = launch(a.launch, url, a.timeout)
        sampler = PeakMemory(pid=server.pid)
    else:
        sampler = PeakMemory(name=be.proc_name)
    if not remote:  # process memory can only be read on this machine
        sampler.start()

    try:
        result = {"schema": SCHEMA, "label": a.label, "machine": a.machine, "notes": a.notes,
                  "date": datetime.date.today().isoformat(), "hardware": hw,
                  "software": {"backend": a.backend, "runtime": be.version(), "python": platform.python_version()},
                  "model": be.model_info(),
                  "settings": {"ctx": a.ctx, "threads": a.threads, "repeats": a.repeats, "gen_tokens": a.gen_tokens,
                               "temperature": 0, "seed": SEED}}
        log("Model: %s via %s" % (a.model, result["software"]["runtime"]))

        if load_s is None:
            log("Timing a cold load...")
            load_s = be.load_seconds()
        result["load_s"] = load_s
        log("  load: %s s" % load_s)

        log("Warm-up...")
        be.chat("Say hello.", 8)

        gen, read_ = [], []
        for i in range(1, a.repeats + 1):
            r = be.chat("(%d) %s" % (i, GEN_PROMPT), a.gen_tokens)
            gen.append(r["gen_tps"])
            log("  writing test %d/%d: %s tok/s (%s tokens, %s s)" % (i, a.repeats, r["gen_tps"], r["gen_tokens"],
                                                                     r["wall_s"]))
            r = be.chat(long_prompt("%d-%d" % (i, random.randint(0, 99999))), 64)
            read_.append(r["prompt_tps"])
            log("  reading test %d/%d: %s tok/s (%s prompt tokens)" % (i, a.repeats, r["prompt_tps"],
                                                                      r["prompt_tokens"]))
            if r.get("approx"):
                result["speed_note"] = "runtime gave no timings; writing speed is whole-request and approximate"
        result["gen_tps"] = summary(gen)
        result["prompt_tps"] = summary(read_)

        if not a.skip_quality:
            items = []
            for q, pattern, case in QUALITY:
                ans = be.chat(q, 160)["text"]  # room to reason before answering.strip()
                ok = bool(re.search(pattern, ans, 0 if case else re.I))
                items.append({"q": q, "answer": ans[:200], "ok": ok})
                log("  %s %s" % ("PASS" if ok else "FAIL", q[:60]))
            result["quality"] = {"score": sum(i["ok"] for i in items), "out_of": len(items), "items": items}

        result.update(be.resident())
    finally:
        result_peak = sampler.stop()
        if server:
            server.terminate()

    result["peak_rss_gb"] = gb(result_peak)
    if platform.system() == "Darwin" and a.backend == "ollama":
        result["memory_note"] = "On Apple Silicon, GPU memory may not count in RSS; see model_mem_gb."

    os.makedirs(a.out, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", "%s--%s" % (a.label, a.model))
    path = os.path.join(a.out, safe + ".json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    log("\nWriting %s tok/s · reading %s tok/s · load %s s · peak memory %s GB · quality %s" % (
        result["gen_tps"]["median"], result["prompt_tps"]["median"], load_s, result["peak_rss_gb"],
        "%d/%d" % (result["quality"]["score"], result["quality"]["out_of"]) if "quality" in result else "skipped"))
    log("Saved " + path)


if __name__ == "__main__":
    main()
