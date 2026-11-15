"""기존 FoodCatalog.sqlite의 foods 테이블에 제품 총중량 열을 덧붙인다.

DB를 다시 만들지 않는다. 식약처 가공식품 원본의 `식품중량` 열만 읽어서
식품코드 = foods.id로 연결하고, 다음 세 열을 채운다.

- package_amount: 숫자 (원문이 `숫자+g` 또는 `숫자+ml` 형태일 때만)
- package_unit:   "g" 또는 "ml" (위와 같은 조건)
- package_raw:    원문 그대로 (형태와 무관하게 보존)

`1회 섭취참고량`은 대체값으로 쓰지 않는다. 기존 열은 건드리지 않으며,
실행 전후 기존 열 전체의 해시가 같은지 검증한 뒤에만 원본 DB를 교체한다.

사용 예:
    python3 Scripts/add_package_weights.py ~/Downloads/식약처_가공식품_DB_2026-09-29.xlsx
"""

import argparse
import collections
import hashlib
import json
import math
import re
import shutil
import sqlite3
import unicodedata
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = ROOT / "ONEULSIK/Resource/Data/FoodCatalog.sqlite"
DEFAULT_REPORT = ROOT / "Docs/FoodCatalogImport.json"
ORIGINAL_COLUMNS = (
    "id", "name", "brand", "category", "basis_unit",
    "calories", "carbohydrates", "protein", "fat",
    "source", "source_date", "name_key", "brand_key", "priority",
)
NUTRITION_COLUMNS = ("id", "basis_unit", "calories", "carbohydrates", "protein", "fat")
PACKAGE_COLUMNS = (("package_amount", "REAL"), ("package_unit", "TEXT"), ("package_raw", "TEXT"))
WEIGHT = re.compile(r"(\d+(?:\.\d+)?)\s*(g|ml)", re.IGNORECASE)


def parse_weight(raw):
    """`숫자+g` / `숫자+ml` 형태만 받는다. 그 밖의 표기는 (None, None)."""
    value = unicodedata.normalize("NFKC", raw).strip()
    match = WEIGHT.fullmatch(value)
    if not match:
        return None, None
    amount = float(match.group(1))
    if not math.isfinite(amount) or amount <= 0:
        return None, None
    return amount, match.group(2).lower()


def table_hash(connection, columns):
    digest = hashlib.sha256()
    query = f"SELECT {', '.join(columns)} FROM foods ORDER BY id"
    for row in connection.execute(query):
        digest.update(repr(row).encode())
        digest.update(b"\n")
    return digest.hexdigest()


def source_weights(path):
    book = openpyxl.load_workbook(path, read_only=True, data_only=True)
    try:
        for sheet in book:
            iterator = sheet.values
            headers = next(iterator)
            if "식품코드" not in headers or "식품중량" not in headers:
                raise SystemExit(f"{path.name}: 식품코드 또는 식품중량 열이 없습니다")
            code_index = headers.index("식품코드")
            weight_index = headers.index("식품중량")
            for values in iterator:
                code = values[code_index]
                weight = values[weight_index]
                yield (str(code).strip() if code is not None else "",
                       str(weight).strip() if weight is not None else "")
    finally:
        book.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, help="식약처 가공식품 원본 xlsx")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    with args.source.open("rb") as source_file:
        checksum = hashlib.file_digest(source_file, "sha256").hexdigest()

    working = args.db.with_suffix(".packaging.sqlite")
    shutil.copyfile(args.db, working)
    connection = sqlite3.connect(working)
    try:
        existing = {row[1] for row in connection.execute("PRAGMA table_info(foods)")}
        missing = [column for column in ORIGINAL_COLUMNS if column not in existing]
        if missing:
            raise SystemExit(f"foods 테이블에 기존 열이 없습니다: {missing}")
        before_all = table_hash(connection, ORIGINAL_COLUMNS)
        before_nutrition = table_hash(connection, NUTRITION_COLUMNS)

        for column, kind in PACKAGE_COLUMNS:
            if column not in existing:
                connection.execute(f"ALTER TABLE foods ADD COLUMN {column} {kind}")
        connection.execute("UPDATE foods SET package_amount = NULL, package_unit = NULL, package_raw = NULL")

        basis_units = dict(connection.execute("SELECT id, basis_unit FROM foods"))
        stats = collections.Counter()
        unparsed = collections.Counter()
        seen = set()
        updates = []
        for code, raw in source_weights(args.source):
            stats["source_rows"] += 1
            if not code:
                stats["source_missing_code"] += 1
                continue
            if code in seen:
                stats["source_duplicate_code"] += 1
                continue
            seen.add(code)
            if code not in basis_units:
                stats["not_in_catalog"] += 1
                continue
            stats["linked"] += 1
            if not raw:
                stats["linked_empty_weight"] += 1
                continue
            amount, unit = parse_weight(raw)
            if amount is None:
                stats["linked_unparsed_weight"] += 1
                unparsed[raw] += 1
            else:
                stats[f"linked_weight_{unit}"] += 1
                if unit != basis_units[code].lower():
                    stats["linked_weight_unit_differs_from_basis"] += 1
            updates.append((amount, unit, raw, code))
            if stats["source_rows"] % 50000 == 0:
                print(dict(stats), flush=True)
        connection.executemany(
            "UPDATE foods SET package_amount = ?, package_unit = ?, package_raw = ? WHERE id = ?", updates)
        connection.commit()

        after_all = table_hash(connection, ORIGINAL_COLUMNS)
        after_nutrition = table_hash(connection, NUTRITION_COLUMNS)
        if (before_all, before_nutrition) != (after_all, after_nutrition):
            raise SystemExit("기존 열의 해시가 달라졌습니다. 원본 DB를 교체하지 않습니다.")
        catalog_rows = connection.execute("SELECT COUNT(*) FROM foods").fetchone()[0]
        with_amount = connection.execute("SELECT COUNT(*) FROM foods WHERE package_amount IS NOT NULL").fetchone()[0]
        connection.execute("VACUUM")
    except BaseException:
        connection.close()
        working.unlink(missing_ok=True)
        raise
    connection.close()

    working.replace(args.db)

    report = json.loads(args.report.read_text()) if args.report.exists() else {}
    report["packageWeights"] = {
        "source": {"file": args.source.name, "sha256": checksum, "column": "식품중량"},
        "rule": "식품코드 = foods.id, 식품중량이 숫자+g 또는 숫자+ml일 때만 package_amount/package_unit을 채움. 1회 섭취참고량은 사용하지 않음",
        "catalogRows": catalog_rows,
        "rowsWithPackageAmount": with_amount,
        "counts": dict(sorted(stats.items())),
        "topUnparsedWeights": [{"raw": raw, "count": count} for raw, count in unparsed.most_common(20)],
        "existingColumnsSha256": {"all": before_all, "nutrition": before_nutrition, "unchanged": True},
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["packageWeights"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
