#!/usr/bin/env bash
# Baut Clawd und verpackt es als "build/Clawd Desktop Pet.app".
#   ./build.sh           – für diesen Mac
#   ./build.sh install   – zusätzlich nach ~/Applications kopieren
#   ./build.sh release   – Universal-App (Apple Silicon + Intel) als Zip für einen GitHub-Release
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
NAME="Clawd Desktop Pet"
APP="build/$NAME.app"
BUNDLE_ID="io.github.tschlueter.clawd"

ARCHS=()
if [[ "$MODE" == "release" ]]; then
  # Ein Release entsteht nur aus einem sauberen, getaggten Stand: Der Tag muss zur Version in
  # Info.plist passen (1.2.0 → v1.2.0). Ablauf: Version erhöhen, committen, `git tag -a v1.2.0`.
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
  TAG="v$VERSION"
  if ! git diff --quiet HEAD -- || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    echo "Abbruch: Es gibt nicht committete Änderungen – ein Release muss genau dem Tag $TAG entsprechen." >&2
    exit 1
  fi
  if ! git tag --points-at HEAD | grep -qx "$TAG"; then
    echo "Abbruch: Der aktuelle Commit trägt nicht den Tag $TAG (Version $VERSION aus Info.plist)." >&2
    echo "         Erst die Version anpassen und committen, dann: git tag -a $TAG -m \"Clawd Desktop Pet $VERSION\"" >&2
    exit 1
  fi

  # Beide Architekturen in einem Binary. Die Warnung "x86_64 is deprecated" ist harmlos:
  # das Mindest-macOS bleibt 14 (siehe Package.swift).
  ARCHS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Clawd" "$APP/Contents/MacOS/Clawd"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" # erzeugt mit scripts/make-icon.swift

# Ad-hoc-Signatur mit fester Designated Requirement, damit die
# Bedienungshilfen-Freigabe Rebuilds möglichst überlebt.
codesign --force --sign - \
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP"

echo "Fertig: $APP ($(lipo -archs "$APP/Contents/MacOS/Clawd"))"

case "$MODE" in
  install)
    # nach ~/Applications kopieren (empfohlen für "Beim Anmelden starten")
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$NAME.app"
    cp -R "$APP" "$HOME/Applications/$NAME.app"
    echo "Installiert: $HOME/Applications/$NAME.app"
    ;;
  release)
    ZIP="build/Clawd-Desktop-Pet-$VERSION.zip"
    rm -f "$ZIP"
    # ditto erhält Signatur und Bundle-Struktur (anders als ein normales zip).
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    echo "Release-Paket: $ZIP ($(du -h "$ZIP" | cut -f1 | xargs))"
    shasum -a 256 "$ZIP"
    ;;
esac
