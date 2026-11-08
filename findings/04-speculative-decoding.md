# 04. Speculative decoding on a slow CPU

**Status: incomplete. Our first run did not measure what we meant it to. A clean rerun is pending.**

## The idea

A small "helper" model guesses the next few words, and the big model checks the guesses in one go. On fast
machines whose bottleneck is memory, this can double the speed. The question was whether it helps on an old CPU
whose bottleneck is raw computing power.

## What we ran

- 2013 laptop, AMD A10-5750M, 8 GB, llama.cpp build b11669.
- Big model: Qwen3 8B (Q4_K_M). Helper: Qwen3 0.6B (Q4_K_M).
- Rounds: the big model alone; with the helper guessing 4 words; guessing 8 words; and "n-gram" guessing (no
  helper, it reuses patterns from the text so far).

| Round | Writing tok/s | Clock | Max CPU temp |
|---|---:|---:|---:|
| Big model alone | 1.32 | 2,489 MHz | 82 °C |
| + helper, 4 guesses | 1.32–1.33 | 2,488 MHz | 84 °C |
| + helper, 8 guesses | 1.32–1.33 | 2,489 MHz | 84 °C |
| n-gram guesses | 1.32 | 2,489 MHz | 85 °C |

## Why we don't trust this yet

Every round came out the same, and the server reported **no guesses at all**. In llama.cpp b11669, loading a
helper model with `-md` is not enough: speculation stays off unless you also pass `--spec-type draft-simple`.
(The older `--draft-max` flag was removed; it's now `--spec-draft-n-max`.) Our first run missed that, so the
helper rounds were really "big model alone" three times.

`tools/spec-test.sh` has the corrected flags and prints how many guesses were accepted, so a rerun will show
whether speculation was really on.

## What we expect

On a CPU this slow, checking the guesses costs nearly as much as writing the words, so we expect little or no
gain, possibly a loss. But that's a prediction, not a measurement, and we'll replace it with real numbers.

## Takeaway for now

If you try this yourself: **check that the server reports accepted guesses** (`draft_n_accepted` in the
`/completion` timings). If it doesn't, speculation isn't running, whatever your flags say.
