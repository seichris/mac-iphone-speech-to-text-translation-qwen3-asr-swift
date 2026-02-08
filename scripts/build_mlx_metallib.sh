#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build_mlx_metallib.sh [debug|release]

Builds MLX's Metal shader library (mlx.metallib) and places it next to the
SwiftPM-built executable output (e.g. .build/release/mlx.metallib).

If you see: "missing Metal Toolchain", run:
  xcodebuild -downloadComponent MetalToolchain
EOF
}

resolve_tool() {
  local name="$1"
  local metal_bin=""
  local dir=""

  if path="$(xcrun -sdk macosx -find "$name" 2>/dev/null)"; then
    echo "$path"
    return 0
  fi

  # On some systems, xcrun finds `metal` via the MetalToolchain but fails to
  # locate `metallib`. Fall back to the toolchain bin dir next to `metal`.
  if [[ "$name" == "metallib" ]]; then
    metal_bin="$(xcrun -sdk macosx -find metal 2>/dev/null || true)"
    if [[ -n "$metal_bin" ]]; then
      dir="$(dirname "$metal_bin")"
      if [[ -x "$dir/metallib" ]]; then
        echo "$dir/metallib"
        return 0
      fi
    fi
  fi

  return 1
}

CONFIG="${1:-release}"
if [[ "$CONFIG" != "release" && "$CONFIG" != "debug" ]]; then
  usage
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build"

if [[ ! -d "$BUILD_DIR" ]]; then
  echo "error: $BUILD_DIR not found (run swift build first)" >&2
  exit 1
fi

OUT_DIR="$BUILD_DIR/$CONFIG"
if [[ ! -d "$OUT_DIR" ]]; then
  # Fallback for non-symlink layouts
  OUT_DIR="$(find "$BUILD_DIR" -maxdepth 3 -type d -path "*/$CONFIG" | head -n 1 || true)"
fi
if [[ -z "${OUT_DIR:-}" || ! -d "$OUT_DIR" ]]; then
  echo "error: failed to locate SwiftPM output dir for config=$CONFIG under $BUILD_DIR" >&2
  exit 1
fi

MLX_SWIFT_DIR="$BUILD_DIR/checkouts/mlx-swift"
MLX_DIR="$MLX_SWIFT_DIR/Source/Cmlx/mlx"
KERNELS_DIR="$MLX_SWIFT_DIR/Source/Cmlx/mlx/mlx/backend/metal/kernels"

if [[ ! -d "$KERNELS_DIR" ]]; then
  echo "error: MLX kernels dir not found at $KERNELS_DIR" >&2
  echo "hint: ensure dependencies are fetched (swift build) and mlx-swift checkout exists" >&2
  exit 1
fi
if [[ ! -d "$MLX_DIR/mlx" ]]; then
  echo "error: MLX include root not found at $MLX_DIR/mlx" >&2
  exit 1
fi

METAL_SRCS=()
while IFS= read -r line; do
  METAL_SRCS+=("$line")
done < <(find "$KERNELS_DIR" -type f -name '*.metal' | LC_ALL=C sort)
if [[ "${#METAL_SRCS[@]}" -eq 0 ]]; then
  echo "error: no .metal sources found under $KERNELS_DIR" >&2
  exit 1
fi

TMPDIR_ROOT="${TMPDIR:-/tmp}"
TMP="$(mktemp -d "$TMPDIR_ROOT/mlx-metallib.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

AIR_FILES=()
METAL_FLAGS=(
  -x metal
  -Wall
  -Wextra
  -fno-fast-math
  -Wno-c++17-extensions
  -Wno-c++20-extensions
)

METAL_BIN="$(resolve_tool metal || true)"
METALLIB_BIN="$(resolve_tool metallib || true)"
if [[ -z "$METAL_BIN" ]]; then
  echo "error: unable to locate the Metal compiler (metal)" >&2
  echo "run: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi
if [[ -z "$METALLIB_BIN" ]]; then
  echo "error: unable to locate metallib" >&2
  echo "run: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

echo "Compiling ${#METAL_SRCS[@]} Metal sources..."
for SRC in "${METAL_SRCS[@]}"; do
  REL="${SRC#"$KERNELS_DIR/"}"
  KEY="$(printf '%s' "$REL" | shasum -a 256 | awk '{print $1}' | cut -c1-16)"
  OUT_AIR="$TMP/$KEY.air"

  if ! "$METAL_BIN" "${METAL_FLAGS[@]}" -c "$SRC" -I"$MLX_DIR" -I"$KERNELS_DIR" -o "$OUT_AIR" 2>"$TMP/metal.err"; then
    if grep -q "missing Metal Toolchain" "$TMP/metal.err" 2>/dev/null; then
      echo "error: Xcode Metal Toolchain is missing." >&2
      echo "run: xcodebuild -downloadComponent MetalToolchain" >&2
    fi
    cat "$TMP/metal.err" >&2
    exit 1
  fi
  AIR_FILES+=("$OUT_AIR")
done

OUT_METALLIB="$OUT_DIR/mlx.metallib"
echo "Linking mlx.metallib -> $OUT_METALLIB"
"$METALLIB_BIN" "${AIR_FILES[@]}" -o "$OUT_METALLIB"

echo "OK: wrote $OUT_METALLIB"
