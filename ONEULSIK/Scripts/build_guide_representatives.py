#!/usr/bin/env python3
"""식약처 「외식 영양성분 자료집 제2권」(2013)과 맞는 DB 자료를 대표 자료로 지정하는 데이터 파일을 만든다.

원칙(2026-11-19 결정): 대표 분량표(FoodPortion.swift)의 출처가 이 자료집(guideSource)인 음식은,
자료집의 100g당 열량과 ±2% 안에서 맞는 g 기준 DB 자료(브랜드 없음, 가공식품 아님)를 그 음식의 대표 자료로 쓴다.
그런 자료가 없으면 지정하지 않는다(앱은 priority, 기준일, 식품코드 순을 유지).

- 자료집: 음식마다 한 쪽. `pdftotext -layout`(poppler)으로 쪽마다 항목 번호·이름·중량(g)·열량(Kcal)을 읽는다.
- 대표 분량표 행은 guideSource(page: N)의 쪽 번호로 자료집 항목과 연결한다.
- 같은 음식: 정규화한 이름(validate_food_references.normalized)이 같거나, 대표 분량 이름 규칙 1~4
  (그대로, 순서 뒤집기, 분류어, 괄호)를 적용한 이름이 겹치는 DB 이름. 규칙 5(첫 단어)는 쓰지 않는다.
- 맞는 자료가 같은 이름에 둘 이상이면 자료집 값에 가장 가까운 자료(같으면 식품코드 순)를 고른다.
- 참고표(FoodReferences.json)가 같은 이름·단위 묶음에 다른 자료를 지정했으면 참고표가 우선이므로 넣지 않는다.
- mL 자료는 비교하지 않는다(1mL=1g 비교로만 맞는 경우는 지정하지 않음).
- DB는 읽기 전용(mode=ro)으로 연다. 자료집 PDF는 저장소에 넣지 않는다.

사용법: python3 -B Scripts/build_guide_representatives.py <2013.pdf> [--check]
  --check: 데이터 파일을 쓰지 않고 지금 파일과 같은지만 확인(같으면 종료 코드 0)
"""
import collections
import hashlib
import json
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dump_food_portions import parse as parse_portions, read_source  # noqa: E402
from validate_food_references import normalized  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "ONEULSIK/Resource/Data"
OUTPUT = DATA / "GuideRepresentatives.json"
GUIDE_URL = "https://www.foodsafetykorea.go.kr/upload/mkisna/2013.pdf"
GUIDE_SHA256 = "3dbbf29e58131288efb928367cf71848da78e4876db4874521dcf2dab1716316"
TOLERANCE = 0.02
QUARANTINED = {"D402-077000000-0001", "D702-077000000-0001"}  # FoodCatalogQuality.quarantinedIDs


def guide_items(pdf):
    pages = int(re.search(r"Pages:\s+(\d+)", subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True, check=True).stdout).group(1))
    items = []
    for page in range(1, pages + 1):
        text = subprocess.run(["pdftotext", "-layout", "-f", str(page), "-l", str(page), str(pdf), "-"],
                              capture_output=True, text=True, check=True).stdout
        item = None
        for line in text.splitlines():
            header = re.match(r"^\s{0,12}(\d{3})\s+(\S.*?)\s*$", line)
            if header and not re.search(r"\d+\.\d", line) and len(header.group(2)) < 30:
                item = {"number": header.group(1), "name": header.group(2), "page": page}
                items.append(item)
                continue
            if item is None:
                continue
            weight = re.search(r"중량\s*\((g|ml|mL)\)\s+([\d.]+)\s+([\d.]+)", line)
            if weight and "serving" not in item:
                item["unit"], item["serving"], item["base"] = weight.group(1), float(weight.group(2)), float(weight.group(3))
            energy = re.search(r"열량\s*\(Kcal\)\s+([\d.]+)\s+([\d.]+)", line)
            if energy and "kcal" not in item:
                item["kcal"], item["kcalPer100"] = float(energy.group(1)), float(energy.group(2))
    incomplete = [item for item in items if not {"unit", "serving", "base", "kcal", "kcalPer100"} <= item.keys()]
    if incomplete or any(item["unit"] != "g" or item["base"] != 100 for item in items):
        raise SystemExit(f"자료집 항목을 다 읽지 못함: {incomplete[:3]}")
    return pages, items


def same_dish_names(name):
    """FoodPortion.sameDishNames(대표 분량 이름 규칙 1~4)와 같은 규칙."""
    variants = [name]
    plain = re.sub(r"\([^)]*\)", " ", name)
    words = [word for word in re.split(r"[\s,]+", plain) if word]
    if len(words) >= 2:
        variants.append("".join(words[1:]) + words[0])
        categories = [category for category in words[0].split("/") if category]
        if any(category in words[-1] for category in categories):
            variants.append(words[-1])
    inner = re.search(r"\(([^)]*)\)", name)
    if inner:
        variants += [part.strip() for part in re.split(r"[/,]", inner.group(1)) if part.strip()]
    return {normalized(variant) for variant in variants}


def build(pdf):
    with open(pdf, "rb") as file:
        checksum = hashlib.file_digest(file, "sha256").hexdigest()
    if checksum != GUIDE_SHA256:
        raise SystemExit(f"자료집 SHA-256이 다름: {checksum}")
    pages, items = guide_items(pdf)
    by_page = collections.defaultdict(list)
    for item in items:
        by_page[item["page"]].append(item)

    rows = collections.defaultdict(list)  # 쪽 → 대표 분량표 이름들
    for name, (_, _, source, _) in parse_portions(read_source(None)).items():
        match = re.fullmatch(re.escape(GUIDE_URL) + r"#page=(\d+)", source)
        if match:
            rows[int(match.group(1))].append(name)

    database = sqlite3.connect(f"file:{DATA / 'FoodCatalog.sqlite'}?mode=ro", uri=True)
    foods = [row for row in database.execute(
        "SELECT id, name, basis_unit, calories FROM foods WHERE brand = '' AND category != '가공식품' AND basis_unit = 'g'")
        if row[0] not in QUARANTINED]
    database.close()
    referenced = collections.defaultdict(set)
    for entry in json.loads((DATA / "FoodReferences.json").read_text(encoding="utf-8")):
        if entry["amountUnit"] == "g":
            referenced[normalized(entry["referenceName"])].add(entry["referenceID"])

    entries, report = [], {"rows": 0, "noGuideItem": [], "noMatch": [], "multiple": [], "referenceWins": []}
    for page, names in sorted(rows.items()):
        report["rows"] += 1
        guide = next((item for item in by_page.get(page, []) if normalized(item["name"]) in {normalized(name) for name in names}), None)
        if guide is None:
            report["noGuideItem"].append((page, names, [item["name"] for item in by_page.get(page, [])]))
            continue
        keys = {normalized(name) for name in names} | {normalized(guide["name"])}
        matched = collections.defaultdict(list)
        for food_id, name, unit, calories in foods:
            if same_dish_names(name) & keys and abs(calories / guide["kcalPer100"] - 1) <= TOLERANCE:
                matched[normalized(name)].append((food_id, name, unit, calories))
        if not matched:
            report["noMatch"].append((page, guide["number"], guide["name"], guide["kcalPer100"]))
            continue
        for key, candidates in sorted(matched.items()):
            candidates.sort(key=lambda food: (abs(food[3] - guide["kcalPer100"]), food[0]))
            if len(candidates) > 1:
                report["multiple"].append((guide["name"], [food[0] for food in candidates]))
            food_id, name, unit, calories = candidates[0]
            if referenced.get(key) and food_id not in referenced[key]:
                report["referenceWins"].append((name, sorted(referenced[key]), food_id))
                continue
            entries.append({
                "name": name, "amountUnit": unit, "foodID": food_id,
                "guidePage": page, "guideItem": guide["number"], "guideName": guide["name"],
                "guideKcalPer100g": guide["kcalPer100"], "foodKcalPer100g": calories,
                "differencePercent": round((calories / guide["kcalPer100"] - 1) * 100, 1),
            })
    entries.sort(key=lambda entry: (entry["guidePage"], entry["name"]))
    document = {
        "_readme": [
            "대표 분량 출처와 영양 자료를 맞추기 위한 대표 자료 지정 표(2026-11-19 결정). 화면에 쓰지 않는 내부 근거다.",
            "대표 분량표(FoodPortion.swift)의 출처가 식약처 「외식 영양성분 자료집 제2권」(2013, guideSource)인 음식은 자료집의 100g당 열량과 ±2% 안에서 맞는 g 기준 DB 자료(브랜드 없음, 가공식품 아님)를 대표 자료로 쓴다. 없으면 지정하지 않고 앱은 priority, 기준일, 식품코드 순을 유지한다.",
            "앱 적용: 검색의 같은 이름·단위 일반 음식 중 하나를 남길 때 참고표(FoodReferences.json) 지정 다음으로 foodID를 먼저 둔다. D3 등 앞자리를 일반적으로 우선하지 않고, mL 자료는 비교하지 않는다.",
            "생성: python3 -B Scripts/build_guide_representatives.py <자료집 PDF>. 자료집 PDF는 저장소에 넣지 않는다(출처 기록은 Docs/FoodCatalogImport.json의 guideRepresentatives).",
            f"자료집: {GUIDE_URL}, SHA-256 {GUIDE_SHA256}, {pages}쪽, 항목 {len(items)}개(1회 제공량 모두 g).",
        ],
        "entries": entries,
    }
    return document, report, pages, items


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    document, report, pages, items = build(Path(argv[1]))
    text = json.dumps(document, ensure_ascii=False, indent=2) + "\n"
    print(f"자료집 {pages}쪽, 항목 {len(items)}개. 대표 분량표 자료집 행(쪽) {report['rows']}개, 지정 {len(document['entries'])}개")
    print(f"자료집 항목을 찾지 못한 쪽 {len(report['noGuideItem'])}: {report['noGuideItem']}")
    print(f"±2% 안의 g 자료 없음 {len(report['noMatch'])}: {report['noMatch']}")
    print(f"같은 이름에 맞는 자료 둘 이상(가장 가까운 자료 선택) {len(report['multiple'])}: {report['multiple']}")
    print(f"참고표 지정이 우선해 넣지 않음 {len(report['referenceWins'])}: {report['referenceWins']}")
    if "--check" in argv:
        same = OUTPUT.exists() and OUTPUT.read_text(encoding="utf-8") == text
        print("데이터 파일과 같음" if same else "데이터 파일과 다름")
        return 0 if same else 1
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"저장: {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
