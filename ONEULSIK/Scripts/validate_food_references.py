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
            if row["brand"] or row["category"] != entry.get("category", "음식"):
                raise ValueError(f"Not a general food of the declared category: {entry['name']}")
            if any(not math.isfinite(row[column]) or row[column] < 0 for column in ("calories", "carbohydrates", "protein", "fat")):
                raise ValueError(f"Invalid nutrition: {entry['name']}")
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
