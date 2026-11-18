#!/bin/bash
# Start Session Deck at login (macOS launchd). Re-run after moving the folder.  Remove: bash scripts/install-agent.sh --remove
set -euo pipefail
LABEL=local.session-deck
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DIR=$(cd "$(dirname "$0")/.." && pwd)
if [ "${1:-}" = "--remove" ]; then launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true; rm -f "$PLIST"; echo "removed"; exit 0; fi
NODE=$(command -v node); [ -x /opt/homebrew/bin/node ] && NODE=/opt/homebrew/bin/node   # stable path survives brew upgrades
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$NODE</string><string>$DIR/server.js</string></array>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string><key>LANG</key><string>en_US.UTF-8</string></dict>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/session-deck.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/session-deck.log</string>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Session Deck starts at login: http://127.0.0.1:5199"
