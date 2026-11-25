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

# Optional third-party packages (iOS wheels, or pure-Python ones such as `chess`) go to
# site-packages, which the app puts on sys.path. Set PYTHON_PACKAGES="chess numpy".
# A failure only skips the packages; it never fails the build.
if [ -n "${PYTHON_PACKAGES:-}" ]; then
  pyver_dir="$(basename "$(find "$OUT/lib" -maxdepth 1 -type d -name 'python3*' | head -n1)")"
  pyver="${pyver_dir#python}"
  pytag="${pyver/./}"
  site="$OUT/lib/$pyver_dir/site-packages"
  wheels="$(mktemp -d)"
  mkdir -p "$site"
  echo "Downloading wheels: $PYTHON_PACKAGES (cp$pytag)"
  # shellcheck disable=SC2086
  if python3 -m pip download $PYTHON_PACKAGES -d "$wheels" \
      --platform ios_13_0_arm64_iphoneos --platform any --python-version "$pyver" \
      --implementation cp --abi "cp$pytag" --abi none --only-binary=:all: \
      --extra-index-url https://pypi.anaconda.org/beeware/simple >/dev/null 2>&1; then
    for w in "$wheels"/*.whl; do
      [ -f "$w" ] || continue
      echo "  + $(basename "$w")"
      unzip -q -o "$w" -d "$site"
    done
    find "$site" -type d \( -name tests -o -name test -o -name __pycache__ \) -prune -exec rm -rf {} + 2>/dev/null || true
  else
    echo "WARNING: could not download wheels for: $PYTHON_PACKAGES (continuing without them)" >&2
  fi
  rm -rf "$wheels"
fi

echo "Python runtime ready in $OUT"
du -sh "$OUT"
