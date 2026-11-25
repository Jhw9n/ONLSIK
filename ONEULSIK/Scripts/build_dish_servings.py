#!/usr/bin/env python3
"""식약처 음식 DB 원본의 식품중량(1인분 중량)을 대표 분량 데이터 파일로 만든다(2026-11-24, #43).

원본: 식품의약품안전처 식품영양성분 DB, 음식(xlsx). FoodCatalog.sqlite를 만들 때 쓴 파일과 같은지 SHA-256으로 확인한다.
출력: ONEULSIK/Resource/Data/DishServings.json (식품코드 → [1인분 중량, 단위])

규칙
- 번들 DB(FoodCatalog.sqlite, 읽기 전용)에 있는 식품코드만 쓴다.
- 식품중량이 `숫자+g` 또는 `숫자+ml` 형태일 때만 쓴다. 그 밖의 형태(빈칸 포함)는 버린다.
- 단위가 DB 레코드의 기준 단위(basis_unit, g 또는 mL)와 다르면 버린다.
- 중량이 영양성분 기준량(DB 기준 100g·100mL)과 같으면 버린다. 쌀밥·팟타이·고기만두·마라탕처럼 1인분이 아닌 값이
  기준량을 그대로 적은 경우가 많아서다(원본 확인 결과).
- 1,000g 이상(여러 인분 포장·피자 한 판 등)은 파일에는 남기고, 앱이 기존 1인분 상한(MealPortionEstimate.isPlausible)으로 거른다.
- 찌개류: DB 이름(공백 제거)이 "찌개"로 끝나는 레코드는 1인분 중량이 400 미만이면 400으로 한다(g·mL 모두, 영양 기준량과 같은 100도 포함).
  내부 기준 "찌개류 외식 1인분 400g 준용"(김치찌개·순두부찌개 식약처 외식 자료 400g, 콩비지찌개 외식 영양성분 자료집 제2권 95쪽 400g,
  2026-11-25 사용자 결정, #43). 실기기에서 동태찌개·청국장찌개가 식품중량 200g으로 88~94kcal였다.

사용법(프로젝트 폴더 ONEULSIK에서, openpyxl 필요):
  python3 -B Scripts/build_dish_servings.py <식약처_음식_DB.xlsx> [--check]
--check는 파일을 쓰지 않고 기존 파일과 같은지만 확인한다(같으면 종료 코드 0).
"""
import argparse
import collections
import hashlib
import json
import re
import sqlite3
import sys
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[1]
DATABASE = ROOT / "ONEULSIK/Resource/Data/FoodCatalog.sqlite"
OUTPUT = ROOT / "ONEULSIK/Resource/Data/DishServings.json"
EXPECTED_SHA256 = "1ef3551f9a1d0ee87891d6306fa22bbd6a7ffcc90f2c70a4a184dbfe3fce6ea6"  # Docs/FoodCatalogImport.json의 음식 원본
STEW_MINIMUM = 400  # 찌개류 외식 1인분 400g 준용(내부 기준, 2026-11-25)
WEIGHT = re.compile(r"(\d+(?:\.\d+)?)\s*(g|ml)", re.IGNORECASE)


def number(value):
    return int(value) if float(value).is_integer() else round(float(value), 2)


def build(source):
    with source.open("rb") as handle:
        digest = hashlib.file_digest(handle, "sha256").hexdigest()
    if digest != EXPECTED_SHA256:
        sys.exit(f"원본 SHA-256이 다릅니다: {digest} (기대: {EXPECTED_SHA256})")
    database = sqlite3.connect(f"file:{DATABASE}?mode=ro", uri=True)
    foods = {row[0]: row[1] for row in database.execute("select id, basis_unit from foods")}
    names = {row[0]: row[1] for row in database.execute("select id, name from foods where id like 'D%'")}
    database.close()

    counts = collections.Counter()
    servings = {}
    book = openpyxl.load_workbook(source, read_only=True, data_only=True)
    for sheet in book:
        rows = sheet.values
        headers = next(rows)
        for values in rows:
            row = dict(zip(headers, values))
            counts["sourceRows"] += 1
            food_id = str(row.get("식품코드") or "").strip()
            if food_id not in foods:
                counts["notInCatalog"] += 1
                continue
            counts["catalogRows"] += 1
            match = WEIGHT.fullmatch(str(row.get("식품중량") or "").strip())
            if not match:
                counts["droppedFormat"] += 1
                continue
            amount = float(match.group(1))
            unit = "g" if match.group(2).lower() == "g" else "mL"
            if unit != foods[food_id]:
                counts["droppedUnitMismatch"] += 1
                continue
            if amount <= 0:
                counts["droppedFormat"] += 1
                continue
            if names.get(food_id, "").replace(" ", "").endswith("찌개") and amount < STEW_MINIMUM:
                counts["stewRaisedTo400"] += 1
                if amount == 100:
                    counts["stewRaisedFromBasisAmount"] += 1
                amount = STEW_MINIMUM
            if amount == 100:
                counts["droppedBasisAmount"] += 1
                continue
            counts["kept"] += 1
            if amount >= 1000:
                counts["keptAtLeast1000"] += 1
            servings[food_id] = [number(amount), unit]
    book.close()
    return digest, counts, dict(sorted(servings.items()))


def render(digest, source_name, counts, servings):
    header = {
        "source": {
            "title": "식품의약품안전처 식품영양성분 DB, 음식",
            "url": "https://various.foodsafetykorea.go.kr/nutrient/general/down/list.do",
            "version": "2026-08-28",
            "file": source_name,
            "sha256": digest,
            "column": "식품중량",
        },
        "displayText": "식약처 음식 DB 1인분 중량 기준",
        "basisNote": "음식 DB 원본의 식품중량을 1인분·1그릇 대표 분량으로 쓴다(2026-11-24 결정, #43). "
                     "숫자+g/ml 형태이고 DB 기준 단위와 같은 값만 쓰며, 영양성분 기준량과 같은 100은 1인분 정보가 아닌 경우가 많아 뺐다. "
                     "이름이 찌개로 끝나는 레코드는 400 미만이면 400으로 한다(내부 기준: 찌개류 외식 1인분 400g 준용, 2026-11-25 결정). "
                     "생성: Scripts/build_dish_servings.py",
        "counts": dict(sorted(counts.items())),
    }
    lines = json.dumps(header, ensure_ascii=False, indent=2)[:-2] + ',\n  "servings": {\n'
    entries = [f'    "{food_id}": {json.dumps(value, ensure_ascii=False)}' for food_id, value in servings.items()]
    return lines + ",\n".join(entries) + "\n  }\n}\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    digest, counts, servings = build(args.source)
    text = render(digest, args.source.name, counts, servings)
    json.loads(text)
    for key, value in sorted(counts.items()):
        print(f"{key}: {value}")
    if args.check:
        same = OUTPUT.exists() and OUTPUT.read_text(encoding="utf-8") == text
        print("기존 파일과 같음" if same else "기존 파일과 다름")
        sys.exit(0 if same else 1)
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"{OUTPUT.relative_to(ROOT)}: {OUTPUT.stat().st_size} bytes, {len(servings)} entries")


if __name__ == "__main__":
    main()
