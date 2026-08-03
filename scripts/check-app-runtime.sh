#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="${1:-$ROOT_DIR/dist/Workstate.app}"
SOURCE_DIST="$ROOT_DIR/AgentRuntime/dist"
BUNDLED_DIST="$APP_DIR/Contents/Resources/AgentRuntime/dist"
NODE_BIN="${WORKSTATE_NODE_PATH:-$(command -v node)}"

if [[ ! -x "$APP_DIR/Contents/MacOS/Workstate" ]]; then
  printf 'Bundled Workstate executable is missing: %s\n' "$APP_DIR" >&2
  exit 1
fi
if [[ ! -x "$NODE_BIN" ]]; then
  printf 'Node executable is missing: %s\n' "$NODE_BIN" >&2
  exit 1
fi

PRODUCTION_FILE_COUNT=0
for source_file in "$SOURCE_DIST"/*.js(N); do
  if [[ "${source_file:t}" == *.test.js ]]; then
    continue
  fi
  bundled_file="$BUNDLED_DIST/${source_file:t}"
  if [[ ! -f "$bundled_file" ]]; then
    printf 'Bundled AgentRuntime file is missing: %s\n' "${source_file:t}" >&2
    exit 1
  fi
  if ! cmp -s "$source_file" "$bundled_file"; then
    printf 'Bundled AgentRuntime file differs from build output: %s\n' "${source_file:t}" >&2
    exit 1
  fi
  ((PRODUCTION_FILE_COUNT += 1))
done
if (( PRODUCTION_FILE_COUNT == 0 )); then
  printf '%s\n' 'AgentRuntime has no production JavaScript files to verify.' >&2
  exit 1
fi

SMOKE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/workstate-runtime-smoke.XXXXXX")
trap 'rm -rf "$SMOKE_ROOT"' EXIT
SMOKE_OUTPUT=$(
  printf '%s' '{"mode":"reset_owner_session","projectId":"bundle-smoke"}' \
    | WORKSTATE_RUNTIME_ROOT="$SMOKE_ROOT" "$NODE_BIN" "$BUNDLED_DIST/index.js"
)
"$NODE_BIN" -e '
  const output = JSON.parse(process.argv[1]);
  if (output.mode !== "reset_owner_session"
      || output.result?.projectId !== "bundle-smoke"
      || output.usage !== null) {
    throw new Error("Bundled AgentRuntime smoke response is invalid");
  }
' "$SMOKE_OUTPUT"

printf 'Bundled AgentRuntime verified: %d production files\n' "$PRODUCTION_FILE_COUNT"
