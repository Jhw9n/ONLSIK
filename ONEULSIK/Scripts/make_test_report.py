"""run_tests.sh가 남긴 결과(JSON Lines)로 TestReports/*.md 보고서를 만든다."""
import argparse
import json
from collections import OrderedDict
from pathlib import Path

SUITES = OrderedDict([
    ("meals", "식사"),
    ("grounding", "파싱"),
    ("normalization", "정규화"),
    ("search", "검색"),
    ("plausibility", "타당성"),
])


def cell(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def case_input(suite, case):
    if suite == "normalization":
        return case.get("alias") or f"{case.get('a')} / {case.get('b')}"
    if suite == "search":
        return case["query"]
    if suite == "plausibility":
        return f"{case['food']} 1{case['unit']} = {case['amount']}{case['amountUnit']}"
    return case["input"]


def main():
    parser = argparse.ArgumentParser()
    for name in ["cases", "results", "log", "output", "started", "branch", "commit", "dirty", "simulator", "exit-code"]:
        parser.add_argument(f"--{name}", required=True)
    args = parser.parse_args()

    cases = json.loads(Path(args.cases).read_text())
    records = {}
    for line in Path(args.results).read_text().splitlines():
        if line.strip():
            record = json.loads(line)
            records[(record["suite"], record["id"])] = record

    rows = []
    for key, suite in SUITES.items():
        for case in cases.get(key, []):
            record = records.get((suite, case["id"]))
            rows.append((suite, case, record, case_input(key, case)))

    # 케이스 파일에 없는 검사(화면 문구, 합계 계산 등)는 기록된 결과를 그대로 "기타 검사"로 붙인다.
    known = {(suite, case["id"]) for suite, case, _, _ in rows}
    extras = [record for key, record in records.items() if key not in known]
    for record in extras:
        rows.append((record["suite"], {"id": record["id"]}, record, record["input"]))

    counts = {"전체": len(rows), "통과": 0, "실패": 0, "실행 불가": 0}
    per_suite = OrderedDict((suite, {"통과": 0, "실패": 0, "실행 불가": 0}) for suite in SUITES.values())
    for record in extras:
        per_suite.setdefault(record["suite"], {"통과": 0, "실패": 0, "실행 불가": 0})
    failure_groups = OrderedDict()
    for suite, case, record, _ in rows:
        status = "실행 불가" if record is None else ("통과" if record["passed"] else "실패")
        counts[status] += 1
        per_suite[suite][status] += 1
        if record and not record["passed"]:
            for kind in record["failureTypes"]:
                failure_groups.setdefault(kind, []).append(f"{case['id']} {record['input']}")

    lines = [
        f"# 테스트 결과 {Path(args.output).stem}",
        "",
        f"- 실행 시각: {args.started}",
        f"- 브랜치: `{args.branch}`",
        f"- 커밋: `{args.commit}`" + (" (커밋되지 않은 변경 있음)" if args.dirty == "yes" else ""),
        f"- 시뮬레이터: {args.simulator}",
        f"- xcodebuild 종료 코드: {args.exit_code}",
        "",
        "## 요약",
        "",
        "| 구분 | 전체 | 통과 | 실패 | 실행 불가 |",
        "|---|---:|---:|---:|---:|",
        f"| **합계** | {counts['전체']} | {counts['통과']} | {counts['실패']} | {counts['실행 불가']} |",
    ]
    for suite, value in per_suite.items():
        total = sum(value.values())
        if total:
            lines.append(f"| {suite} | {total} | {value['통과']} | {value['실패']} | {value['실행 불가']} |")

    if counts["실행 불가"]:
        log_lines = Path(args.log).read_text(errors="replace").splitlines() if Path(args.log).exists() else []
        errors = [line for line in log_lines if "error:" in line][:10] or log_lines[-15:]
        lines += ["", "### 실행 불가 원인 (xcodebuild 로그 발췌)", "", "```", *errors, "```"]

    lines += ["", "## 실패 유형별 요약", ""]
    if failure_groups:
        lines += ["| 유형 | 개수 | 케이스 |", "|---|---:|---|"]
        for kind, items in failure_groups.items():
            lines.append(f"| {cell(kind)} | {len(items)} | {cell(', '.join(items))} |")
    else:
        lines.append("실패 없음")

    for suite in per_suite:
        suite_rows = [row for row in rows if row[0] == suite]
        if not suite_rows:
            continue
        lines += ["", f"## {suite} 케이스", ""]
        if suite == "식사":
            lines += ["| 결과 | ID | 입력 | 기대값 | 실제 결과 | 질문 | 실패 사유 |", "|---|---|---|---|---|---:|---|"]
        else:
            lines += ["| 결과 | ID | 입력 | 기대값 | 실제 결과 | 실패 사유 |", "|---|---|---|---|---|---|"]
        for _, case, record, text in suite_rows:
            if record is None:
                values = ["⚪ 실행 불가", case["id"], text, "", "", ""]
                if suite == "식사":
                    values.insert(5, "")
            else:
                mark = "✅ 통과" if record["passed"] else "❌ 실패"
                values = [mark, case["id"], record["input"], record["expected"], record["actual"], "; ".join(record["reasons"])]
                if suite == "식사":
                    values.insert(5, record["questions"] if record["questions"] is not None else "")
            lines.append("| " + " | ".join(cell(v) for v in values) + " |")

    # 통과해도 남기는 점검 상세(예: L03 대표 분량 음식 점검의 원인별 목록). details가 없는 기록은 표시하지 않는다.
    detailed = [(case, record) for _, case, record, _ in rows if record and record.get("details")]
    for case, record in detailed:
        details = record["details"]
        causes = [line for line in details[1:] if line.startswith("원인 ")]
        inputs = [line for line in details[1:] if line.startswith("입력 ")]
        lines += ["", f"## 점검 상세: {case['id']}", "", cell(details[0]), ""]
        if causes:
            lines += ["| 원인 | 건수 | 목록 |", "|---|---:|---|"]
            for line in causes:
                head, _, items = line[len("원인 "):].partition(": ")
                name, _, count = head.rpartition(" ")
                lines.append(f"| {cell(name)} | {cell(count.removesuffix('건'))} | {cell(items)} |")
        if inputs:
            lines += ["", "<details><summary>입력별 기록 자료</summary>", ""]
            lines += [f"- {cell(line[len('입력 '):])}" for line in inputs]
            lines += ["", "</details>"]

    asked = [(case, record) for suite, case, record, _ in rows if suite == "식사" and record and record["questionLog"]]
    if asked:
        lines += ["", "## 확인 질문 기록", "", "첫 번째 선택지를 고르는 것으로 진행했습니다.", ""]
        for case, record in asked:
            lines.append(f"- **{case['id']} {record['input']}**")
            lines += [f"  - {cell(entry)}" for entry in record["questionLog"]]

    Path(args.output).write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
