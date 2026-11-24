#!/usr/bin/env bash
# Downloads the embeddable CPython for iOS from beeware/Python-Apple-support and
# extracts the device slice into build/python/{Python.framework,lib}.
#
# This step is optional: when it fails the app still builds, only the
# "import a .py bot" feature is unavailable. Requires the `gh` CLI (GH_TOKEN).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY_SERIES="${PY_SERIES:-3.13}"
OUT="$ROOT/build/python"
WORK="$ROOT/build/python-download"

if [ -d "$OUT/Python.framework" ] && [ -d "$OUT/lib" ]; then
  echo "Python runtime already present, skipping."
  exit 0
fi

fail() {
  echo "WARNING: $1" >&2
  echo "The IPA will be built without the Python runtime (Python bots disabled)." >&2
  rm -rf "$OUT" "$WORK"
  exit 0
}

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK"

tag="$(gh release list -R beeware/Python-Apple-support --limit 200 --json tagName --jq '.[].tagName' 2>/dev/null \
      | grep -E "^${PY_SERIES//./\\.}-b[0-9]+$" | sort -V | tail -n1)"
[ -n "$tag" ] || fail "no Python-Apple-support release found for Python $PY_SERIES"
echo "Using Python-Apple-support $tag"

gh release download "$tag" -R beeware/Python-Apple-support -p "Python-${PY_SERIES}-iOS-support*.tar.gz" -D "$WORK" \
  || fail "could not download the iOS support package"

archive="$(ls "$WORK"/*.tar.gz 2>/dev/null | head -n1)"
[ -n "$archive" ] || fail "downloaded archive not found"

mkdir -p "$WORK/extract"
tar -xzf "$archive" -C "$WORK/extract" || fail "could not extract $archive"

slice="$(find "$WORK/extract" -type d -path '*Python.xcframework/ios-arm64' | head -n1)"
[ -n "$slice" ] || fail "device slice (ios-arm64) not found in the xcframework"
[ -d "$slice/Python.framework" ] || fail "Python.framework missing in the device slice"
[ -d "$slice/lib" ] || fail "standard library missing in the device slice"

mkdir -p "$OUT"
cp -R "$slice/Python.framework" "$OUT/Python.framework"
cp -R "$slice/lib" "$OUT/lib"
rm -rf "$WORK"
echo "Python runtime ready in $OUT"
du -sh "$OUT"
