#!/usr/bin/env bash
# One release gate for maintainers and CI; never launches the app interactively.
set -euo pipefail
cd "$(dirname "$0")/.."
XCODE_INPUT=(-project AudioMator.xcodeproj)
PACKAGE_SOURCE="published Package.resolved"
if [[ $# -gt 0 ]]; then
    [[ $# -eq 2 && "$1" == --local-package ]] || { echo 'Usage: validate-release.sh [--local-package /absolute/package/path]' >&2; exit 2; }
    [[ "$2" == /* && -f "$2/Package.swift" ]] || { echo 'Local package must be an absolute package path' >&2; exit 2; }
    PACKAGE_SOURCE="$2"
    python3 - "$2" <<'WORKSPACE'
from pathlib import Path
import sys
from xml.sax.saxutils import quoteattr
root = Path.cwd()
path = root / '.tmp/MappingIntegration.xcworkspace/contents.xcworkspacedata'
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text('<Workspace version="1.0"><FileRef location=' + quoteattr('absolute:' + str(root / 'AudioMator.xcodeproj'))
    + '/><FileRef location=' + quoteattr('absolute:' + sys.argv[1]) + '/></Workspace>')
WORKSPACE
    XCODE_INPUT=(-workspace .tmp/MappingIntegration.xcworkspace)
fi
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
VALIDATION_DIR=".deriveddata-codex/Validation/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$VALIDATION_DIR"
echo "Validation evidence: $VALIDATION_DIR"
{
    echo "Package source: $PACKAGE_SOURCE"
    git rev-parse HEAD
    git diff --stat
    git diff | shasum -a 256
    if [[ "$PACKAGE_SOURCE" != "published Package.resolved" ]]; then
        git -C "$PACKAGE_SOURCE" rev-parse HEAD
        git -C "$PACKAGE_SOURCE" status --short --branch
        git -C "$PACKAGE_SOURCE" diff | shasum -a 256
        # Include new test/production files in candidate identity as well.
        git -C "$PACKAGE_SOURCE" ls-files --others --exclude-standard -z | while IFS= read -r -d '' path; do
            shasum -a 256 "$PACKAGE_SOURCE/$path"
        done
    else
        cat AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
    fi
} > "$VALIDATION_DIR/source.txt"
run_check() {
    local name="$1"
    shift
    echo "Running $name"
    if "$@" > "$VALIDATION_DIR/$name.log" 2>&1; then
        echo "Passed $name"
    else
        tail -80 "$VALIDATION_DIR/$name.log" >&2
        echo "Failed $name; see $VALIDATION_DIR/$name.log" >&2
        return 1
    fi
}
run_check policy python3 -m unittest discover -s scripts/tests
run_check core swift test --filter AudioMatorCoreLogicTests
python3 scripts/check-core-evidence.py "$VALIDATION_DIR/core.log" 0 "$VALIDATION_DIR/core-gate.json"
APP_STATUS=0
xcodebuild "${XCODE_INPUT[@]}" -scheme AudioMator \
    -configuration Debug -destination 'platform=macOS' -derivedDataPath .deriveddata-codex \
    -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
    -resultBundlePath "$VALIDATION_DIR/AppTests.xcresult" \
    CODE_SIGNING_ALLOWED=NO test > "$VALIDATION_DIR/app.log" 2>&1 || APP_STATUS=$?
xcrun xcresulttool get test-results summary --path "$VALIDATION_DIR/AppTests.xcresult" \
    > "$VALIDATION_DIR/test-summary.json" 2> "$VALIDATION_DIR/summary-error.log" || true
xcrun xcresulttool get test-results tests --path "$VALIDATION_DIR/AppTests.xcresult" \
    > "$VALIDATION_DIR/test-tree.json" 2> "$VALIDATION_DIR/tree-error.log" || true
python3 scripts/check-test-evidence.py "$VALIDATION_DIR/test-summary.json" \
    "$VALIDATION_DIR/test-tree.json" "$APP_STATUS" "$VALIDATION_DIR/test-gate.json"
run_check release xcodebuild "${XCODE_INPUT[@]}" -scheme AudioMator \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build
run_check artifact bash scripts/validate-macos-artifact.sh \
    .deriveddata-codex/Build/Products/Release/AudioMator.app 15.0
echo "Build/test gate passed ($PACKAGE_SOURCE); interactive UI acceptance remains manual. Evidence: $VALIDATION_DIR"
