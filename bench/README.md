# The benchmark

This is the exact script behind the tables in [findings/01](../findings/01-speeds-on-old-machines.md), with every raw result
file in `results/` (speed tests) and `results/context/` (long-chat tests). Check our numbers, or run it on your own machine.

One script, same tests, any machine. It measures what a local language model can do on the hardware you
actually own, from a 2013 laptop to a current Mac.

For each machine and model it records:

- **Load time:** seconds from cold to ready.
- **Writing speed:** tokens per second while answering (median of several runs).
- **Reading speed:** tokens per second while taking in a prompt of roughly 1,200–1,500 tokens (it depends on the model's tokenizer).
- **Peak memory** the runtime held.
- **Quality:** ten easy questions with one right answer each (arithmetic, ordering, a time sum, a trick
  question). It's a sanity check, not a leaderboard.

## Run it

Python 3.8+ with nothing to install. Works on Linux, Windows and macOS.

```sh
# Ollama
python3 bench.py --label envy-m6 --machine "HP Envy m6 laptop (2013)" --model llama3.2:3b

# llama.cpp's llama-server or a fork of it (e.g. PrismML's for Bonsai); the script starts it to time the load
python3 bench.py --label envy-m6 --machine "HP Envy m6 laptop (2013)" --backend llama-server \
  --model bonsai-8b --url http://127.0.0.1:8099 \
  --launch "./llama-server -m Bonsai-8B.gguf -c 4096 --port 8099 --host 127.0.0.1"

python3 report.py   # results/*.json -> RESULTS.md
```

Old machines are slow, so each request may take up to 30 minutes by default (`--timeout`). Use
`--repeats 1` for a quick pass and `--notes` for anything that matters, such as "on battery".

## Fair comparisons

- Temperature 0, fixed seed, 4,096-token context, 128 tokens written per writing test.
- Each run starts its prompt differently, so a runtime can't reuse earlier work.
- The runtime and its version are recorded because they matter: the same model file read prompts
  2.7x faster in llama-server than in Ollama on the same Mac.
- On Apple Silicon, memory the GPU uses may not show as process memory; Ollama's own figure is used
  when available.

## Privacy

Results hold hardware, software versions and numbers only: no hostname, user name, IP address, server
address or file path. Check `results/` before publishing anyway.
