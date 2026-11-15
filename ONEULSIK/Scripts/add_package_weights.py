"""기존 FoodCatalog.sqlite의 foods 테이블에 가공식품 원본의 제품 정보를 덧붙인다.

DB를 다시 만들지 않는다. build_food_catalog.py로 만든 DB(또는 이 스크립트를 이미 실행한 DB)에
식약처 가공식품 원본을 한 번 읽어 다음을 처리한다. 연결 키는 식품코드 = foods.id.

- package_amount, package_unit: `식품중량`이 `숫자+g` 또는 `숫자+ml` 형태일 때만 채운다.
  `1회 섭취참고량`은 대체값으로 쓰지 않는다. 원문 열(package_raw)은 두지 않는다(있으면 제거).
- category_code: `식품대분류명`·`식품중분류명`·`식품소분류명` 조합의 정수 코드.
  조합 이름은 별도 표 food_categories(code, major, middle, minor)에 한 번만 저장한다.
- 앱 쿼리가 쓰지 않는 food_display_order 인덱스는 제거한다.

실행 전후 기존 14개 열·영양 열의 해시를 비교하고, 이미 제품 중량 열이 있던 DB라면
package_amount·package_unit 해시도 같아야 한다. 결과 크기가 --max-bytes 이상이면 교체하지 않는다.

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
PACKAGE_HASH_COLUMNS = ("id", "package_amount", "package_unit")
ADDED_COLUMNS = (("package_amount", "REAL"), ("package_unit", "TEXT"), ("category_code", "INTEGER"))
REMOVED_COLUMNS = ("package_raw",)
REMOVED_INDEXES = ("food_display_order",)
CATEGORY_HEADERS = ("식품대분류명", "식품중분류명", "식품소분류명")
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
    for row in connection.execute(f"SELECT {', '.join(columns)} FROM foods ORDER BY id"):
        digest.update(repr(row).encode())
        digest.update(b"\n")
    return digest.hexdigest()


def text(value):
    return str(value).strip() if value is not None else ""


def source_rows(path):
    book = openpyxl.load_workbook(path, read_only=True, data_only=True)
    try:
        for sheet in book:
            iterator = sheet.values
            headers = next(iterator)
            needed = ("식품코드", "식품중량", *CATEGORY_HEADERS)
            missing = [name for name in needed if name not in headers]
            if missing:
                raise SystemExit(f"{path.name}: 원본에 열이 없습니다: {missing}")
            index = {name: headers.index(name) for name in needed}
            for values in iterator:
                yield (text(values[index["식품코드"]]), text(values[index["식품중량"]]),
                       tuple(text(values[index[name]]) for name in CATEGORY_HEADERS))
    finally:
        book.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, help="식약처 가공식품 원본 xlsx")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--max-bytes", type=int, default=90_000_000, help="결과 DB 크기 상한(이상이면 교체하지 않음)")
    args = parser.parse_args()

    with args.source.open("rb") as source_file:
        checksum = hashlib.file_digest(source_file, "sha256").hexdigest()
    size_before = args.db.stat().st_size

    working = args.db.with_suffix(".updating.sqlite")
    shutil.copyfile(args.db, working)
    connection = sqlite3.connect(working)
    try:
        existing = {row[1] for row in connection.execute("PRAGMA table_info(foods)")}
        missing = [column for column in ORIGINAL_COLUMNS if column not in existing]
        if missing:
            raise SystemExit(f"foods 테이블에 기존 열이 없습니다: {missing}")
        had_package = {"package_amount", "package_unit"} <= existing
        before = {"all": table_hash(connection, ORIGINAL_COLUMNS), "nutrition": table_hash(connection, NUTRITION_COLUMNS)}
        if had_package:
            before["package"] = table_hash(connection, PACKAGE_HASH_COLUMNS)

        for index in REMOVED_INDEXES:
            connection.execute(f"DROP INDEX IF EXISTS {index}")
        for column in REMOVED_COLUMNS:
            if column in existing:
                connection.execute(f"ALTER TABLE foods DROP COLUMN {column}")
        for column, kind in ADDED_COLUMNS:
            if column not in existing:
                connection.execute(f"ALTER TABLE foods ADD COLUMN {column} {kind}")
        connection.execute("UPDATE foods SET package_amount = NULL, package_unit = NULL, category_code = NULL")
        connection.execute("DROP TABLE IF EXISTS food_categories")
        connection.execute("""CREATE TABLE food_categories (
            code INTEGER PRIMARY KEY, major TEXT NOT NULL, middle TEXT NOT NULL, minor TEXT NOT NULL,
            UNIQUE (major, middle, minor))""")

        basis_units = dict(connection.execute("SELECT id, basis_unit FROM foods"))
        stats = collections.Counter()
        unparsed = collections.Counter()
        seen = set()
        weights = []
        categories = {}
        for code, raw, category in source_rows(args.source):
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
            categories[code] = category
            if not raw:
                stats["linked_empty_weight"] += 1
            else:
                amount, unit = parse_weight(raw)
                if amount is None:
                    stats["linked_unparsed_weight"] += 1
                    unparsed[raw] += 1
                else:
                    stats[f"linked_weight_{unit}"] += 1
                    if unit != basis_units[code].lower():
                        stats["linked_weight_unit_differs_from_basis"] += 1
                    weights.append((amount, unit, code))
            if stats["source_rows"] % 50000 == 0:
                print(dict(stats), flush=True)

        codes = {combination: number for number, combination in enumerate(sorted(set(categories.values())), 1)}
        connection.executemany("INSERT INTO food_categories VALUES (?, ?, ?, ?)",
                               [(number, *combination) for combination, number in codes.items()])
        connection.executemany("UPDATE foods SET package_amount = ?, package_unit = ? WHERE id = ?", weights)
        connection.executemany("UPDATE foods SET category_code = ? WHERE id = ?",
                               [(codes[combination], code) for code, combination in categories.items()])
        connection.commit()

        after = {"all": table_hash(connection, ORIGINAL_COLUMNS), "nutrition": table_hash(connection, NUTRITION_COLUMNS)}
        if had_package:
            after["package"] = table_hash(connection, PACKAGE_HASH_COLUMNS)
        if before != after:
            changed = [key for key in before if before[key] != after.get(key)]
            raise SystemExit(f"해시가 달라졌습니다({changed}). 원본 DB를 교체하지 않습니다.")
        if not had_package:
            after["package"] = table_hash(connection, PACKAGE_HASH_COLUMNS)
        catalog_rows = connection.execute("SELECT COUNT(*) FROM foods").fetchone()[0]
        with_amount = connection.execute("SELECT COUNT(*) FROM foods WHERE package_amount IS NOT NULL").fetchone()[0]
        with_category = connection.execute("SELECT COUNT(*) FROM foods WHERE category_code IS NOT NULL").fetchone()[0]
        indexes = [row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type = 'index'")]
        connection.execute("VACUUM")
        connection.close()
        size_after = working.stat().st_size
        if size_after >= args.max_bytes:
            raise SystemExit(f"결과 크기 {size_after:,}바이트가 상한 {args.max_bytes:,}바이트 이상입니다. 원본 DB를 교체하지 않습니다.")
    except BaseException:
        connection.close()
        working.unlink(missing_ok=True)
        raise

    working.replace(args.db)

    report = json.loads(args.report.read_text()) if args.report.exists() else {}
    report.pop("packageWeights", None)
    report["productDetails"] = {
        "source": {"file": args.source.name, "sha256": checksum, "columns": ["식품중량", *CATEGORY_HEADERS]},
        "rule": "식품코드 = foods.id. 식품중량이 숫자+g 또는 숫자+ml일 때만 package_amount/package_unit을 채움(1회 섭취참고량 미사용). "
                "대·중·소분류 조합은 food_categories의 정수 코드(category_code)로 연결",
        "catalogRows": catalog_rows,
        "rowsWithPackageAmount": with_amount,
        "rowsWithCategory": with_category,
        "categoryCombinations": len(codes),
        "counts": dict(sorted(stats.items())),
        "topUnparsedWeights": [{"raw": raw, "count": count} for raw, count in unparsed.most_common(20)],
        "removed": {"columns": list(REMOVED_COLUMNS), "indexes": list(REMOVED_INDEXES)},
        "remainingIndexes": indexes,
        "sizeBytes": {"before": size_before, "after": size_after, "limit": args.max_bytes},
        "sha256": {"existingColumns": after["all"], "nutrition": after["nutrition"], "package": after["package"],
                   "verifiedUnchanged": sorted(before)},
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["productDetails"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
