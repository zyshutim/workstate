#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"

swift build -c release --product Workstate
swift build -c release --product WorkstateCLI
swift build -c release --product WorkstateDaemon

BIN_DIR=$(swift build -c release --show-bin-path)
APP_DIR="$ROOT_DIR/dist/Workstate.app"
CLI_DIR="$ROOT_DIR/dist/bin"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$CLI_DIR"

cp "$BIN_DIR/Workstate" "$APP_DIR/Contents/MacOS/Workstate"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BIN_DIR/WorkstateCLI" "$CLI_DIR/workstate"
cp "$BIN_DIR/WorkstateDaemon" "$CLI_DIR/workstate-daemon"
chmod 755 "$APP_DIR/Contents/MacOS/Workstate" "$CLI_DIR/workstate" "$CLI_DIR/workstate-daemon"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

printf '%s\n' "$APP_DIR"
