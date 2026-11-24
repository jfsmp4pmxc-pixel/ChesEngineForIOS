#!/usr/bin/env bash
# Usage: package_ipa.sh <path/to/App.app> <output.ipa>
#
# Wraps the (unsigned) .app into an IPA. When build/python exists it also embeds
# the Python runtime: Python.framework plus the standard library, with every
# extension module (.so) moved into its own framework as CPython's iOS
# loader expects. Nothing is signed; re-sign the IPA with your own tool.
set -euo pipefail

APP="$1"
OUT="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="$ROOT/build/python"

[ -d "$APP" ] || { echo "App bundle not found: $APP" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
BUNDLE="$WORK/Payload/$(basename "$APP")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUNDLE/Info.plist")"

if [ -d "$PY/Python.framework" ] && [ -d "$PY/lib" ]; then
  echo "Embedding Python runtime"
  mkdir -p "$BUNDLE/Frameworks" "$BUNDLE/python"
  cp -R "$PY/Python.framework" "$BUNDLE/Frameworks/Python.framework"
  cp -R "$PY/lib" "$BUNDLE/python/lib"

  VER_DIR="$(ls -1 "$BUNDLE/python/lib" | grep '^python3' | head -n1)"
  STDLIB="$BUNDLE/python/lib/$VER_DIR"

  # Trim what a chess bot never needs.
  for d in test tests idlelib tkinter turtledemo ensurepip lib2to3 pydoc_data; do
    rm -rf "$STDLIB/$d"
  done
  find "$STDLIB" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

  # Move each extension module into a framework and leave a .fwork pointer.
  DYNLOAD="$STDLIB/lib-dynload"
  if [ -d "$DYNLOAD" ]; then
    find "$DYNLOAD" -name '*.so' | while IFS= read -r so; do
      file="$(basename "$so")"
      module="${file%%.*}"
      fw="$BUNDLE/Frameworks/$module.framework"
      mkdir -p "$fw"
      id_suffix="$(echo "$module" | tr '_' '-')"
      cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$module</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID.$id_suffix</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$module</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>15.0</string>
</dict>
</plist>
PLIST
      mv "$so" "$fw/$module"
      echo "Frameworks/$module.framework/$module" > "${so%.so}.fwork"
      echo "python/lib/$VER_DIR/lib-dynload/${file%.so}.fwork" > "$fw/$module.origin"
    done
  fi
else
  echo "No Python runtime in build/python: building the IPA without it."
fi

rm -f "$OUT"
(cd "$WORK" && zip -qry "$OUT" Payload)
echo "Created $OUT"
ls -la "$OUT"
