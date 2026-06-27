#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEEP_DERIVED_DATA="${ROOT_DIR}/.deriveddata-codex"
KEEP_APP="${ROOT_DIR}/.deriveddata-codex/Build/Products/Debug/AudioMator.app"

while IFS= read -r derived_data_path; do
  if [[ "${derived_data_path}" == "${KEEP_DERIVED_DATA}" ]]; then
    continue
  fi

  rm -rf "${derived_data_path}"
done < <(find "${ROOT_DIR}" -maxdepth 1 -name '.deriveddata*' -type d -prune)

while IFS= read -r app_path; do
  if [[ "${app_path}" == "${KEEP_APP}" ]]; then
    continue
  fi

  rm -rf "${app_path}"
done < <(find "${ROOT_DIR}" -name '*.app' -type d -prune)
