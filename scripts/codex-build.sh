#!/usr/bin/env bash

# Local Debug build helper.
#
# This helper fails closed:
# - It only skips after both Git discovery commands succeed and report no
#   build-relevant paths.
# - It only prints the build-completed marker after xcodebuild and log capture
#   both succeed.
# - It never prunes artifacts. Explicit pruning is a separate maintainer action
#   through scripts/prune-app-bundles.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || {
  echo "Unable to resolve the build helper directory." >&2
  exit 1
}
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)" || {
  echo "Unable to resolve the repository root." >&2
  exit 1
}
DERIVED_DATA_PATH="${ROOT_DIR}/.deriveddata-codex"
LOG_PATH="${DERIVED_DATA_PATH}/xcodebuild.log"
FORCE_BUILD=0
BUILD_COMPLETED_MARKER="CODEX_BUILD_COMPLETED"
BUILD_RELEVANT_COUNT=0

TRACKED_CHANGES_FILE=""
UNTRACKED_PATHS_FILE=""

cleanup_temp_files() {
  if [[ -n "${TRACKED_CHANGES_FILE}" ]]; then
    rm -f "${TRACKED_CHANGES_FILE}"
  fi
  if [[ -n "${UNTRACKED_PATHS_FILE}" ]]; then
    rm -f "${UNTRACKED_PATHS_FILE}"
  fi
}
trap cleanup_temp_files EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE_BUILD=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: bash scripts/codex-build.sh [--force]" >&2
      exit 2
      ;;
  esac
done

fail_discovery() {
  echo "error: $1" >&2
  echo "Build discovery failed, so this helper cannot claim the project is unchanged." >&2
  echo "Fix the Git checkout or run 'bash scripts/codex-build.sh --force' to build without Git discovery." >&2
}

is_build_relevant_file() {
  local path="$1"

  case "${path}" in
    AudioMator/*|AudioMatorTests/*|AudioMator.xcodeproj/*|Config/*|scripts/codex-build.sh)
      return 0
      ;;
  esac

  return 1
}

record_relevant_file() {
  local path="$1"

  BUILD_RELEVANT_COUNT=$((BUILD_RELEVANT_COUNT + 1))
  echo "  ${path}"
}

collect_build_relevant_changes() {
  local path

  if ! git --no-optional-locks -C "${ROOT_DIR}" rev-parse --verify --quiet HEAD >/dev/null; then
    fail_discovery "the checkout has no readable HEAD commit."
    return 1
  fi

  TRACKED_CHANGES_FILE="$(mktemp "${TMPDIR:-/tmp}/audiomator-build-tracked.XXXXXX")" || {
    fail_discovery "unable to create a temporary file for tracked changes."
    return 1
  }
  UNTRACKED_PATHS_FILE="$(mktemp "${TMPDIR:-/tmp}/audiomator-build-untracked.XXXXXX")" || {
    fail_discovery "unable to create a temporary file for untracked paths."
    return 1
  }

  # Tracked changes (staged and unstaged) against HEAD. Rename detection is
  # disabled so both sides of a cross-root rename are evaluated separately.
  if ! git --no-optional-locks -C "${ROOT_DIR}" diff --name-only -z --no-renames HEAD -- \
    > "${TRACKED_CHANGES_FILE}"; then
    fail_discovery "unable to read tracked changes from Git."
    return 1
  fi

  if ! git --no-optional-locks -C "${ROOT_DIR}" ls-files --others --exclude-standard -z -- \
    > "${UNTRACKED_PATHS_FILE}"; then
    fail_discovery "unable to read untracked paths from Git."
    return 1
  fi

  echo "Build-relevant changes detected:"

  # NUL-delimited iteration preserves newlines, leading dashes and trailing
  # spaces in file names on macOS Bash 3.
  while IFS= read -r -d '' path; do
    if is_build_relevant_file "${path}"; then
      record_relevant_file "${path}"
    fi
  done < "${TRACKED_CHANGES_FILE}"

  while IFS= read -r -d '' path; do
    if is_build_relevant_file "${path}"; then
      record_relevant_file "${path}"
    fi
  done < "${UNTRACKED_PATHS_FILE}"

  return 0
}

if [[ ${FORCE_BUILD} -ne 1 ]]; then
  if ! collect_build_relevant_changes; then
    exit 1
  fi

  if [[ ${BUILD_RELEVANT_COUNT} -eq 0 ]]; then
    echo "CODEX_BUILD_SKIPPED: Git discovery succeeded and found no build-relevant changes; xcodebuild was not run."
    echo "Nothing was compiled. Pass --force to run a full validation build anyway."
    exit 0
  fi
else
  echo "Forced build requested; Git discovery was not run."
fi

if ! mkdir -p "${DERIVED_DATA_PATH}"; then
  echo "error: unable to create the derived data directory: ${DERIVED_DATA_PATH}" >&2
  exit 1
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

# Record both pipeline statuses immediately: a failed log capture must not be
# hidden by a successful compilation, and vice versa.
"${COMMAND[@]}" 2>&1 | tee "${LOG_PATH}"
BUILD_EXIT=${PIPESTATUS[0]} TEE_EXIT=${PIPESTATUS[1]}

has_appicon_crash_signature() {
  [[ -f "${LOG_PATH}" ]] || return 1
  grep -Fq 'The file “AppIcon.icon” couldn’t be opened.' "${LOG_PATH}" \
    && grep -Fq 'Exception while running actool' "${LOG_PATH}" \
    && grep -Fq 'CompileAssetCatalogVariant' "${LOG_PATH}"
}

if [[ ${BUILD_EXIT} -ne 0 ]]; then
  echo
  if has_appicon_crash_signature; then
    echo "Known Codex CLI limitation detected:"
    echo "  actool/ibtoold crashed while compiling AudioMator/AppIcon.icon."
    echo "  This may be an environment-specific false positive, but the build still failed,"
    echo "  so this run is not valid build evidence. Inspect the log for other errors."
    echo
    echo "Use Xcode on the local desktop to validate the .icon asset itself."
  fi
  if [[ ${TEE_EXIT} -ne 0 ]]; then
    echo "The build log could not be written completely (tee exit ${TEE_EXIT})." >&2
  fi
  echo "Build failed (xcodebuild exit ${BUILD_EXIT}). See ${LOG_PATH}." >&2
  exit "${BUILD_EXIT}"
fi

if [[ ${TEE_EXIT} -ne 0 ]]; then
  echo "error: xcodebuild succeeded but the build log could not be written (tee exit ${TEE_EXIT})." >&2
  echo "This run is not valid build evidence. Fix the log destination and retry." >&2
  exit 1
fi

echo "${BUILD_COMPLETED_MARKER}: xcodebuild succeeded and the build log was captured."
echo "Build succeeded. Log: ${LOG_PATH}"
exit 0
