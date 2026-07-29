#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"

if [[ ! -d "$ROOT_DIR/AgentRuntime/node_modules/@openai/codex" ]]; then
  npm install --prefix "$ROOT_DIR/AgentRuntime"
fi
npm run build --prefix "$ROOT_DIR/AgentRuntime" >/dev/null

swift build -c release --product Workstate
swift build -c release --product WorkstateCLI

BIN_DIR=$(swift build -c release --show-bin-path)
APP_DIR="$ROOT_DIR/dist/Workstate.app"
CLI_DIR="$ROOT_DIR/dist/bin"
RUNTIME_DIR="$APP_DIR/Contents/Resources/AgentRuntime"

rm -rf "$APP_DIR"
mkdir -p \
  "$APP_DIR/Contents/MacOS" \
  "$RUNTIME_DIR/dist" \
  "$RUNTIME_DIR/node_modules/@openai" \
  "$CLI_DIR"

cp "$BIN_DIR/Workstate" "$APP_DIR/Contents/MacOS/Workstate"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/AgentRuntime/dist/index.js" "$RUNTIME_DIR/dist/index.js"
cp "$ROOT_DIR/AgentRuntime/package.json" "$RUNTIME_DIR/package.json"
ditto \
  "$ROOT_DIR/AgentRuntime/node_modules/@openai/codex" \
  "$RUNTIME_DIR/node_modules/@openai/codex"
ditto \
  "$ROOT_DIR/AgentRuntime/node_modules/@openai/codex-darwin-arm64" \
  "$RUNTIME_DIR/node_modules/@openai/codex-darwin-arm64"
cp "$BIN_DIR/WorkstateCLI" "$CLI_DIR/workstate"
rm -f "$CLI_DIR/workstate-daemon"
chmod 755 "$APP_DIR/Contents/MacOS/Workstate" "$CLI_DIR/workstate"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

printf '%s\n' "$APP_DIR"
