"""전시 대비 입력 점검: Docs/ExhibitionInputs.txt의 입력을 AI 식사 입력 흐름(가짜 해석기)으로 끝까지 돌려 정리한다.

ONEULSIKTests/ExhibitionAuditTests를 시뮬레이터에서 실행하고, 결과를 자동 기준으로 S1·S2·S3·정상으로 나눠
TestReports/exhibition-audit_<날짜_시각>.md에 저장한다. 자동 분류는 사람이 다시 볼 후보를 고르는 것이고 최종 판정이 아니다.
가짜 해석기는 입력 줄을 그대로 음식 이름으로 돌려주고 분량·영양 추정은 하지 않는다(실기기 모델이 하는 부분).

자동 기준
- S1(전시 전 꼭 막아야 함): 오류, 질문 3회 이상·반복, 확인 질문 없이 1회 1,500kcal 이상,
  g 기준 음식이 1회 10kcal 미만, 입력에 없는 원두·분말·소스·시럽 같은 재료로 기록, 입력과 글자가 거의 겹치지 않는 이름으로 기록
- S2(가능하면 고칠 것): 브랜드·제품 입력이 아닌데 가공식품·브랜드 제품이 첫 선택지거나 기록 자료,
  어색한 단위(mL 음료를 인분·공기·접시로), 같은 음식의 표현만 바꾼 입력끼리 기록 자료나 g당 열량이 크게 다름
- S3(실기기 모델에 맡김): 재료·소스 질문(모델 영양 추정이 필요), 수량을 적었는데 수량 질문(모델 분량 추정이 필요)
- 정상: 그 밖(기록 카드까지 가거나 수량을 적지 않아 수량을 묻는 자연스러운 질문 1회 등)

사용 예:
    python3 -B Scripts/check_exhibition_inputs.py
    python3 -B Scripts/check_exhibition_inputs.py --simulator "iPhone 18 Pro"
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import OrderedDict, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_menu_coverage import DEVELOPER_DIR, ROOT, cell, simulator_id  # noqa: E402

AMOUNT = re.compile(r"\s*(?:\d+(?:\.\d+)?\s*(?:인분|그릇|개|잔|캔|병|조각|줄|공기|마리|판|장|송이|줌|꼬치|cc|g|mL)|"
                    r"(?:한|두|세|네)\s*(?:인분|그릇|개|잔|캔|병|조각|줄|공기|마리|판|장|송이|줌|꼬치)|"
                    r"반\s*(?:마리|병|개|공기)?|반마리|조금|하나|둘)\s*$")
INGREDIENT_WORDS = ["원두", "분말", "가루", "티백", "원액", "농축", "소스", "시럽", "믹스", "생것", "말린것"]
PRODUCT_CATEGORIES = ("편의점", "브랜드")


def base_name(text):
    previous = None
    while previous != text:
        previous, text = text, AMOUNT.sub("", text).strip()
    return text


def compact(text):
    return re.sub(r"[^0-9A-Za-z가-힣]", "", text)


def overlap(a, b):
    """두 이름의 글자 겹침(입력 기준 비율)."""
    a, b = compact(a), compact(b)
    return sum(1 for ch in set(a) if ch in b) / max(len(set(a)), 1)


def classify(row, variants):
    reasons = {"S1": [], "S2": [], "S3": []}
    text, base = row["input"], base_name(row["input"])
    has_amount = base != text
    questions = row["questions"]
    if row["outcome"] == "error":
        reasons["S1"].append(f"오류: {row['error']}")
    if len(questions) >= 3 or "(질문 반복)" in questions:
        reasons["S1"].append(f"질문 {len(questions)}회")
    confirmed_large = any("이 양이 맞나요" in q for q in questions)
    for item in row["items"]:
        name = item["databaseName"] or item["name"]
        if item["kcal"] >= 1500 and not confirmed_large:
            reasons["S1"].append(f"확인 없이 {item['kcal']:.0f}kcal")
        if item["amountUnit"] == "g" and item["kcal"] < 10:
            reasons["S1"].append(f"g 음식 {item['kcal']:.1f}kcal")
        words = [w for w in INGREDIENT_WORDS if w in name and w not in text]
        if words:
            reasons["S1"].append(f"입력에 없는 ‘{'·'.join(words)}’ 자료({name})")
        if overlap(base, name) < 0.34:
            reasons["S1"].append(f"이름이 거의 다름({name})")
        if item["category"] == "가공식품" or item["brand"]:
            if row["category"] not in PRODUCT_CATEGORIES and not row["category"].startswith(PRODUCT_CATEGORIES):
                reasons["S2"].append(f"가공식품·제품으로 기록({name})")
        if item["amountUnit"] == "mL" and item["unit"] in ("인분", "공기", "접시"):
            reasons["S2"].append(f"단위 어색: {item['unit']}")
    if row["choices"] and row["category"].split("(")[0] not in PRODUCT_CATEGORIES:
        first = row["choices"][0]
        if questions and "이 제품을 드셨나요" in questions[0]:
            reasons["S2"].append(f"첫 질문이 제품 확인({first})")
    group = variants.get(base, [])
    if len(group) > 1 and row["items"]:
        mine = row["items"][0]
        for other in group:
            if other is row or not other["items"]:
                continue
            theirs = other["items"][0]
            if mine["id"] != theirs["id"]:
                reasons["S2"].append(f"표현만 다른 ‘{other['input']}’과 자료가 다름({theirs['databaseName'] or theirs['name']})")
                break
            if mine["amount"] > 0 and theirs["amount"] > 0:
                ratio = (mine["kcal"] / mine["amount"]) / max(theirs["kcal"] / theirs["amount"], 1e-9)
                if ratio > 1.5 or ratio < 1 / 1.5:
                    reasons["S2"].append(f"표현만 다른 ‘{other['input']}’과 g당 열량이 {ratio:.1f}배")
                    break
    last = questions[-1] if questions else ""
    if row["outcome"] == "question" and "재료나 소스" in last:
        reasons["S3"].append("재료·소스 질문(모델 영양 추정 필요)")
    if row["outcome"] == "question" and "얼마나" in last and has_amount:
        reasons["S3"].append("수량을 적었는데 수량 질문(모델 분량 추정 필요)")
    level = next((key for key in ("S1", "S2", "S3") if reasons[key]), "정상")
    return level, reasons


def describe(row):
    if row["outcome"] == "ready":
        parts = []
        for item in row["items"]:
            db = item["databaseName"]
            name = item["name"] if not db or db == item["name"] else f"{item['name']} (DB: {db})"
            kind = "가공" if item["category"] == "가공식품" or item["brand"] else "일반"
            parts.append(f"{name} · {item['count']:g}{item['unit']} · {item['amount']:g}{item['amountUnit']} · "
                         f"{item['kcal']:.0f}kcal · {kind}")
        return "; ".join(parts)
    if row["outcome"] == "error":
        return f"오류: {row['error']}"
    return f"질문에서 멈춤: {row['questions'][-1] if row['questions'] else '-'}"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--inputs", type=Path, default=ROOT / "Docs/ExhibitionInputs.txt")
    parser.add_argument("--simulator", default=os.environ.get("SIMULATOR", ""))
    parser.add_argument("--jsonl", type=Path, help="이미 만든 결과(JSON Lines)로 보고서만 다시 만든다")
    args = parser.parse_args()

    started = datetime.datetime.now()
    device = "-"
    if args.jsonl:
        rows = [json.loads(line) for line in args.jsonl.read_text().splitlines() if line.strip()]
    else:
        udid, device = simulator_id(args.simulator)
        with tempfile.TemporaryDirectory(prefix="oneulsik-exhibition.") as work:
            output = Path(work) / "audit.jsonl"
            log = Path(work) / "xcodebuild.log"
            env = {**os.environ, "DEVELOPER_DIR": DEVELOPER_DIR,
                   "TEST_RUNNER_ONEULSIK_EXHIBITION_FILE": str(args.inputs.resolve()),
                   "TEST_RUNNER_ONEULSIK_EXHIBITION_OUTPUT": str(output)}
            print(f"시뮬레이터: {device} ({udid})", flush=True)
            with log.open("w") as handle:
                status = subprocess.run(
                    ["xcodebuild", "test", "-project", "ONEULSIK.xcodeproj", "-scheme", "ONEULSIK",
                     "-destination", f"id={udid}", "-only-testing:ONEULSIKTests/ExhibitionAuditTests",
                     "-resultBundlePath", str(Path(work) / "Exhibition.xcresult")],
                    cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT).returncode
            if not output.exists():
                tail = log.read_text(errors="replace").splitlines()[-30:]
                raise SystemExit(f"결과 파일이 없습니다(xcodebuild 종료 코드 {status}).\n" + "\n".join(tail))
            rows = [json.loads(line) for line in output.read_text().splitlines() if line.strip()]
            if os.environ.get("ONEULSIK_EXHIBITION_KEEP"):
                Path(os.environ["ONEULSIK_EXHIBITION_KEEP"]).write_text(output.read_text())

    variants = defaultdict(list)
    for row in rows:
        variants[base_name(row["input"])].append(row)
    results = [(row, *classify(row, variants)) for row in rows]
    counts = OrderedDict((key, 0) for key in ("S1", "S2", "S3", "정상"))
    for _, level, _ in results:
        counts[level] += 1

    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    branch = subprocess.run(["git", "branch", "--show-current"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    stamp = started.strftime("%Y-%m-%d_%H%M")
    lines = [
        f"# 전시 대비 입력 점검 {stamp}",
        "",
        f"- 실행 시각: {started:%Y-%m-%d %H:%M}",
        f"- 브랜치: `{branch}`, 커밋: `{commit}`",
        f"- 시뮬레이터: {device}",
        f"- 입력: `{args.inputs.relative_to(ROOT) if args.inputs.is_absolute() else args.inputs}` {len(rows)}개(여러 음식 한 줄 [제외] 분류는 돌리지 않음)",
        "- 가짜 해석기: 입력 줄을 그대로 음식 이름으로 돌려주고 분량·영양 추정은 하지 않음. 확인 질문은 첫 선택지, 수량 질문에서 멈춤.",
        "- 실기기 모델이 하는 분량·영양 추정과 여러 음식 나누기는 확인하지 않았음. 자동 분류는 사람이 다시 볼 후보이며 최종 판정은 아래 '사람 판정' 절.",
        "",
        "## 자동 분류",
        "",
        "| 분류 | 개수 |",
        "|---|---:|",
        *[f"| {key} | {value} |" for key, value in counts.items()],
    ]
    for level in ("S1", "S2", "S3"):
        lines += ["", f"### {level} 후보", "", "| 입력 | 분류 | 결과 | 걸린 기준 |", "|---|---|---|---|"]
        for row, found, reasons in results:
            if found == level:
                lines.append(f"| {cell(row['input'])} | {cell(row['category'])} | {cell(describe(row))} | "
                             f"{cell('; '.join(reasons[level]))} |")
    lines += ["", "## 전체 결과", "", "<details><summary>입력별 결과</summary>", "",
              "| 입력 | 분류 | 자동 판정 | 질문 | 결과 |", "|---|---|---|---|---|"]
    for row, found, _ in results:
        lines.append(f"| {cell(row['input'])} | {cell(row['category'])} | {found} | "
                     f"{cell(' → '.join(row['questions']) or '-')} | {cell(describe(row))} |")
    lines += ["", "</details>"]
    output = ROOT / "TestReports" / f"exhibition-audit_{stamp}.md"
    output.write_text("\n".join(lines) + "\n")
    print(f"입력 {len(rows)}개: " + ", ".join(f"{k} {v}" for k, v in counts.items()))
    print(f"보고서: {output.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
