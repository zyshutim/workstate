#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
LABEL="com.timshu.workstate.daemon"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/Workstate"
INSTALL_DIR="$HOME/Library/Application Support/Workstate"
DAEMON="$INSTALL_DIR/bin/workstate-daemon"
RUNTIME_DIR="$INSTALL_DIR/AgentRuntime"
DOMAIN="gui/$UID"
START_AFTER_INSTALL=false

if [[ "${1:-}" == "--start" ]]; then
  START_AFTER_INSTALL=true
elif [[ $# -gt 0 ]]; then
  printf 'usage: %s [--start]\n' "$0" >&2
  exit 2
fi

launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true

if [[ ! -d "$ROOT_DIR/AgentRuntime/node_modules" ]]; then
  npm install --prefix "$ROOT_DIR/AgentRuntime"
fi
npm run build --prefix "$ROOT_DIR/AgentRuntime" >/dev/null
"$ROOT_DIR/scripts/build-app.sh" >/dev/null
mkdir -p "${PLIST:h}" "$LOG_DIR" "$INSTALL_DIR/bin" "$RUNTIME_DIR/dist" "$RUNTIME_DIR/node_modules/@openai"

cp "$ROOT_DIR/dist/bin/workstate-daemon" "$DAEMON"
cp "$ROOT_DIR/AgentRuntime/dist/index.js" "$RUNTIME_DIR/dist/index.js"
cp "$ROOT_DIR/AgentRuntime/package.json" "$RUNTIME_DIR/package.json"
rm -rf \
  "$RUNTIME_DIR/node_modules/@openai/codex" \
  "$RUNTIME_DIR/node_modules/@openai/codex-sdk" \
  "$RUNTIME_DIR/node_modules/@openai/codex-darwin-arm64"
ditto "$ROOT_DIR/AgentRuntime/node_modules/@openai/codex" "$RUNTIME_DIR/node_modules/@openai/codex"
ditto "$ROOT_DIR/AgentRuntime/node_modules/@openai/codex-sdk" "$RUNTIME_DIR/node_modules/@openai/codex-sdk"
cp -cR "$ROOT_DIR/AgentRuntime/node_modules/@openai/codex-darwin-arm64" "$RUNTIME_DIR/node_modules/@openai/codex-darwin-arm64"
chmod 755 "$DAEMON"
codesign --force --sign - "$DAEMON" >/dev/null

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$DAEMON</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>WORKSTATE_AGENT_RUNTIME</key>
    <string>$RUNTIME_DIR/dist/index.js</string>
  </dict>
  <key>RunAtLoad</key>
  <false/>
  <key>KeepAlive</key>
  <false/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/daemon.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/daemon-error.log</string>
</dict>
</plist>
PLIST

plutil -lint "$PLIST" >/dev/null
if [[ "$START_AFTER_INSTALL" == true ]]; then
  launchctl bootstrap "$DOMAIN" "$PLIST"
  launchctl kickstart -k "$DOMAIN/$LABEL"
fi
printf '%s\n' "$PLIST"
