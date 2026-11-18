#!/usr/bin/env python3
"""같은 요리의 g 기준 항목과 mL 기준 항목을 짝지어, mL 값을 g처럼 쓸 때 열량이 얼마나 다른지 비교한다(읽기 전용).

- 쌍: 브랜드 없음, 가공식품 아님. 정규화한 이름(앱의 FoodReferenceCatalog.normalized와 같은 규칙,
  표기 변형은 SpellingVariants.json)이 같은 g 항목과 mL 항목이 모두 있는 이름 하나가 한 쌍이다.
  같은 이름에 항목이 여러 개면 쪽마다 열량의 중앙값을 쓴다.
- 비교 값: (100mL당 열량 / 100g당 열량) - 1. 음수면 mL 값을 g처럼 쓸 때 열량이 낮게 나온다.
  100g당 열량이 0인 쌍은 뺀다.
- 국물·면 집단: Resource/Data/VolumeAsWeight.json(앱과 같은 표). DB 이름에서 괄호 안을 빼고 공백·쉼표로 나눈
  조각 중 하나가 suffixes의 끝말로 끝나면 국물·면. includeNames는 넣고 excludeNames는 뺀다.
- DB는 읽기 전용(mode=ro)으로 연다.

사용법: python3 Scripts/compare_volume_weight_pairs.py [--list]
"""
import json
import re
import sqlite3
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_food_references import normalized  # noqa: E402

DATA = Path(__file__).resolve().parents[1] / "ONEULSIK/Resource/Data"


def load_rule():
    rule = json.loads((DATA / "VolumeAsWeight.json").read_text(encoding="utf-8"))
    return (rule["suffixes"], {normalized(name) for name in rule["includeNames"]},
            {normalized(name) for name in rule["excludeNames"]})


def is_soup_or_noodle(name, rule):
    suffixes, include, exclude = rule
    key = normalized(name)
    if key in exclude:
        return False
    if key in include:
        return True
    words = [word for word in re.split(r"[\s,]+", re.sub(r"\([^)]*\)", " ", name)) if word]
    return any(word.endswith(suffix) for word in words for suffix in suffixes)


def pairs():
    database = sqlite3.connect(f"file:{DATA / 'FoodCatalog.sqlite'}?mode=ro", uri=True)
    rows = database.execute(
        "SELECT name, basis_unit, calories FROM foods WHERE brand = '' AND category != '가공식품'").fetchall()
    database.close()
    grams, milliliters, names = {}, {}, {}
    for name, unit, calories in rows:
        key = normalized(name)
        names.setdefault(key, name)
        (milliliters if unit == "mL" else grams).setdefault(key, []).append(calories)
    result = []
    for key in sorted(set(grams) & set(milliliters)):
        gram_value, milliliter_value = statistics.median(grams[key]), statistics.median(milliliters[key])
        if gram_value > 0:
            result.append((names[key], gram_value, milliliter_value, milliliter_value / gram_value - 1))
    return result


def summary(label, values):
    q1, median, q3 = statistics.quantiles(values, n=4)
    return f"{label}: {len(values)}쌍, 중앙값 {median * 100:+.1f}%, 사분위 {q1 * 100:+.1f}% ~ {q3 * 100:+.1f}%"


def main(argv):
    rule = load_rule()
    found = pairs()
    soup = [item for item in found if is_soup_or_noodle(item[0], rule)]
    other = [item for item in found if not is_soup_or_noodle(item[0], rule)]
    print(f"쌍 {len(found)}개 (100mL당 열량 / 100g당 열량 - 1)")
    print(summary("국물·면", [item[3] for item in soup]))
    print(summary("그 외", [item[3] for item in other]))
    if "--list" in argv:
        for label, group in (("국물·면", soup), ("그 외", other)):
            for name, gram_value, milliliter_value, ratio in group:
                print(f"{label}\t{name}\t{gram_value:g}\t{milliliter_value:g}\t{ratio * 100:+.1f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
