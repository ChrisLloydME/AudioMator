#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${ROOT_DIR}/.tmp/taglib_bridge_smoke"
BUILD_DIR="${ROOT_DIR}/.tmp/taglib-bridge-smoke-build"

mkdir -p "${BUILD_DIR}"

BRIDGE_ROOT_CANDIDATES=()
if [[ -n "${TAGLIB_BRIDGE_ROOT:-}" ]]; then
  BRIDGE_ROOT_CANDIDATES+=("${TAGLIB_BRIDGE_ROOT}")
fi
BRIDGE_ROOT_CANDIDATES+=(
  "${ROOT_DIR}/AudioMator/TagLibBridge"
  "${ROOT_DIR}/.deriveddata-codex/SourcePackages/checkouts/TagLibAudioMetadata/Sources/CTagLibBridge"
)

BRIDGE_ROOT=""
for candidate in "${BRIDGE_ROOT_CANDIDATES[@]}"; do
  if [[ -f "${candidate}/TagLibMetadataExtractor.mm" && -d "${candidate}/taglib/taglib" ]]; then
    BRIDGE_ROOT="${candidate}"
    break
  fi
done

if [[ -z "${BRIDGE_ROOT}" ]]; then
  cat >&2 <<EOF
Could not locate TagLib bridge sources.

Expected either:
  - AudioMator/TagLibBridge
  - .deriveddata-codex/SourcePackages/checkouts/TagLibAudioMetadata/Sources/CTagLibBridge

Run an Xcode package resolution/build first, or set TAGLIB_BRIDGE_ROOT to the CTagLibBridge source directory.
EOF
  exit 1
fi

TAGLIB_SOURCES=()
while IFS= read -r source_path; do
  TAGLIB_SOURCES+=("${source_path}")
done < <(find "${BRIDGE_ROOT}/taglib/taglib" -name '*.cpp' | sort)

INCLUDE_DIRS=(
  "${BRIDGE_ROOT}"
  "${BRIDGE_ROOT}/include"
  "${BRIDGE_ROOT}/taglib"
  "${BRIDGE_ROOT}/taglib/3rdparty/utfcpp/source"
)
while IFS= read -r include_dir; do
  INCLUDE_DIRS+=("${include_dir}")
done < <(find "${BRIDGE_ROOT}/taglib/taglib" -type d | sort)

COMMAND=(
  xcrun
  clang++
  -std=gnu++20
  -fobjc-arc
  -framework Foundation
  "${ROOT_DIR}/scripts/taglib_bridge_smoke.mm"
  "${BRIDGE_ROOT}/TagLibMetadataExtractor.mm"
)

for include_dir in "${INCLUDE_DIRS[@]}"; do
  COMMAND+=(-I "${include_dir}")
done

COMMAND+=("${TAGLIB_SOURCES[@]}")
COMMAND+=(
  -o "${OUTPUT_PATH}"
)

printf 'Building TagLib bridge smoke tool:\n'
printf '  %q' "${COMMAND[@]}"
printf '\n'

"${COMMAND[@]}"

echo "Built ${OUTPUT_PATH}"
