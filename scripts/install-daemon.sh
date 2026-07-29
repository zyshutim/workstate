#!/bin/zsh
set -euo pipefail

LABEL="com.timshu.workstate.daemon"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$UID"

launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
rm -f "$PLIST"

printf '%s\n' \
  'Removed the legacy Workstate LaunchAgent. Live monitoring now runs only while the Workstate app is open.'
