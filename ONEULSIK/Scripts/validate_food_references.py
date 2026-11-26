import json
import math
import re
import sqlite3
import unicodedata
from pathlib import Path


SPELLING = json.loads((Path(__file__).resolve().parents[1] / "ONEULSIK/Resource/Data/SpellingVariants.json").read_text())["entries"]


def normalized(value):
    """앱의 FoodReferenceCatalog.normalized와 같은 규칙(표기 변형은 SpellingVariants.json)."""
    value = unicodedata.normalize("NFKC", value).lower()
    for entry in SPELLING:
        for variant in entry["variants"]:
            value = re.sub(r"\s*".join(map(re.escape, variant.replace(" ", ""))), entry["standard"], value)
    return "".join(character for character in value if character.isalnum())


def main():
    root = Path(__file__).resolve().parents[1]
    folder = root / "ONEULSIK/Resource/Data"
    entries = json.loads((folder / "FoodReferences.json").read_text())
    aliases = {}
    with sqlite3.connect(f"file:{folder / 'FoodCatalog.sqlite'}?mode=ro", uri=True) as database:
        database.row_factory = sqlite3.Row
        for entry in entries:
            row = database.execute("SELECT * FROM foods WHERE id = ?", (entry["referenceID"],)).fetchone()
            if row is None:
                raise ValueError(f"Missing reference: {entry['name']}")
            for field, column in [("referenceName", "name"), ("amountUnit", "basis_unit"), ("source", "source"), ("sourceDate", "source_date")]:
                if entry[field] != row[column]:
                    raise ValueError(f"Changed reference {entry['name']}: {field}")
            # allowsBrandedProduct(기본 false, #43)가 true인 항목만 업체 제품(brand 있는 레코드)을 가리킬 수 있다(앱의 FoodReference.matches와 같은 규칙).
            allows_branded = entry.get("allowsBrandedProduct", False)
            if not isinstance(allows_branded, bool):
                raise ValueError(f"Invalid allowsBrandedProduct: {entry['name']}")
            if (row["brand"] and not allows_branded) or row["category"] != entry.get("category", "음식"):
                raise ValueError(f"Not a general food of the declared category: {entry['name']}")
            if any(not math.isfinite(row[column]) or row[column] < 0 for column in ("calories", "carbohydrates", "protein", "fat")):
                raise ValueError(f"Invalid nutrition: {entry['name']}")
            # 같은 이름 '음식' 자료의 가운데 값(#51): 음식 DB에서 다시 계산해 같아야 한다(단위가 섞이면 없어야 한다).
            if "sameNameMedian" in entry:
                same = database.execute(
                    "SELECT * FROM foods WHERE category = '음식' AND brand = '' AND name = ?", (row["name"],)).fetchall()
                units = {item["basis_unit"] for item in same}
                ordered = sorted(same, key=lambda item: (item["calories"], item["id"]))
                middle = len(ordered) // 2
                picked = ordered[middle:middle + 1] if len(ordered) % 2 else ordered[middle - 1:middle + 1]
                median = entry["sameNameMedian"]
                expected = {column: round(sum(item[column] for item in picked) / len(picked), 4)
                            for column in ("calories", "carbohydrates", "protein", "fat")}
                if (len(same) < 2 or len(units) != 1 or median["unit"] != entry["amountUnit"] or median["count"] != len(same)
                        or any(abs(median[column] - value) > 1e-6 for column, value in expected.items())):
                    raise ValueError(f"Invalid sameNameMedian: {entry['name']}")
            for unit, amount in entry.get("estimatedPortions", {}).items():
                if unit not in {"인분", "그릇", "접시"} or not isinstance(amount, (int, float)) or not math.isfinite(amount) or not 0.1 <= amount <= 5000:
                    raise ValueError(f"Invalid estimated portion: {entry['name']}")
            for alias in [entry["name"], *entry["aliases"]]:
                key = normalized(alias)
                if not key or (key in aliases and aliases[key] != entry["name"]):
                    raise ValueError(f"Conflicting alias: {alias}")
                aliases[key] = entry["name"]
    print(f"Validated {len(entries)} references and {len(aliases)} normalized names; source records unchanged.")


if __name__ == "__main__":
    main()
