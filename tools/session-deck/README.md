# Session Deck

One window for every Claude Code session on your Mac, built for small screens with many sessions open.
Local only (127.0.0.1), free and open source.


- **Left:** every open Claude Code session, newest first (amber = busy, green = idle).
  LIVE = running inside the deck (tmux), TAB = open in a Terminal tab (read-only transcript here),
  BRIDGED = Remote Control is on, SENT = sent to the Claude app. ⌘1–9 jumps to a session, ⌘B hides the list.
- **Right:** the live session in a real terminal, or the transcript of a Terminal-tab session.
- **Session ⋯:** Move into deck (an idle Terminal-tab session reopens live in the deck, same conversation),
  Save to log (local Ollama summary → a daily run log in your notes vault), Send to Claude, End session (offers to save first;
  closes only if the save worked).
- **Top-right ⋯:** Save all sessions to the Hive (copies every transcript, plus readable Markdown copies, to a home
  server over SSH). Deck-wide options are added in `DECK_ACTIONS` in `public/index.html`.
- **⧉ Pop out:** the session in its own Terminal window.
- **Claude app bridge:** `mcp.js` is a read-only MCP server for the Claude desktop app (`list_sessions`,
  `read_session`, `search_sessions`, `shared_sessions`). Press **Connect** in the deck, then **Restart Claude**.

## Install

Needs macOS, Node 20+, tmux (`brew install tmux`) and Claude Code. Optional: Ollama for log summaries, a Markdown notes vault
with a Local REST API plugin for the log, an SSH-reachable home server for the Hive copy.

```
npm install
npm start                       # http://127.0.0.1:5199
bash scripts/install-agent.sh   # optional: start at login
```

In Safari: **File → Add to Dock** turns it into an app with its own icon.

## Settings

Copy `config.example.json` to `~/.config/session-deck/config.json` and edit it. Your names, server address and
vault details stay in that file, outside the code. Without it the deck still runs; the log and Hive features just say
they aren't set up. The notes vault's API token is read from the macOS Keychain (`keychainService` / `keychainAccount`).

## Safety

The terminal can run anything Claude Code can, so the deck listens on 127.0.0.1 only and checks a per-launch token
plus the Host and Origin headers on every request. The MCP bridge can read sessions but never type into them.
New background sessions only start in folders you have trusted in Claude Code.
