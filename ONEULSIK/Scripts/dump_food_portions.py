#!/usr/bin/env python3
"""FoodPortion 대표 분량표를 (이름 → 단위, 양, 출처, 같은 양으로 보는 단위)로 덤프하고 두 버전을 비교한다.

FoodPortion.swift의 두 가지 작성 방식을 모두 읽는다.
- switch 방식(2026-11-16 이전): `case "이름", ...:` + `portion = ("단위", 양, 출처)`,
  보조 표는 `case "이름": portion = ("단위", 양, 쪽번호)`
- 조회 표 방식: `Row(names: [...], unit: "...", grams: ..., source: ..., equivalentUnits: [...])`

사용법:
  python3 Scripts/dump_food_portions.py dump [REF]           # REF 생략 시 작업 트리
  python3 Scripts/dump_food_portions.py compare REF1 [REF2]  # REF2 생략 시 작업 트리
REF는 git 커밋(예: a2c07c5). 차이가 없으면 종료 코드 0, 있으면 1.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELATIVE = "ONEULSIK/Models/FoodPortion.swift"


def read_source(ref):
    if ref is None:
        return (ROOT / RELATIVE).read_text(encoding="utf-8")
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
    path = (ROOT / RELATIVE).relative_to(top)
    return subprocess.run(["git", "show", f"{ref}:{path}"], cwd=ROOT, capture_output=True, text=True, check=True).stdout


def string_constants(text):
    return dict(re.findall(r'let (\w+Source) = "([^"]+)"', text))


def page_template(text):
    match = re.search(r'"(https://[^"]*page=)\\\((?:portion\.)?page\)"', text)
    return match.group(1) if match else None


def resolve(expression, constants, template):
    expression = expression.strip()
    if expression.startswith('"') and expression.endswith('"'):
        return expression[1:-1]
    if expression in constants:
        return constants[expression]
    match = re.fullmatch(r"guideSource\(page: (\d+)\)", expression)
    if match and template:
        return template + match.group(1)
    raise ValueError(f"출처 식을 해석하지 못함: {expression}")


def names_in(text):
    return re.findall(r'"([^"]+)"', text)


def parse(text):
    constants = string_constants(text)
    template = page_template(text)
    rows = {}

    def add(names, unit, grams, source, equivalent):
        for name in names:
            if name in rows:
                continue  # 먼저 나온 행이 이긴다(switch와 조회 표 모두 같은 규칙)
            rows[name] = (unit, float(grams), source, ",".join(equivalent))

    if "Row(names:" in text:
        pattern = re.compile(r'Row\(names: \[([^\]]*)\], unit: "([^"]+)", grams: ([\d.]+), source: (.+?)(?:, equivalentUnits: \[([^\]]*)\])?\),\s*$', re.M)
        for match in pattern.finditer(text):
            add(names_in(match.group(1)), match.group(2), match.group(3),
                resolve(match.group(4), constants, template), names_in(match.group(5) or ""))
        return rows

    # switch 방식: 큰 switch(여러 줄 case)와 보조 switch(한 줄 case)
    blocks = re.split(r"\n\s+case ", text)
    for block in blocks[1:]:
        head, _, rest = block.partition(":")
        names = names_in(head)
        if not names:
            continue
        body = rest.split("\n        case ")[0]
        one_line = re.match(r'\s*portion = \("([^"]+)", ([\d.]+), (\d+)\)', rest)
        if one_line and template:
            add(names, one_line.group(1), one_line.group(2), template + one_line.group(3), [])
            continue
        multi = re.search(r'portion = \("([^"]+)", ([\d.]+), ("[^"]*"|\w+)\)', body)
        if not multi:
            continue
        equivalent = re.search(r"equivalentUnits = \[([^\]]*)\]", body)
        add(names, multi.group(1), multi.group(2), resolve(multi.group(3), constants, template),
            names_in(equivalent.group(1)) if equivalent else [])
    return rows


def dump(rows):
    return [f"{name}\t{unit}\t{grams:g}\t{source}\t{equivalent}" for name, (unit, grams, source, equivalent) in sorted(rows.items())]


def main(argv):
    if len(argv) >= 2 and argv[1] == "dump":
        print("\n".join(dump(parse(read_source(argv[2] if len(argv) > 2 else None)))))
        return 0
    if len(argv) >= 3 and argv[1] == "compare":
        left_ref, right_ref = argv[2], (argv[3] if len(argv) > 3 else None)
        left, right = parse(read_source(left_ref)), parse(read_source(right_ref))
        label = right_ref or "작업 트리"
        print(f"{left_ref}: 이름 {len(left)}개, {label}: 이름 {len(right)}개")
        differences = 0
        for name in sorted(set(left) | set(right)):
            if left.get(name) != right.get(name):
                differences += 1
                print(f"- {name}\n    {left_ref}: {left.get(name)}\n    {label}: {right.get(name)}")
        print(f"차이 {differences}개")
        return 1 if differences else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
