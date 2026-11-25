#!/usr/bin/env bash
# Usage: package_ipa.sh <path/to/App.app> <output.ipa>
#
# Wraps the (unsigned) .app into an IPA. When build/python exists it also embeds
# the Python runtime: Python.framework plus the standard library, with every
# extension module (.so) moved into its own framework as CPython's iOS
# loader expects. Nothing is signed; re-sign the IPA with your own tool.
set -eEo pipefail
trap 'echo "package_ipa.sh failed at line $LINENO" >&2' ERR

APP="$1"
OUT="$2"
# The zip step runs after a cd into a temp dir, so OUT must be absolute.
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
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

  echo "Contents of python/lib:"
  ls -la "$BUNDLE/python/lib" || true

  VER_DIR=""
  for d in "$BUNDLE/python/lib"/python3*; do
    if [ -d "$d" ]; then VER_DIR="$(basename "$d")"; break; fi
  done
  if [ -z "$VER_DIR" ]; then
    echo "No python3.x folder found in the bundled standard library; skipping Python." >&2
    rm -rf "$BUNDLE/python" "$BUNDLE/Frameworks/Python.framework"
  else
  STDLIB="$BUNDLE/python/lib/$VER_DIR"
  echo "Python standard library: $VER_DIR"

  # Trim what a chess bot never needs.
  for d in test tests idlelib tkinter turtledemo ensurepip lib2to3 pydoc_data; do
    rm -rf "$STDLIB/$d"
  done
  find "$STDLIB" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

  # Move each extension module into a framework and leave a .fwork pointer.
  DYNLOAD="$STDLIB/lib-dynload"
  if [ -d "$DYNLOAD" ]; then
    while IFS= read -r so; do
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
    done < <(find "$DYNLOAD" -name '*.so')
  fi

  # Extension modules of third-party packages (site-packages) get the same treatment.
  # Their framework is named after the full dotted module path, e.g.
  # numpy/core/_x.cpython-313-iphoneos.so -> numpy.core._x.framework
  SITE="$STDLIB/site-packages"
  if [ -d "$SITE" ]; then
    while IFS= read -r so; do
      rel="${so#$SITE/}"
      stem="${rel%%.cpython-*}"
      [ "$stem" = "$rel" ] && stem="${rel%.so}"
      module="$(echo "$stem" | tr '/' '.')"
      fw="$BUNDLE/Frameworks/$module.framework"
      mkdir -p "$fw"
      id_suffix="$(echo "$module" | tr '_.' '--')"
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
      fwork="${so%.so}.fwork"
      mv "$so" "$fw/$module"
      echo "Frameworks/$module.framework/$module" > "$fwork"
      echo "python/lib/$VER_DIR/site-packages/${fwork#$SITE/}" > "$fw/$module.origin"
    done < <(find "$SITE" -name '*.so')
  fi
  fi
else
  echo "No Python runtime in build/python: building the IPA without it."
fi

rm -f "$OUT"
(cd "$WORK" && zip -qry "$OUT" Payload)
echo "Created $OUT"
ls -la "$OUT"
