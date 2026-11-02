import argparse
import collections
import datetime
import hashlib
import json
import math
import re
import sqlite3
import unicodedata
from pathlib import Path

import openpyxl


def normalized(value):
    result = re.sub(r"[\W_]", "", unicodedata.normalize("NFKC", value).lower())
    return result.replace("계란", "달걀").replace("자장", "짜장").replace("흰쌀밥", "쌀밥").replace("돈까스", "돈가스")


def text(value):
    if value is None:
        return ""
    if isinstance(value, (datetime.date, datetime.datetime)):
        return value.strftime("%Y-%m-%d")
    return str(value).strip()


def number(value):
    value = text(value)
    if not re.fullmatch(r"\d+(?:\.\d+)?", value):
        return None
    result = float(value)
    return result if math.isfinite(result) and result >= 0 else None


def mfds_rows(path):
    book = openpyxl.load_workbook(path, read_only=True, data_only=True)
    for sheet in book:
        iterator = sheet.values
        headers = next(iterator)
        for values in iterator:
            row = dict(zip(headers, values))
            yield {
                "id": text(row.get("식품코드")),
                "name": text(row.get("식품명")),
                "brand": text(row.get("업체명") or row.get("제조사명")),
                "category": text(row.get("데이터구분명")),
                "basis": text(row.get("영양성분함량기준량")),
                "calories": row.get("에너지(kcal)"),
                "carbohydrates": row.get("탄수화물(g)"),
                "protein": row.get("단백질(g)"),
                "fat": row.get("지방(g)"),
                "source": text(row.get("출처명")),
                "source_date": text(row.get("데이터기준일자")),
                "origin": text(row.get("식품기원명")),
                "method": text(row.get("데이터생성방법명")),
                "representative": text(row.get("대표식품명")),
            }
    book.close()


def rda_rows(path):
    book = openpyxl.load_workbook(path, read_only=True, data_only=True)
    codes = {row[0]: row[1] for row in book["부록2)식품코드,국문명,영문명,학명 정보 "].iter_rows(min_row=2, values_only=True)}
    for values in book["국가표준식품성분 Database 10.4"].iter_rows(min_row=4, values_only=True):
        if not values[0]:
            continue
        yield {
            "id": "RDA-" + text(codes[values[0]]) if codes.get(values[0]) else "",
            "name": text(values[3]), "brand": "", "category": "원재료성 식품",
            "basis": "100g", "calories": values[5], "carbohydrates": values[10],
            "protein": values[7], "fat": values[8],
            "source": "농촌진흥청 국가표준식품성분 DB 10.4 (2026)",
            "source_date": "2026-04-28", "origin": text(values[4]),
            "method": "", "representative": text(values[3]).split(",")[0],
        }
    book.close()


def convert(row, stats):
    stats["input"] += 1
    nutrients = [number(row[key]) for key in ("calories", "carbohydrates", "protein", "fat")]
    if any(value is None for value in nutrients):
        stats["missing_or_invalid_nutrition"] += 1
        return None
    basis = row["basis"].lower().replace(" ", "")
    if basis not in ("100g", "100ml"):
        stats["unsupported_basis"] += 1
        return None
    if not row["id"] or not row["name"]:
        stats["missing_identity"] += 1
        return None
    if nutrients[0] > 950 or any(value > 100 for value in nutrients[1:]) or sum(nutrients[1:]) > 105:
        stats["implausible_nutrition"] += 1
        return None
    brand = row["brand"]
    if brand in ("해당없음", "없음", "-", "N/A"):
        brand = ""
    name = re.sub(r"\s+", " ", row["name"].replace("_", " ")).strip()
    priority = 0 if not brand else 2
    if "급식" in row["origin"]:
        priority = 1
    return (
        row["id"], name, brand, row["category"], "g" if basis == "100g" else "mL",
        *nutrients, row["source"], row["source_date"],
        normalized(name), normalized(brand), priority,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mfds", type=Path, nargs="+", required=True)
    parser.add_argument("--rda", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(".building.sqlite")
    temporary.unlink(missing_ok=True)
    connection = sqlite3.connect(temporary)
    connection.execute("""CREATE TABLE foods (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT NOT NULL,
        category TEXT NOT NULL, basis_unit TEXT NOT NULL,
        calories REAL NOT NULL, carbohydrates REAL NOT NULL, protein REAL NOT NULL, fat REAL NOT NULL,
        source TEXT NOT NULL, source_date TEXT NOT NULL,
        name_key TEXT NOT NULL, brand_key TEXT NOT NULL,
        priority INTEGER NOT NULL
    )""")
    connection.execute("PRAGMA user_version = 1")
    sources = []
    inputs = [(path, mfds_rows) for path in args.mfds]
    if args.rda:
        inputs.append((args.rda, rda_rows))
    for path, read_rows in inputs:
        stats = collections.Counter()
        for row in read_rows(path):
            entry = convert(row, stats)
            if entry is not None:
                if connection.execute("INSERT OR IGNORE INTO foods VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", entry).rowcount:
                    stats["accepted"] += 1
                else:
                    stats["duplicate_code"] += 1
            if stats["input"] % 50000 == 0:
                print(path.name, dict(stats), flush=True)
        with path.open("rb") as source_file:
            checksum = hashlib.file_digest(source_file, "sha256").hexdigest()
        sources.append({"file": path.name, "sha256": checksum, "counts": dict(stats)})
        print(path.name, dict(stats), flush=True)
    before_deduplication = connection.execute("SELECT COUNT(*) FROM foods").fetchone()[0]
    connection.execute("""DELETE FROM foods WHERE rowid IN (
        SELECT rowid FROM (
            SELECT rowid, ROW_NUMBER() OVER (
                PARTITION BY name_key, brand_key, basis_unit, calories, carbohydrates, protein, fat
                ORDER BY priority, source_date DESC, id
            ) AS duplicate_rank FROM foods
        ) WHERE duplicate_rank > 1
    )""")
    connection.execute("CREATE INDEX food_display_order ON foods(priority, name, id)")
    connection.commit()
    connection.execute("VACUUM")
    report = {
        "schemaVersion": 1,
        "sources": sources,
        "foodCount": connection.execute("SELECT COUNT(*) FROM foods").fetchone()[0],
        "exactDuplicateCount": before_deduplication - connection.execute("SELECT COUNT(*) FROM foods").fetchone()[0],
        "categories": dict(connection.execute("SELECT category, COUNT(*) FROM foods GROUP BY category")),
        "units": dict(connection.execute("SELECT basis_unit, COUNT(*) FROM foods GROUP BY basis_unit")),
        "popularFoodMatches": {},
    }
    for query in ("쌀밥", "김치찌개", "된장찌개", "비빔밥", "김밥", "라면", "떡볶이", "짜장면", "삼겹살", "닭가슴살", "사과", "바나나", "우유", "아메리카노"):
        report["popularFoodMatches"][query] = connection.execute("SELECT COUNT(*) FROM foods WHERE name_key LIKE ?", ("%" + normalized(query) + "%",)).fetchone()[0]
    connection.close()
    temporary.replace(args.output)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
