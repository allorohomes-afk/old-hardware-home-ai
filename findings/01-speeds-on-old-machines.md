# 01. How fast is AI on old machines?

Measured late October to early November 2026. Same test script on every machine, temperature 0.

- **Writing speed**: tokens per second while the model writes its answer (a token is roughly ¾ of a word).
  Above ~5 tok/s feels usable for chat; above ~10 feels smooth.
- **Reading speed**: tokens per second while it reads your question (matters for long documents).
- **Quality**: ten easy questions with one right answer each. It catches broken setups, not fine differences.

## The old machines (CPU only, no graphics card)

| Machine | Model (Q4_K_M unless noted) | Writing tok/s | Reading tok/s | Peak RAM (GB) | Quality |
|---|---|---:|---:|---:|---:|
| 2012 desktop, Intel i3-3240, 16 GB DDR3 | IBM Granite 4.0 H-Tiny | **11.1** | 23.2 | 7.1 | 10/10 |
| 2012 desktop, Intel i3-3240, 16 GB DDR3 | Llama 3.2 3B Instruct | 6.4 | 12.6 | 2.7 | 10/10 |
| 2012 desktop, Intel i3-3240, 16 GB DDR3 | Llama 3.2 3B Instruct, Q4_0 | 5.5 | 7.2 | 3.2 | 9/10 |
| 2012 desktop, Intel i3-3240, 16 GB DDR3 | Llama 3.2 3B Instruct, Q8_0 | 5.4 | 8.1 | 4.7 | 10/10 |
| 2012 desktop, Intel i3-3240, 16 GB DDR3 | Bonsai 8B, Q1_0 | 2.5 | 2.8 | 2.0 | 9/10 |
| 2013 laptop, AMD A10-5750M, 8 GB DDR3L | Llama 3.2 3B Instruct | 2.5 | 6.8 | 2.7 | 10/10 |
| 2013 laptop, AMD A10-5750M, 8 GB DDR3L | Bonsai 8B, Q1_0 | 1.4 | 1.5 | 2.0 | 9/10 |
| 2013 laptop, AMD A10-5750M, 8 GB DDR3L | Qwen3 8B | 1.3 | — | — | — |

Runtime: llama.cpp `llama-server` build b11669, Ubuntu Server 24.04.

## Newer machines, for comparison

| Machine | Model (Q4_K_M) | Writing tok/s | Reading tok/s | Quality |
|---|---|---:|---:|---:|
| 2024 laptop, Intel Core Ultra 7 155H, 16 GB (CPU only, Windows, Ollama) | IBM Granite 4.0 H-Tiny | 30.2 | 119.7 | 10/10 |
| same | Llama 3.2 3B | 18.2 | 84.7 | 10/10 |
| same | Qwen3 4B Instruct | 14.4 | 61.7 | 10/10 |
| same | Gemma 4 12B | 7.6 | 19.0 | 10/10 |
| 2023 Mac mini M2, 8 GB (Ollama) | Llama 3.2 3B | 30.4 | 369.4 | 10/10 |
| same | IBM Granite 4.0 H-Tiny | 26.4 | 234.1 | 10/10 |
| same | Qwen3 4B Instruct | 23.4 | 275.0 | 9/10 |

## What we learned

1. **The model choice moved speed more than any setting did.** On the 2012 desktop, Granite 4.0 H-Tiny
   wrote 11.1 tok/s against 6.4 for Llama 3.2 3B, with the same quiz score. Granite is a "mixture of experts"
   model: about 7B in total but only about 1B active per word, so it's fast on weak CPUs. The cost is RAM:
   it peaked at about 7 GB, so it suits 16 GB machines, not 8 GB ones.
2. **Long chats slow everything down, but not equally.** On the 2024 laptop, at a 16,000-token conversation,
   Granite only dropped from 28.7 to 18 tok/s, while Llama 3.2 3B fell from 11.6 to 3.0 tok/s. If your family
   has long conversations, test at long lengths, not just the first answer.
3. **Smaller or bigger "quant" files didn't help on old CPUs.** Q4_0 and Q8_0 were both slower than Q4_K_M on
   the 2012 desktop. Stick with Q4_K_M.
4. **Squeezing the chat memory (`--cache-type-k q8_0`) made the 2013 AMD laptop slower**, not faster. Leave it
   at the default on old CPUs.
5. **1-bit models (Bonsai 8B, Q1_0) were not worth it here.** They use little RAM, but they were slower than a
   normal 3B model on both old machines.
6. **An 8B model on a 2013 laptop is too slow for chat** (1.3 tok/s). Use 3–4B models there, or give the laptop
   a background job (overnight summaries, file indexing) where speed doesn't matter.

## Rule of thumb

| Your RAM | Start with | Expect on a ~2012–2014 CPU |
|---|---|---|
| 8 GB | Llama 3.2 3B or Qwen3 4B Instruct (Q4_K_M) | 2–6 tok/s |
| 16 GB | IBM Granite 4.0 H-Tiny (Q4_K_M) | 6–11 tok/s |
| 32 GB+ | Try 8–14B models, but check the speed is still acceptable | depends heavily on the CPU |
