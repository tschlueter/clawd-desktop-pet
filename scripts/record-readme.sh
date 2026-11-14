#!/usr/bin/env bash
# Nimmt die GIFs für die README neu auf (docs/*.gif). Jede Szene läuft in einem eigenen,
# hellen und stummen Spielplatz-Fenster; danach beendet sich die App von selbst.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh >/dev/null
CLAWD="build/Clawd Desktop Pet.app/Contents/MacOS/Clawd"
mkdir -p docs

# Kopf: hineinfallen, winken, über beide Kästen hüpfen, winken
"$CLAWD" --record docs/hero.gif --record-from-start --record-seconds 7 --playground-size 600x260 \
  --script "0.3:wave,2.1:jump,3.6:jump,5.0:wave" >/dev/null

# Tagesablauf: Ausschnitt um das Mini-Dock (so gewählt, dass die Kästen nicht hineinragen)
scene() { local name=$1 seconds=$2; shift 2
  "$CLAWD" --record "docs/$name.gif" --record-seconds "$seconds" --playground-size 480x300 \
    --record-rect 165,16,220,134 "$@" >/dev/null; }
scene coffee 5.8 --force job:coffee
scene coding 6 --force coding
scene nap 7 --force yawn
# Präsentation zu zweit braucht mehr Platz: breiterer Spielplatz, Ausschnitt weiter rechts
"$CLAWD" --record docs/presentation.gif --record-seconds 8 --playground-size 700x300 \
  --record-rect 250,16,220,134 --encounter presentation >/dev/null
ls -la docs/*.gif
