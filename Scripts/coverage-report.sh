#!/usr/bin/env bash
#
# coverage-report.sh — summarize code coverage from an .xcresult bundle and
# enforce a minimum line-coverage threshold for the app target.
#
# Usage:
#   Scripts/coverage-report.sh <path-to.xcresult> [min-percent]
#
# The minimum can also come from the COVERAGE_MIN environment variable.
# Defaults to 15. When run inside GitHub Actions ($GITHUB_STEP_SUMMARY set),
# a Markdown summary table is appended to the job summary.
#
# Exit status: 0 if coverage >= threshold, 1 otherwise (or on bad input).

set -euo pipefail

XCRESULT="${1:-}"
MIN="${2:-${COVERAGE_MIN:-15}}"
# The app target whose coverage gates CI (test targets are ignored).
APP_TARGET="${COVERAGE_TARGET:-Runnit iOS.app}"

if [[ -z "$XCRESULT" || ! -e "$XCRESULT" ]]; then
  echo "error: result bundle not found: '$XCRESULT'" >&2
  echo "usage: $0 <path-to.xcresult> [min-percent]" >&2
  exit 1
fi

TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT
xcrun xccov view --report --json "$XCRESULT" > "$TMP_JSON"

APP_TARGET="$APP_TARGET" MIN="$MIN" COV_JSON="$TMP_JSON" python3 <<'PY'
import json, os, sys

data = json.load(open(os.environ["COV_JSON"]))
app_target = os.environ["APP_TARGET"]
minimum = float(os.environ["MIN"])
summary_path = os.environ.get("GITHUB_STEP_SUMMARY")

target = next((t for t in data.get("targets", []) if t["name"] == app_target), None)
if target is None:
    # Fall back to the first non-test target so the script is resilient to renames.
    target = next((t for t in data.get("targets", []) if "Tests" not in t["name"]), None)
if target is None:
    print("error: no application target found in coverage report", file=sys.stderr)
    sys.exit(1)

overall = target["lineCoverage"] * 100
covered = sum(f["coveredLines"] for f in target["files"])
total = sum(f["executableLines"] for f in target["files"])
files = sorted(target["files"], key=lambda f: f["lineCoverage"])

def bar(pct):
    filled = round(pct / 10)
    return "█" * filled + "░" * (10 - filled)

print(f"Target: {target['name']}")
print(f"Overall line coverage: {overall:.2f}%  ({covered}/{total} lines)")
print(f"Threshold: {minimum:.0f}%")
print()
print(f"{'Coverage':>9}  File")
print(f"{'-'*9}  {'-'*40}")
for f in files:
    print(f"{f['lineCoverage']*100:8.1f}%  {f['name']}")

passed = overall + 1e-9 >= minimum

if summary_path:
    with open(summary_path, "a") as fh:
        status = "✅ passed" if passed else "❌ below threshold"
        fh.write("## 📊 Code coverage\n\n")
        fh.write(f"**{overall:.2f}%** line coverage for `{target['name']}` "
                 f"(threshold {minimum:.0f}%) — {status}\n\n")
        fh.write("| Coverage | File |\n|---:|:---|\n")
        for f in files:
            fh.write(f"| `{bar(f['lineCoverage']*100)}` {f['lineCoverage']*100:.1f}% | {f['name']} |\n")

if not passed:
    print(f"\n::error::Coverage {overall:.2f}% is below the required {minimum:.0f}% threshold",
          file=sys.stderr)
    sys.exit(1)

print(f"\nCoverage {overall:.2f}% meets the {minimum:.0f}% threshold.")
PY
