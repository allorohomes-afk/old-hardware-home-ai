# Projects we stand on

Nothing here would work without other people's free and open-source work. This page lists **only what we actually
used** in this repo, what it did for us, and how you can support it. We don't get paid to list anything.

Licenses change, so always check each project's own license before you build on it.

## Running the models

| Project | What it did for us | License |
|---|---|---|
| [llama.cpp](https://github.com/ggml-org/llama.cpp) | Runs AI models on plain CPUs, including 2012-era machines and CPUs without AVX. Every number in [findings/01](findings/01-speeds-on-old-machines.md) came from it. | MIT |
| [Ollama](https://github.com/ollama/ollama) | The easiest way to get started; we used it on the newer comparison machines. | MIT |
| [Hugging Face](https://huggingface.co) | Hosts the model files we download (GGUF format). | (a service) |

## The models

| Model | Why we used it | License |
|---|---|---|
| [IBM Granite 4.0](https://huggingface.co/ibm-granite) (H-Tiny, H-1B) | Fastest small model on our old machines, and holds its speed in long chats. | Apache 2.0 |
| [Qwen3](https://huggingface.co/Qwen) (4B Instruct, 8B) | A strong small model for 8 GB machines. | Apache 2.0 |
| [Llama 3.2](https://huggingface.co/meta-llama) (3B) | Our baseline small model on every machine. | Llama 3.2 Community License (has conditions; not an OSI open-source license) |
| [Gemma](https://huggingface.co/google) (12B) | Tested on the newer laptop. | Gemma Terms of Use (has conditions) |

## The chat page

| Project | What it did for us | License |
|---|---|---|
| [Open WebUI](https://github.com/open-webui/open-webui) | Gives the whole family a chat page in the browser, from any phone or computer on the home network. | Open WebUI License (BSD-3 based, with a branding clause; read it if you redistribute) |

## The system underneath

| Project | What it did for us | License |
|---|---|---|
| [Ubuntu Server](https://ubuntu.com/server) | The operating system on every old machine, installed with no screen by our [kit](kits/headless-ubuntu-autoinstall/). | Free (mostly GPL) |
| [smartmontools](https://www.smartmontools.org) | Disk health checks before we trust an old drive. | GPL-2.0 |
| [lm-sensors](https://github.com/lm-sensors/lm-sensors) | Temperatures on old hardware. | GPL-2.0 / LGPL-2.1 |
| [ufw](https://launchpad.net/ufw) | A simple firewall: only SSH from the home network. | GPL-3.0 |
| [xorriso](https://www.gnu.org/software/xorriso/) | Builds the autoinstall USB image. | GPL-3.0 |

## How to give back (all free)

- **Star** the projects you use. It helps them get noticed and funded.
- **Report what works on your hardware.** Old and cheap machines are under-tested; your numbers help maintainers.
- **File good bug reports:** what you ran, on what machine, and what happened.
- **Help in their forums and issue trackers.** Answering a beginner's question is a contribution.
- If you can afford it, many of these projects accept donations through GitHub Sponsors or Open Collective.

Know a free project that helped you run AI at home on cheap hardware? [Open an issue](https://github.com/affordable-home-ai/old-hardware-home-ai/issues/new/choose) and tell us
what it did for you. We add projects once we've used them ourselves.
