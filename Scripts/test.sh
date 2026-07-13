#!/usr/bin/env bash
#
# test.sh — run the same build + test + coverage gate CI runs, locally.
#
# Usage:
#   Scripts/test.sh              # auto-pick an available iPhone simulator
#   SIMULATOR="iPhone 17" Scripts/test.sh
#   COVERAGE_MIN=30 Scripts/test.sh
#
# Run this from the repository root.

set -euo pipefail

PROJECT="Runnit iOS.xcodeproj"
SCHEME="Runnit iOS"
RESULT_BUNDLE="${RESULT_BUNDLE:-TestResults.xcresult}"
COVERAGE_MIN="${COVERAGE_MIN:-15}"

cd "$(dirname "$0")/.."

# Pick a simulator if one wasn't provided.
if [ -z "${SIMULATOR:-}" ]; then
  SIMULATOR=$(xcrun simctl list devices available \
    | awk -F '[()]' '/iPhone/ { gsub(/^ +| +$/, "", $1); print $1; exit }')
fi
if [ -z "$SIMULATOR" ]; then
  echo "No available iPhone simulator found." >&2
  exit 1
fi
echo "▸ Simulator: $SIMULATOR"
echo "▸ Coverage threshold: ${COVERAGE_MIN}%"

rm -rf "$RESULT_BUNDLE"

set -o pipefail
if command -v xcbeautify >/dev/null; then
  FMT=(xcbeautify)
else
  FMT=(cat)
fi

xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO \
  | "${FMT[@]}"

echo
"$(dirname "$0")/coverage-report.sh" "$RESULT_BUNDLE" "$COVERAGE_MIN"
