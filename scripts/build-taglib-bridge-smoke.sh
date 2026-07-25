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
  if [[ -f "${candidate}/TagLibMetadataExtractor.mm" ]]; then
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

TAGLIB_SOURCE_ROOT=""
TAGLIB_SOURCE_ROOT_CANDIDATES=(
  "${BRIDGE_ROOT}/taglib"
  "${BRIDGE_ROOT}/../../ThirdParty/TagLib"
)
for candidate in "${TAGLIB_SOURCE_ROOT_CANDIDATES[@]}"; do
  if [[ -d "${candidate}/taglib" ]]; then
    TAGLIB_SOURCE_ROOT="${candidate}"
    break
  fi
done

TAGLIB_FRAMEWORK=""
TAGLIB_FRAMEWORK_CANDIDATES=(
  "${ROOT_DIR}/.deriveddata-codex/SourcePackages/artifacts/taglibaudiometadata/TagLib/TagLib.xcframework/macos-arm64_x86_64/TagLib.framework"
  "${ROOT_DIR}/.deriveddata-codex/Build/Products/Debug/TagLib.framework"
)
for candidate in "${TAGLIB_FRAMEWORK_CANDIDATES[@]}"; do
  if [[ -d "${candidate}" ]]; then
    TAGLIB_FRAMEWORK="${candidate}"
    break
  fi
done

if [[ -z "${TAGLIB_SOURCE_ROOT}" && -z "${TAGLIB_FRAMEWORK}" ]]; then
  cat >&2 <<EOF
Could not locate TagLib sources or a built macOS framework for the bridge smoke tool.

Expected either:
  - ${BRIDGE_ROOT}/taglib/taglib
  - the package checkout's ThirdParty/TagLib/taglib directory
  - .deriveddata-codex SourcePackages artifacts or Debug/TagLib.framework
EOF
  exit 1
fi

TAGLIB_SOURCES=()
INCLUDE_DIRS=(
  "${BRIDGE_ROOT}"
  "${BRIDGE_ROOT}/include"
)
LINK_ARGS=()

if [[ -n "${TAGLIB_SOURCE_ROOT}" ]]; then
  while IFS= read -r source_path; do
    TAGLIB_SOURCES+=("${source_path}")
  done < <(find "${TAGLIB_SOURCE_ROOT}/taglib" -name '*.cpp' | sort)

  INCLUDE_DIRS+=(
    "${TAGLIB_SOURCE_ROOT}"
    "${TAGLIB_SOURCE_ROOT}/3rdparty/utfcpp/source"
  )
  while IFS= read -r include_dir; do
    INCLUDE_DIRS+=("${include_dir}")
  done < <(find "${TAGLIB_SOURCE_ROOT}/taglib" -type d | sort)
else
  TAGLIB_FRAMEWORK_SEARCH_PATH="${TAGLIB_FRAMEWORK%/TagLib.framework}"
  LINK_ARGS+=(
    -F "${TAGLIB_FRAMEWORK_SEARCH_PATH}"
    -framework TagLib
    -Wl,-rpath,"${TAGLIB_FRAMEWORK_SEARCH_PATH}"
  )
fi

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

if [[ -n "${TAGLIB_SOURCE_ROOT}" ]]; then
  COMMAND+=("${TAGLIB_SOURCES[@]}")
else
  COMMAND+=("${LINK_ARGS[@]}")
fi
COMMAND+=(
  -o "${OUTPUT_PATH}"
)

printf 'Building TagLib bridge smoke tool:\n'
printf '  %q' "${COMMAND[@]}"
printf '\n'

"${COMMAND[@]}"

echo "Built ${OUTPUT_PATH}"
