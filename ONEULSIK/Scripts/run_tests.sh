#!/bin/bash
# ONEULSIKTests를 실행하고 결과 요약을 TestReports/<날짜_시각>.md로 저장한다.
# 사용법: Scripts/run_tests.sh                 (기본 시뮬레이터 자동 선택)
#         SIMULATOR="iPhone 18 Pro" Scripts/run_tests.sh
#         SIMULATOR_ID=<UDID> Scripts/run_tests.sh
# .xcresult와 로그는 임시 폴더에 남기고 저장소에는 넣지 않는다.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

started_at="$(date '+%Y-%m-%d %H:%M:%S %z')"
stamp="$(date '+%Y-%m-%d_%H%M')"
work="$(mktemp -d "${TMPDIR:-/tmp}/oneulsik-tests.XXXXXX")"
results="$work/results.jsonl"
log="$work/xcodebuild.log"
bundle="$work/ONEULSIKTests.xcresult"
: > "$results"

# 시뮬레이터: 지정값 > 테스트 타깃 최소 iOS 이상인 iPhone 중 첫 번째
min_ios="$(grep -B8 'PRODUCT_BUNDLE_IDENTIFIER = junghwan.ONEULSIKTests;' ONEULSIK.xcodeproj/project.pbxproj \
    | sed -n 's/.*IPHONEOS_DEPLOYMENT_TARGET = \([0-9.]*\);.*/\1/p' | head -1)"
min_ios="${min_ios:-18.0}"
if [[ -z "${SIMULATOR_ID:-}" ]]; then
    SIMULATOR_ID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name, minimum = sys.argv[1], tuple(int(x) for x in sys.argv[2].split("."))
devices = json.load(sys.stdin)["devices"]
found = []
for runtime, items in devices.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(x) for x in runtime.rsplit("iOS-", 1)[-1].split("-"))
    for d in items:
        if d["name"].startswith("iPhone") and version >= minimum and (not name or d["name"] == name):
            found.append((version, d["udid"]))
print(sorted(found, reverse=True)[0][1] if found else "")
' "${SIMULATOR:-}" "$min_ios")"
fi
simulator_name="$(xcrun simctl list devices -j | python3 -c '
import json, sys
for items in json.load(sys.stdin)["devices"].values():
    for d in items:
        if d["udid"] == sys.argv[1]: print(d["name"]); sys.exit()
' "${SIMULATOR_ID:-none}")"

status=0
if [[ -z "${SIMULATOR_ID:-}" ]]; then
    echo "iOS ${min_ios} 이상 iPhone 시뮬레이터를 찾지 못했습니다." | tee "$log"
    status=70
else
    echo "시뮬레이터: ${simulator_name} (${SIMULATOR_ID}), 결과 폴더: ${work}"
    TEST_RUNNER_ONEULSIK_REPORT_FILE="$results" xcodebuild test \
        -project ONEULSIK.xcodeproj -scheme ONEULSIK \
        -destination "id=${SIMULATOR_ID}" \
        -only-testing:ONEULSIKTests \
        -resultBundlePath "$bundle" > "$log" 2>&1
    status=$?
fi

mkdir -p TestReports
report="TestReports/${stamp}.md"
python3 Scripts/make_test_report.py \
    --cases ONEULSIKTests/MealRegressionCases.json \
    --results "$results" --log "$log" --output "$report" \
    --started "$started_at" --branch "$(git branch --show-current)" \
    --commit "$(git rev-parse --short HEAD)" --dirty "$(git status --porcelain | grep -q . && echo yes || echo no)" \
    --simulator "${simulator_name:-없음}" --exit-code "$status"
echo "보고서: $report"
echo "원본 결과: $bundle"
exit "$status"
