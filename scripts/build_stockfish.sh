#!/usr/bin/env bash
# Builds Stockfish (plus our UCI bridge) as a static library for iOS arm64 and
# downloads the NNUE networks that this Stockfish version expects.
#
# Output:
#   build/lib/libstockfish.a
#   App/Resources/nets/nn-*.nnue
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SF_TAG="${SF_TAG:-sf_17.1}"
BUILD="$ROOT/build"
SRC="$BUILD/stockfish"
OBJ="$BUILD/obj"
LIB="$BUILD/lib/libstockfish.a"
NETS="$ROOT/App/Resources/nets"

mkdir -p "$BUILD/lib" "$OBJ" "$NETS"

net_count() { find "$NETS" -name 'nn-*.nnue' | wc -l | tr -d ' '; }

if [ -f "$LIB" ] && [ "$(net_count)" -ge 2 ]; then
  echo "Stockfish library and networks already present, skipping."
  exit 0
fi

# ---- Source ---------------------------------------------------------------
if [ ! -d "$SRC/src" ]; then
  echo "Cloning Stockfish $SF_TAG"
  git clone --depth 1 --branch "$SF_TAG" https://github.com/official-stockfish/Stockfish.git "$SRC"
fi

# ---- Networks -------------------------------------------------------------
for kind in Big Small; do
  name="$(grep -rhoE "EvalFileDefaultName${kind}[[:space:]]+\"nn-[0-9a-f]+\.nnue\"" "$SRC/src" \
          | grep -oE 'nn-[0-9a-f]+\.nnue' | head -n1 || true)"
  if [ -z "$name" ]; then
    echo "Could not find the default $kind network name in the Stockfish sources" >&2
    exit 1
  fi
  if [ ! -f "$NETS/$name" ]; then
    echo "Downloading $name"
    curl -fL --retry 4 --retry-delay 3 -o "$NETS/$name" "https://data.stockfishchess.org/nn/$name"
  fi
  want="${name#nn-}"; want="${want%.nnue}"
  got="$(shasum -a 256 "$NETS/$name" | cut -c1-12)"
  if [ "$want" != "$got" ]; then
    echo "Checksum mismatch for $name (expected prefix $want, got $got)" >&2
    rm -f "$NETS/$name"
    exit 1
  fi
done

# ---- Compile --------------------------------------------------------------
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CXX="$(xcrun --sdk iphoneos -f clang++)"
AR="$(xcrun --sdk iphoneos -f ar)"

FLAGS=(
  -arch arm64
  -isysroot "$SDK"
  -miphoneos-version-min=15.0
  -std=c++17
  -O3
  -DNDEBUG
  -DIS_64BIT
  -DUSE_POPCNT
  -DUSE_NEON=8
  -DNNUE_EMBEDDING_OFF
)

rm -f "$OBJ"/*.o
JOBS="$(sysctl -n hw.ncpu)"
pids=()
names=()

compile() {
  local file="$1" out="$2"
  shift 2
  "$CXX" "${FLAGS[@]}" "$@" -c "$file" -o "$out"
}

wait_oldest() {
  local pid="${pids[0]}" name="${names[0]}"
  pids=("${pids[@]:1}")
  names=("${names[@]:1}")
  if ! wait "$pid"; then
    echo "Compilation failed: $name" >&2
    exit 1
  fi
}

while IFS= read -r f; do
  rel="${f#"$SRC/src/"}"
  out="$OBJ/$(echo "$rel" | tr '/' '_').o"
  extra=()
  if [ "$rel" = "main.cpp" ]; then extra=(-Dmain=stockfish_main); fi
  compile "$f" "$out" ${extra[@]+"${extra[@]}"} &
  pids+=("$!")
  names+=("$rel")
  while [ "${#pids[@]}" -ge "$JOBS" ]; do wait_oldest; done
done < <(find "$SRC/src" -name '*.cpp' | sort)

# Our bridge (only uses the standard library).
compile "$ROOT/bridge/stockfish_bridge.cpp" "$OBJ/bridge.o" -I"$ROOT/bridge" &
pids+=("$!")
names+=("bridge/stockfish_bridge.cpp")

while [ "${#pids[@]}" -gt 0 ]; do wait_oldest; done

rm -f "$LIB"
"$AR" rcs "$LIB" "$OBJ"/*.o
echo "Built $LIB"
ls -la "$LIB" "$NETS"
