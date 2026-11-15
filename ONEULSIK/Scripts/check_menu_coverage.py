"""메뉴 커버리지 점검: Docs/MenuCoverage.txt의 메뉴를 앱의 검색 로직으로 찾아 표로 정리한다.

합격/불합격 테스트가 아니라 검색 구멍을 찾는 목록이다. 앱 검색(FoodCatalogService.search)을 그대로 쓰기 위해
ONEULSIKTests/MenuCoverageTests를 시뮬레이터에서 실행하고, 결과를 TestReports/menu-coverage_<날짜_시각>.md에 저장한다.

사용 예:
    python3 Scripts/check_menu_coverage.py
    python3 Scripts/check_menu_coverage.py --menus Docs/MenuCoverage.txt --simulator "iPhone 18 Pro"
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEVELOPER_DIR = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")


def simulator_id(name):
    project = (ROOT / "ONEULSIK.xcodeproj/project.pbxproj").read_text()
    match = re.search(r"IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);(?:(?!\};).)*PRODUCT_BUNDLE_IDENTIFIER = junghwan\.ONEULSIKTests;",
                      project, re.S)
    minimum = tuple(int(x) for x in (match.group(1) if match else "18.0").split("."))
    listing = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"], check=True,
                             capture_output=True, text=True, env={**os.environ, "DEVELOPER_DIR": DEVELOPER_DIR})
    found = []
    for runtime, devices in json.loads(listing.stdout)["devices"].items():
        if "iOS" not in runtime:
            continue
        version = tuple(int(x) for x in runtime.rsplit("iOS-", 1)[-1].split("-"))
        for device in devices:
            if device["name"].startswith("iPhone") and version >= minimum and (not name or device["name"] == name):
                found.append((version, device["udid"], device["name"]))
    if not found:
        raise SystemExit("사용할 iPhone 시뮬레이터를 찾지 못했습니다.")
    return sorted(found, reverse=True)[0][1:]


def cell(value):
    return str(value).replace("|", "\\|")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--menus", type=Path, default=ROOT / "Docs/MenuCoverage.txt")
    parser.add_argument("--simulator", default=os.environ.get("SIMULATOR", ""))
    args = parser.parse_args()

    menus = args.menus.resolve()
    udid, device = simulator_id(args.simulator)
    started = datetime.datetime.now()
    with tempfile.TemporaryDirectory(prefix="oneulsik-menu.") as work:
        output = Path(work) / "coverage.jsonl"
        log = Path(work) / "xcodebuild.log"
        env = {**os.environ, "DEVELOPER_DIR": DEVELOPER_DIR,
               "TEST_RUNNER_ONEULSIK_MENU_FILE": str(menus), "TEST_RUNNER_ONEULSIK_MENU_OUTPUT": str(output)}
        print(f"시뮬레이터: {device} ({udid})", flush=True)
        with log.open("w") as handle:
            status = subprocess.run(
                ["xcodebuild", "test", "-project", "ONEULSIK.xcodeproj", "-scheme", "ONEULSIK",
                 "-destination", f"id={udid}", "-only-testing:ONEULSIKTests/MenuCoverageTests",
                 "-resultBundlePath", str(Path(work) / "MenuCoverage.xcresult")],
                cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT).returncode
        if not output.exists():
            tail = log.read_text(errors="replace").splitlines()[-30:]
            raise SystemExit(f"결과 파일이 없습니다(xcodebuild 종료 코드 {status}).\n" + "\n".join(tail))
        rows = [json.loads(line) for line in output.read_text().splitlines() if line.strip()]

    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    branch = subprocess.run(["git", "branch", "--show-current"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    dirty = bool(subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True).stdout.strip())
    no_general = [r for r in rows if r["general"] == 0]
    processed_first = [r for r in rows if r["firstIsProcessed"]]
    nothing = [r for r in rows if r["total"] == 0]

    lines = [
        f"# 메뉴 커버리지 점검 {started:%Y-%m-%d %H:%M}",
        "",
        "합격/불합격이 아니라 검색 구멍을 찾기 위한 목록이다. 앱의 `FoodCatalogService.search` 결과를 그대로 기록했다.",
        "",
        f"- 실행 시각: {started:%Y-%m-%d %H:%M:%S}",
        f"- 브랜치: `{branch}`",
        f"- 커밋: `{commit}`{' (커밋되지 않은 변경 있음)' if dirty else ''}",
        f"- 시뮬레이터: {device}",
        f"- 메뉴 목록: `{menus.relative_to(ROOT) if menus.is_relative_to(ROOT) else menus}` ({len(rows)}개)",
        "",
        "## 요약",
        "",
        "| 항목 | 개수 |",
        "|---|---:|",
        f"| 메뉴 | {len(rows)} |",
        f"| 일반 음식 결과 없음 | {len(no_general)} |",
        f"| 첫 후보가 가공식품·브랜드 | {len(processed_first)} |",
        f"| 검색 결과 0건 | {len(nothing)} |",
        "",
        "### 일반 음식 결과 없음",
        "",
        ", ".join(r["menu"] for r in no_general) or "없음",
        "",
        "### 첫 후보가 가공식품·브랜드",
        "",
        ", ".join(r["menu"] for r in processed_first) or "없음",
    ]
    groups = OrderedDict()
    for row in rows:
        groups.setdefault(row["category"] or "분류 없음", []).append(row)
    for category, items in groups.items():
        lines += ["", f"## {category}", "",
                  "| 메뉴 | 일반 음식 결과 | 첫 후보 | 첫 후보 가공식품 | 첫 일반 후보 | 전체 결과 수 | 상위 3개 |",
                  "|---|---|---|---|---|---:|---|"]
        for r in items:
            general = f"있음 ({r['general']})" if r["general"] else "**없음**"
            processed = "-" if r["firstIsProcessed"] is None else ("**예**" if r["firstIsProcessed"] else "아니오")
            lines.append(f"| {cell(r['menu'])} | {general} | {cell(r['firstName']) or '-'} | {processed} | "
                         f"{cell(r['firstGeneralName']) or '-'} | {r['total']} | "
                         f"{'<br>'.join(cell(name) for name in r.get('top', [])) or '-'} |")

    report = ROOT / "TestReports" / f"menu-coverage_{started:%Y-%m-%d_%H%M}.md"
    report.parent.mkdir(exist_ok=True)
    report.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\n보고서: {report.relative_to(ROOT)}")
    return 0 if status in (0, 65) or rows else status


if __name__ == "__main__":
    sys.exit(main())
