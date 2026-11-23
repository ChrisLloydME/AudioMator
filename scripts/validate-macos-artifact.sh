#!/usr/bin/env bash

set -euo pipefail

APP_PATH="${1:?Usage: validate-macos-artifact.sh /path/to/AudioMator.app [expected-minimum-version]}"
EXPECTED_MINIMUM_VERSION="${2:-15.0}"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"

if [[ ! -d "${APP_PATH}" || ! -f "${INFO_PLIST}" ]]; then
  echo "Invalid macOS application bundle: ${APP_PATH}" >&2
  exit 1
fi

version_is_at_most() {
  local actual="$1"
  local maximum="$2"

  awk -v actual="${actual}" -v maximum="${maximum}" '
    BEGIN {
      actualCount = split(actual, actualParts, ".")
      maximumCount = split(maximum, maximumParts, ".")
      count = actualCount > maximumCount ? actualCount : maximumCount
      for (partIndex = 1; partIndex <= count; partIndex++) {
        actualPart = partIndex <= actualCount ? actualParts[partIndex] + 0 : 0
        maximumPart = partIndex <= maximumCount ? maximumParts[partIndex] + 0 : 0
        if (actualPart < maximumPart) exit 0
        if (actualPart > maximumPart) exit 1
      }
      exit 0
    }
  '
}

BUNDLE_MINIMUM_VERSION="$(plutil -extract LSMinimumSystemVersion raw "${INFO_PLIST}")"
if [[ "${BUNDLE_MINIMUM_VERSION}" != "${EXPECTED_MINIMUM_VERSION}" ]]; then
  echo "Bundle minimum ${BUNDLE_MINIMUM_VERSION} does not match ${EXPECTED_MINIMUM_VERSION}." >&2
  exit 1
fi

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "${INFO_PLIST}")"
if [[ "${BUNDLE_ID}" != "com.LloydME.AudioMator" ]]; then
  echo "Unexpected bundle identifier: ${BUNDLE_ID}" >&2
  exit 1
fi

EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw "${INFO_PLIST}")"
for BINARY in "${APP_PATH}/Contents/MacOS/${EXECUTABLE_NAME}" \
    "${APP_PATH}/Contents/Frameworks/TagLibAudioMetadataTagLib.framework/TagLibAudioMetadataTagLib"; do
  if [[ ! -f "${BINARY}" ]] || ! ARCHITECTURES="$(lipo -archs "${BINARY}")" ||
      [[ " ${ARCHITECTURES} " != *" arm64 "* || " ${ARCHITECTURES} " != *" x86_64 "* ]]; then
    echo "Missing arm64 or x86_64 slice: ${BINARY}" >&2
    exit 1
  fi
  echo "Validated arm64 and x86_64: ${BINARY#"${APP_PATH}/"}"
done

for LICENSE in AudioMator-AGPL-3.0.txt TagLib-LGPL-2.1.txt TagLib-MPL-1.1.txt \
    TagLibAudioMetadata-MIT.txt utfcpp-Boost-1.0.txt; do
  LICENSE_PATH="${APP_PATH}/Contents/Resources/${LICENSE}"
  if [[ ! -f "${LICENSE_PATH}" || ! -s "${LICENSE_PATH}" ]]; then
    echo "Missing or empty bundled license: ${LICENSE_PATH}" >&2
    exit 1
  fi
done

MACHO_COUNT=0
while IFS= read -r -d '' CANDIDATE; do
  FILE_DESCRIPTION="$(file -b "${CANDIDATE}")"
  [[ "${FILE_DESCRIPTION}" == *"Mach-O"* ]] || continue

  MACHO_COUNT=$((MACHO_COUNT + 1))
  BUILD_INFO="$(vtool -show-build "${CANDIDATE}")"
  PLATFORMS="$(awk '$1 == "platform" { print $2 }' <<< "${BUILD_INFO}")"
  if [[ -z "${PLATFORMS}" ]] || [[ -n "$(awk '$0 != "MACOS"' <<< "${PLATFORMS}")" ]]; then
    echo "Non-macOS Mach-O found in app bundle: ${CANDIDATE}" >&2
    exit 1
  fi

  MINIMUM_VERSIONS="$(awk '$1 == "minos" { print $2 }' <<< "${BUILD_INFO}")"
  if [[ -z "${MINIMUM_VERSIONS}" ]]; then
    echo "No LC_BUILD_VERSION minimum found: ${CANDIDATE}" >&2
    exit 1
  fi

  while IFS= read -r MINIMUM_VERSION; do
    if ! version_is_at_most "${MINIMUM_VERSION}" "${EXPECTED_MINIMUM_VERSION}"; then
      echo "${CANDIDATE} requires macOS ${MINIMUM_VERSION}; maximum allowed is ${EXPECTED_MINIMUM_VERSION}." >&2
      exit 1
    fi
  done <<< "${MINIMUM_VERSIONS}"

  echo "Validated ${CANDIDATE#"${APP_PATH}/"}: minOS ${MINIMUM_VERSIONS//$'\n'/, }"
done < <(find "${APP_PATH}/Contents" -type f -print0)

if [[ ${MACHO_COUNT} -eq 0 ]]; then
  echo "No Mach-O files found in ${APP_PATH}." >&2
  exit 1
fi

echo "Validated ${BUNDLE_ID}, macOS ${BUNDLE_MINIMUM_VERSION}, ${MACHO_COUNT} Mach-O files and five bundled licenses."
