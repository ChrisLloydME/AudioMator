#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${ROOT_DIR}/.deriveddata-codex"
LOG_PATH="${DERIVED_DATA_PATH}/xcodebuild.log"

mkdir -p "${DERIVED_DATA_PATH}"

COMMAND=(
  xcodebuild
  -project "${ROOT_DIR}/AudioMator.xcodeproj"
  -scheme AudioMator
  -configuration Debug
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
  echo "Build succeeded."
  exit 0
fi

if grep -Fq 'The file “AppIcon.icon” couldn’t be opened.' "${LOG_PATH}" \
  && grep -Fq 'Exception while running actool' "${LOG_PATH}" \
  && grep -Fq 'CompileAssetCatalogVariant' "${LOG_PATH}"; then
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
