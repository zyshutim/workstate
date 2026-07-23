#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CLI_SOURCE="$ROOT_DIR/dist/bin/workstate"
CLI_TARGET_DIR="$HOME/.local/bin"
SKILL_SOURCE="$ROOT_DIR/Skills/workstate-handoff"
SKILL_TARGET="$HOME/.codex/skills/workstate-handoff"

if [[ ! -x "$CLI_SOURCE" ]]; then
    "$ROOT_DIR/scripts/build-app.sh" >/dev/null
fi

mkdir -p "$CLI_TARGET_DIR"
ln -sfn "$CLI_SOURCE" "$CLI_TARGET_DIR/workstate"
mkdir -p "${SKILL_TARGET:h}"
ln -sfn "$SKILL_SOURCE" "$SKILL_TARGET"
printf '%s\n' "$CLI_TARGET_DIR/workstate"
