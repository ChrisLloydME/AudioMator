#!/usr/bin/env bash
# One release gate for maintainers and CI; never launches the app interactively.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
VALIDATION_DIR=".deriveddata-codex/Validation/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$VALIDATION_DIR"
echo "Validation evidence: $VALIDATION_DIR"
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
run_check core swift test --filter AudioMatorCoreLogicTests
run_check app xcodebuild -project AudioMator.xcodeproj -scheme AudioMator \
    -configuration Debug -destination 'platform=macOS' -derivedDataPath .deriveddata-codex \
    -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
    -resultBundlePath "$VALIDATION_DIR/AppTests.xcresult" \
    CODE_SIGNING_ALLOWED=NO test
xcrun xcresulttool get test-results summary --path "$VALIDATION_DIR/AppTests.xcresult" \
    > "$VALIDATION_DIR/test-summary.json"
python3 - "$VALIDATION_DIR/test-summary.json" <<'PY'
import json, sys
summary = json.load(open(sys.argv[1]))
assert summary['totalTestCount'] > 0, 'No app tests executed'
assert summary['failedTests'] == 0, 'Failed app tests'
assert summary['skippedTests'] == 0, 'Skipped tests require explicit review; gate cannot pass'
PY
run_check release xcodebuild -project AudioMator.xcodeproj -scheme AudioMator \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build
run_check artifact bash scripts/validate-macos-artifact.sh \
    .deriveddata-codex/Build/Products/Release/AudioMator.app 15.0
echo "Release gate passed; interactive UI acceptance remains manual. Evidence: $VALIDATION_DIR"
