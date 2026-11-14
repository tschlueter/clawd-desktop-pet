#!/usr/bin/env bash
# Führt die Tests aus. Mit nur den Command Line Tools (ohne Xcode) findet SwiftPM das
# Makro-Plugin von Swift Testing nicht von selbst – dann wird der Pfad mitgegeben.
set -euo pipefail
cd "$(dirname "$0")"
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
