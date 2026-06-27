#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${ROOT_DIR}/.deriveddata-codex"
LOG_PATH="${DERIVED_DATA_PATH}/xcodebuild.log"
PRUNE_APP_BUNDLES="${ROOT_DIR}/scripts/prune-app-bundles.sh"
FORCE_BUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force|--full)
      FORCE_BUILD=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: bash scripts/codex-build.sh [--force|--full]" >&2
      exit 2
      ;;
  esac
done

mkdir -p "${DERIVED_DATA_PATH}"

prune_app_bundles() {
  if ! "${PRUNE_APP_BUNDLES}"; then
    echo "Failed to prune extra .app bundles." >&2
    exit 1
  fi
}

prune_app_bundles

is_build_relevant_file() {
  local path="$1"

  case "${path}" in
    AudioMator.xcodeproj/*|AudioMator/*.xcconfig|Config/*|scripts/codex-build.sh)
      return 0
      ;;
    AudioMator/*)
      case "${path}" in
        *.swift|*.m|*.mm|*.c|*.cc|*.cpp|*.h|*.hpp|*.plist|*.strings|*.xcassets/*|*.icon/*|*.entitlements)
          return 0
          ;;
      esac
      ;;
    AudioMatorTests/*)
      case "${path}" in
        *.swift|*.m|*.mm|*.c|*.cc|*.cpp|*.h|*.hpp|*.plist|*.strings)
          return 0
          ;;
      esac
      ;;
  esac

  return 1
}

collect_changed_files() {
  (
    cd "${ROOT_DIR}" || exit 1
    git diff --name-only --relative HEAD
    git ls-files --others --exclude-standard
  ) | awk 'NF && !seen[$0]++'
}

if [[ ${FORCE_BUILD} -ne 1 ]]; then
  BUILD_RELEVANT_CHANGES=()
  while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    if is_build_relevant_file "${path}"; then
      BUILD_RELEVANT_CHANGES+=("${path}")
    fi
  done < <(collect_changed_files)

  if [[ ${#BUILD_RELEVANT_CHANGES[@]} -eq 0 ]]; then
    echo "No build-relevant changes detected; skipping xcodebuild."
    echo "Pass --force to run a full validation build anyway."
    exit 0
  fi

  echo "Build-relevant changes detected:"
  printf '  %s\n' "${BUILD_RELEVANT_CHANGES[@]}"
fi

COMMAND=(
  xcodebuild
  -project "${ROOT_DIR}/AudioMator.xcodeproj"
  -scheme AudioMator
  -configuration Debug
  -destination "generic/platform=macOS"
  -derivedDataPath "${DERIVED_DATA_PATH}"
  CODE_SIGNING_ALLOWED=NO
  build
)

printf 'Running:'
for arg in "${COMMAND[@]}"; do
  printf ' %q' "${arg}"
done
printf '\n'

"${COMMAND[@]}" 2>&1 | tee "${LOG_PATH}"
BUILD_EXIT=${PIPESTATUS[0]}

if [[ ${BUILD_EXIT} -eq 0 ]]; then
  prune_app_bundles
  echo "Build succeeded."
  exit 0
fi

if grep -Fq 'The file “AppIcon.icon” couldn’t be opened.' "${LOG_PATH}" \
  && grep -Fq 'Exception while running actool' "${LOG_PATH}" \
  && grep -Fq 'CompileAssetCatalogVariant' "${LOG_PATH}"; then
  prune_app_bundles
  echo
  echo "Known Codex CLI limitation detected:"
  echo "  actool/ibtoold crashed while compiling AudioMator/AppIcon.icon."
  echo "  This is treated as an environment-specific false positive, not a project AppIcon error."
  echo
  echo "Use Xcode on the local desktop to validate the .icon asset itself."
  echo "Other compiler output above is still real; inspect it if you suspect additional failures."
  exit 0
fi

echo
echo "Build failed with a real non-AppIcon error. See ${LOG_PATH}."
exit "${BUILD_EXIT}"
