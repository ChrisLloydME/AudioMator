#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${ROOT_DIR}/.tmp/taglib_bridge_smoke"
BUILD_DIR="${ROOT_DIR}/.tmp/taglib-bridge-smoke-build"

mkdir -p "${BUILD_DIR}"

TAGLIB_SOURCES=()
while IFS= read -r source_path; do
  TAGLIB_SOURCES+=("${source_path}")
done < <(find "${ROOT_DIR}/AudioMator/TagLibBridge/taglib/taglib" -name '*.cpp' | sort)

INCLUDE_DIRS=(
  "${ROOT_DIR}/AudioMator/TagLibBridge"
  "${ROOT_DIR}/AudioMator/TagLibBridge/taglib"
)
while IFS= read -r include_dir; do
  INCLUDE_DIRS+=("${include_dir}")
done < <(find "${ROOT_DIR}/AudioMator/TagLibBridge/taglib/taglib" -type d | sort)

COMMAND=(
  xcrun
  clang++
  -std=c++17
  -fobjc-arc
  -framework Foundation
  "${ROOT_DIR}/scripts/taglib_bridge_smoke.mm"
  "${ROOT_DIR}/AudioMator/TagLibBridge/TagLibMetadataExtractor.mm"
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
