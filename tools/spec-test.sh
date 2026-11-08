#!/bin/bash
# Speculative decoding test: a big model alone vs the same model with a small helper model guessing ahead, on the
# same prompts at temperature 0, while sampling CPU clock and temperature. Temporary llama-server on 127.0.0.1 only.
# Prints how many guesses were accepted: if it prints none, speculation was NOT running.
# Run on the machine itself (set LLAMA_SERVER if llama-server isn't at /opt/llama.cpp):
#   bash spec-test.sh big-model.gguf helper-model.gguf
T="${1:-$HOME/models/Qwen3-8B-Q4_K_M.gguf}"
D="${2:-$HOME/models/Qwen3-0.6B-Q4_K_M.gguf}"
PORT=8090
PARSE=/tmp/spec-parse.py
cat >"$PARSE" <<'PY'
import json, sys
try:
    r = json.load(sys.stdin)
except Exception as e:
    print(f"  prompt {sys.argv[1]}: no answer ({e})"); sys.exit()
t = r.get("timings", {})
acc = ""
if t.get("draft_n"):
    acc = f"  guesses accepted {t['draft_n_accepted']}/{t['draft_n']} ({100 * t['draft_n_accepted'] / t['draft_n']:.0f}%)"
print(f"  prompt {sys.argv[1]}: {t.get('predicted_per_second', 0):.2f} tok/s over {t.get('predicted_n', 0)} tokens{acc}")
PY
OUT="$HOME/spec-results/spec-$(date +%Y%m%d-%H%M).log"
mkdir -p "$(dirname "$OUT")"
PROMPTS=(
  "Write a short, friendly paragraph explaining why the sky is blue, for a curious ten-year-old."
  "Write a Python function that reads a CSV file of expenses (date, category, amount) and returns the total per category as a dict. Include a docstring."
)

sample() {  # clock in MHz (mean of cores) and CPU temp, every 2 s, until killed
  while :; do
    mhz=$(awk -F: '/cpu MHz/ {s+=$2; n++} END {printf "%.0f", s/n}' /proc/cpuinfo)
    t=$(cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | head -1)
    for h in /sys/class/hwmon/hwmon*; do [ "$(cat $h/name)" = k10temp ] && t=$(cat $h/temp1_input); done
    echo "$mhz $((t / 1000))"
    sleep 2
  done
}

run() {  # $1 = label, rest = extra server args
  label=$1; shift
  "${LLAMA_SERVER:-/opt/llama.cpp/llama-server}" -m "$T" -c 2048 -t 4 --host 127.0.0.1 --port $PORT --no-webui "$@" >/tmp/spec-server.log 2>&1 &
  srv=$!
  for _ in $(seq 120); do curl -sf http://127.0.0.1:$PORT/health >/dev/null && break; sleep 1; done
  sample >/tmp/spec-clock.log & smp=$!
  for i in "${!PROMPTS[@]}"; do
    body=$(python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "n_predict": 160, "temperature": 0, "cache_prompt": False}))' "${PROMPTS[$i]}")
    curl -s http://127.0.0.1:$PORT/completion -H 'Content-Type: application/json' -d "$body" |
      python3 "$PARSE" "$((i + 1))"
  done
  kill $smp; kill $srv; wait $srv 2>/dev/null
  awk '{m+=$1; if ($1>mx) mx=$1; if ($2>tx) tx=$2; n++} END {printf "  clock avg %.0f MHz, max %d MHz; CPU temp max %d C\n", m/n, mx, tx}' /tmp/spec-clock.log
}

{
  echo "== $(hostname) $(date '+%F %H:%M')  target $(basename "$T")  draft $(basename "$D")"
  echo "-- baseline (target alone)"; run base
  echo "-- helper model, 4 guesses"; run spec4 -md "$D" --spec-type draft-simple --spec-draft-n-max 4 --spec-draft-n-min 1
  echo "-- helper model, 8 guesses"; run spec8 -md "$D" --spec-type draft-simple --spec-draft-n-max 8 --spec-draft-n-min 1
  echo "-- n-gram guesses (no helper model)"; run ngram --spec-type ngram-mod
} | tee "$OUT"
echo "saved $OUT"
