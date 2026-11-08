# 01. How fast is AI on old machines?

Measured 2–3 November 2026 with [`bench/bench.py`](../bench/). **Every raw result file is in
[`bench/results/`](../bench/results/)**, so you can check any number here.

## How we tested

- **Settings:** temperature 0, fixed seed, 4,096-token context, runtime's default thread count.
- **Writing speed:** tokens per second while writing 128 tokens (a token is roughly ¾ of a word). **Median of
  3 runs**; on the old machines the 3 runs never differed by more than 3%. Above ~5 tok/s feels usable for chat;
  above ~10 feels smooth.
- **Reading speed:** tokens per second while reading a prompt of roughly 1,200–1,500 tokens.
- **Sanity check (not a quality score):** ten easy questions with one right answer each. It only catches a
  broken setup (wrong template, runaway "thinking"). It says nothing about how good a model's answers are.
- **One machine of each kind.** These are our machines, not a survey. Your numbers will differ.

## The old machines (CPU only, no graphics card)

Runtime: llama.cpp `llama-server` build b11669, Ubuntu Server 24.04. All models Q4_K_M unless noted.

| Machine | Model | Writing tok/s | Reading tok/s | Peak RAM (GB) | Sanity check | Conditions |
|---|---|---:|---:|---:|---:|---|
| 2012 desktop, Intel i3-3240, 16 GB DDR3 | IBM Granite 4.0 H-Tiny | **11.1** | 23.2 | 7.1 | 10/10 | B |
| same | Llama 3.2 3B Instruct | 6.4 | 12.6 | 2.7 | 10/10 | A |
| same | Llama 3.2 3B Instruct, Q4_0 | 5.5 | 7.2 | 3.2 | 9/10 | B |
| same | Llama 3.2 3B Instruct, Q8_0 | 5.4 | 8.1 | 4.7 | 10/10 | B |
| same | Bonsai 8B, Q1_0 | 2.5 | 2.8 | 2.0 | 9/10 | A |
| 2013 laptop, AMD A10-5750M, 8 GB DDR3L | Llama 3.2 3B Instruct | 2.5 | 6.8 | 2.7 | 10/10 | C |
| same | Bonsai 8B, Q1_0 | 1.4 | 1.5 | 2.0 | 9/10 | C |

**Conditions:**
- **A** (2 Nov): run at the lowest CPU priority, with a chat web app and a second AI server sitting idle in the background.
- **B** (3 Nov): a separate session ("round 2"), without the lowest-priority setting.
- **C** (2 Nov): a small idle network service in the background; plugged in, lid closed.

**Read across the A and B rows with care.** They weren't run back to back under identical conditions, and
we're rerunning them that way.

## Newer machines, for comparison

These use Ollama, a different runtime, so compare models **within** a machine, not across machines.

| Machine | Model (Q4_K_M) | Writing tok/s | Reading tok/s |
|---|---|---:|---:|
| 2024 laptop, Intel Core Ultra 7 155H, 16 GB (CPU only, Windows) | IBM Granite 4.0 H-Tiny | 30.2 | 119.7 |
| same | Llama 3.2 3B | 18.2 | 84.7 |
| same | Qwen3 4B Instruct | 14.4 | 61.7 |
| same | Gemma 4 12B | 7.6 | 19.0 |
| 2023 Mac mini M2, 8 GB (Apple GPU) | Llama 3.2 3B | 30.4 | 369.4 |
| same | IBM Granite 4.0 H-Tiny | 26.4 | 234.1 |
| same | Qwen3 4B Instruct | 23.4 | 275.0 |

## Long chats: speed as the conversation grows

The model reads a long conversation, then answers. The table shows writing speed (tok/s) at each length.

| Machine | Model | 2k | 8k | 16k | 32k |
|---|---|---:|---:|---:|---:|
| 2012 desktop (llama.cpp) | IBM Granite 4.0 H-Tiny | 10.0 | 7.6 | 5.8 | 3.9 |
| 2013 laptop (llama.cpp) | Llama 3.2 3B | 1.34 | 0.59 | — | — |
| 2024 laptop (Ollama) | IBM Granite 4.0 H-Tiny | 28.7 | 24.9 | 18.0 | 17.7 |
| 2024 laptop (Ollama) | Llama 3.2 3B | 11.6 | 6.0 | 3.0 | 3.0 |

"—" means not run: at that length the 2013 laptop would have needed hours just to read. The same test of
Llama 3.2 3B on the 2012 desktop failed with a server error, so it isn't in the table.

## What we learned

1. **Model choice mattered more than any setting we tried.** On the 2012 desktop, Granite 4.0 H-Tiny wrote
   11.1 tok/s against 6.4 for Llama 3.2 3B. Part of that gap may be the different test conditions (A vs B
   above), so treat "about 1.7×" as provisional until the back-to-back rerun. On the 2024 laptop, where both ran
   under the same conditions, Granite was 1.66× faster.

   Why it's fast: Granite 4.0 H-Tiny is about 7B in total, but only about 1B is active per token (a "mixture of
   experts"). The cost is RAM: it peaked at about 7 GB, so it suits 16 GB machines, not 8 GB ones.
2. **Granite holds its speed in long chats much better than Llama 3.2 3B.** On the 2024 laptop, at 16k tokens,
   Granite kept 63% of its speed and Llama kept 26%. That comes mainly from Granite's **hybrid design**: most of
   its layers are Mamba-2 layers, whose memory doesn't grow with the conversation the way a standard
   transformer's does. On the slow 2012 desktop Granite still slowed down (10.0 → 3.9 tok/s at 32k), but it stayed
   usable where Llama didn't run at all. **If your family has long conversations, test at long lengths, not
   just the first answer.**
3. **The other file formats (Q4_0, Q8_0) didn't help on the 2012 desktop. TENTATIVE.** Q8_0 being slower is
   expected: it's a bigger file to push through memory. Q4_0 being slower than Q4_K_M is unusual, and its slow
   reading speed (7.2 vs 12.6) is suspicious. These ran in a different session (B) from the Q4_K_M row (A), so
   we don't trust this result yet. For now, Q4_K_M is a safe default.
4. **Squeezing the chat memory made the 2013 AMD laptop slower overall.** We used flash attention plus an 8-bit
   KV cache (`-fa on -ctk q8_0 -ctv q8_0`). On Llama 3.2 3B, reading speed fell from 6.41 to 4.14 tok/s at 2k
   and from 4.45 to 1.25 tok/s at 8k. Writing barely changed (1.34 → 1.48 at 2k, 0.59 → 0.53 at 8k). The 8k
   test took 1 h 51 min instead of 32 min. On a 2026 Mac the result was mixed: it helped one model at 8k and hurt
   another at 32k. Leave them at the defaults on old CPUs unless you're short of RAM, and measure if you change them.
5. **Bonsai 8B (a 1-bit model) wasn't worth it on these two old machines.** It uses little RAM, but it was slower
   than Llama 3.2 3B on both. That's one model at one stage of 1-bit support in llama.cpp; other 1-bit models, or
   later builds, may do better.
6. **An 8B model on a 2013 laptop is too slow for chat:** Qwen3 8B wrote 1.3 tok/s there, in a separate test
   ([findings/04](04-speculative-decoding.md)). Use 3–4B models on machines like that, or give them background
   jobs where speed doesn't matter.

## Rule of thumb (from our machines only)

| Your RAM | Start with | What we saw on 2012–2013 CPUs |
|---|---|---|
| 8 GB | Llama 3.2 3B or Qwen3 4B Instruct (Q4_K_M) | Llama 3.2 3B: 2.5 tok/s on the 2013 AMD laptop; 6.4 tok/s on the 2012 Intel desktop (which has 16 GB, but the model only needs ~3) |
| 16 GB | IBM Granite 4.0 H-Tiny (Q4_K_M) | 11.1 tok/s (2012 Intel desktop) |
| 32 GB+ | Try 8–14B models, then check the speed is still acceptable | not tested on old hardware yet |
