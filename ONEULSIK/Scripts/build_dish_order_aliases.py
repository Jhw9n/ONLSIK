#!/usr/bin/env python3
"""식약처 '음식' 자료의 "분류 세부" 이름에서 사용자가 쓰는 "세부분류" 별칭 후보를 만든다(#51).

식약처 음식 DB는 "해장국 선지"처럼 "분류 세부" 순서로 이름을 붙여, 사용자가 쓰는 "선지해장국"(세부+분류)과
글자가 맞지 않는다. 이 스크립트는 띄어쓰기가 하나인 이름에서 "세부분류" 별칭을 만들고 걸러 낸 뒤 결과를 출력한다.
음식 DB(FoodCatalog.sqlite)는 읽기만 한다.

걸러 내는 규칙(뺀 이유를 함께 남긴다)
1. 업체 이름이 있는 자료, 가공식품·원재료는 대상이 아니다(브랜드 없는 '음식' 분류만).
2. 괄호·쉼표·슬래시·가운뎃점·숫자·영문이 있는 이름(상품명·설명이 붙은 이름)
3. 세부가 분류 이름 안에 이미 있거나, 분류가 세부 안에 있거나, 둘이 두 글자 이상 겹침(예: 호박볶음 호박, 홍합탕 홍합만)
4. 세부가 재료 비율·조리 상태 같은 수식어(예: 쌀, 홍합만, 채소만, 국물, 건더기, 생것, 소금제외), 조리에 쓴 양념·기름(기름·고춧가루·소금 등)
4-2. 세부가 요리 이름이면 이미 "재료 요리" 순서라 뺀다(예: 감자 소고기찌개, 가자미 매운탕, 개고기 수육)
5. 별칭이 길다(공백 없이 9글자 넘음)
6. 만든 별칭이 이미 다른 이름이다: 음식 DB의 다른 일반 음식·원재료 이름(브랜드 없음), 참고표(FoodReferences.json) 이름·별칭,
   술 표(DrinkReferences.json) 이름·별칭, 포장제품 표 이름·별칭, 대표 분량표(FoodPortion.swift) 이름
7. 서로 다른 두 이름에서 같은 별칭이 나옴
남은 별칭은 같은 이름의 자료 중 앱 검색이 남기는 하나(대표 자료 지정 표 > priority > 최신 기준일 > 식품코드,
g 자료 우선)를 가리킨다.

사용법:
  python3 -B Scripts/build_dish_order_aliases.py report          # 개수·예시 출력
  python3 -B Scripts/build_dish_order_aliases.py excluded        # 뺀 이름 전체와 이유
  python3 -B Scripts/build_dish_order_aliases.py json            # 참고표 항목 형식(JSON)으로 출력
  python3 -B Scripts/build_dish_order_aliases.py apply           # FoodReferences.json 끝에 넣는다(이 스크립트가 넣은 항목은 바꿔 넣음)
  python3 -B Scripts/build_dish_order_aliases.py check           # FoodReferences.json의 생성 항목이 지금 결과와 같은지(다르면 종료 코드 1)

생성 항목은 basisNote가 GENERATED_PREFIX로 시작한다. 앱은 다른 참고표 항목과 똑같이 쓰고, 테스트 L02(참고표 대표 분량 연결)는
이 항목을 빼고 손으로 넣은 항목만 검사한다(항목이 많아 전체 분석 시간이 크게 늘어서, 2026-11-27 사용자 결정, #51).
"""
import json
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "ONEULSIK/Resource/Data"
SPELLING = json.loads((DATA / "SpellingVariants.json").read_text())["entries"]

# 4번 규칙: 재료 비율·조리 상태 같은 수식어(세부 자리에 오면 "세부분류"가 음식 이름이 되지 않음)
MODIFIER_WORDS = {"쌀", "국물", "건더기", "생것", "익힌것", "삶은것", "데친것", "찐것", "구운것", "마른것", "말린것", "냉동",
                  "혼합", "일반", "기타", "보통", "소", "중", "대", "작은것", "큰것", "반", "전체", "부위",
                  # 조리에 쓴 양념·기름(맛 이름이 아님. 간장·고추장·된장·양념은 '간장게장'처럼 이름이 되므로 남긴다)
                  "기름", "식용유", "참기름", "들기름", "고춧가루", "소금", "설탕", "식초", "깨", "참깨", "후추", "물엿",
                  # 부위(세부가 부위면 "부위+요리"가 다른 요리 이름처럼 읽힘: 간돼지고기, 목닭튀김)
                  "간", "허파", "목", "머리", "날개", "다리", "껍질"}
MODIFIER_SUFFIXES = ("만", "것", "류", "용", "제외", "첨가", "재배")
# 3-2번 규칙: 세부가 요리 이름이면 이미 "재료 요리" 순서다(예: 감자 소고기찌개, 가자미 매운탕, 개고기 수육)
DISH_ENDINGS = ("국", "탕", "찌개", "전골", "밥", "죽", "볶음", "조림", "구이", "찜", "전", "나물", "무침", "샐러드", "수육",
                "국수", "면", "튀김", "김밥", "말이", "쌈", "샌드위치", "버거", "피자", "떡", "빵", "덮밥", "스파게티", "냉채", "회", "젓",
                "만두", "스무디", "주스", "라떼", "모카", "커피", "탕수", "스테이크", "잡채", "겉절이", "김치", "우동", "불고기", "찜닭")
MAX_ALIAS_LENGTH = 9


GENERATED_PREFIX = "어순 별칭(#51)"
REFERENCES = DATA / "FoodReferences.json"


def normalized(value):
    """앱의 FoodReferenceCatalog.normalized와 같은 규칙(표기 변형은 SpellingVariants.json)."""
    value = unicodedata.normalize("NFKC", value).lower()
    for entry in SPELLING:
        for variant in entry["variants"]:
            value = re.sub(r"\s*".join(map(re.escape, variant.replace(" ", ""))), entry["standard"], value)
    return "".join(character for character in value if character.isalnum())


def overlaps(left, right):
    if left in right or right in left:
        return True
    return any(left[index:index + 2] in right for index in range(len(left) - 1))


def known_names():
    """이미 앱이 아는 이름(정규화 키 → 어디의 이름인지)"""
    names = {}

    def add(name, origin):
        names.setdefault(normalized(name), origin)

    for entry in json.loads(REFERENCES.read_text()):
        if entry.get("basisNote", "").startswith(GENERATED_PREFIX):
            continue
        for name in [entry["name"], *entry.get("aliases", [])]:
            add(name, "참고표")
    drinks = json.loads((DATA / "DrinkReferences.json").read_text())
    for entry in drinks["drinks"]:
        for name in [entry["name"], *entry.get("aliases", []), *entry.get("productNames", [])]:
            add(name, "술 표")
    for entry in json.loads((DATA / "PackagedFoodReferences.json").read_text()):
        for name in [entry["name"], *entry.get("aliases", [])]:
            add(name, "포장제품 표")
    source = (ROOT / "ONEULSIK/Models/FoodPortion.swift").read_text(encoding="utf-8")
    for match in re.finditer(r"Row\(names: \[([^\]]*)\]", source):
        for name in re.findall(r'"([^"]+)"', match.group(1)):
            add(name, "대표 분량표")
    return names


def guide_ids():
    data = json.loads((DATA / "GuideRepresentatives.json").read_text())
    entries = data["entries"] if isinstance(data, dict) else data
    return {entry["foodID"] for entry in entries if "foodID" in entry}


def build():
    database = sqlite3.connect(f"file:{DATA / 'FoodCatalog.sqlite'}?mode=ro", uri=True)
    database.row_factory = sqlite3.Row
    rows = database.execute(
        "SELECT * FROM foods WHERE category = '음식' AND brand = ''"
    ).fetchall()
    # 겹침 검사는 앱이 일반 음식으로 고를 수 있는 이름(브랜드 없는 음식·원재료)과 한다. 같은 이름의 업체 제품·가공식품은
    # 일반 음식 후보에서 빠지므로(제품을 원하는 입력이 아니면) 겹침으로 보지 않는다.
    all_keys = {normalized(row["name"]) for row in database.execute(
        "SELECT name FROM foods WHERE brand = '' AND category IN ('음식', '원재료성 식품')")}
    known = known_names()
    guides = guide_ids()

    by_name = {}
    for row in rows:
        by_name.setdefault(row["name"], []).append(row)

    accepted, excluded = [], []
    alias_sources = {}
    for name in sorted(by_name):
        parts = name.split(" ")
        if len(parts) != 2:
            continue
        category, detail = parts
        alias = detail + category
        key = normalized(alias)
        reason = None
        if re.search(r"[(),/ㆍ·\d A-Za-z]", category + detail):
            reason = "괄호·쉼표·숫자·영문"
        elif overlaps(detail, category):
            reason = "세부가 분류와 겹침"
        elif detail in MODIFIER_WORDS or detail.endswith(MODIFIER_SUFFIXES):
            reason = "세부가 수식어"
        elif detail.endswith(DISH_ENDINGS):
            reason = "세부가 요리 이름(이미 재료+요리 순서)"
        elif len(key) > MAX_ALIAS_LENGTH:
            reason = "긴 이름"
        elif key in all_keys:
            reason = "음식 DB에 이미 있는 이름"
        elif key in known:
            reason = f"{known[key]}에 이미 있는 이름"
        if reason:
            excluded.append((name, alias, reason))
            continue
        alias_sources.setdefault(key, []).append((name, alias))

    for key, sources in alias_sources.items():
        if len(sources) > 1:
            for name, alias in sources:
                excluded.append((name, alias, "다른 이름과 같은 별칭"))
            continue
        name, alias = sources[0]
        candidates = by_name[name]
        # 앱 검색이 같은 이름 자료 중 남기는 하나: 대표 자료 지정 > priority > 최신 기준일 > 식품코드. g 자료 먼저.
        candidates = sorted(candidates, key=lambda row: (
            row["basis_unit"] != "g", row["id"] not in guides, row["priority"], "".join(chr(0x10FFFF - ord(c)) for c in row["source_date"]), row["id"]))
        chosen = candidates[0]
        accepted.append({
            "name": alias,
            "aliases": [],
            "referenceID": chosen["id"],
            "referenceName": chosen["name"],
            "amountUnit": chosen["basis_unit"],
            "source": chosen["source"],
            "sourceDate": chosen["source_date"],
            "basisNote": f"{GENERATED_PREFIX}: 식약처 음식 DB '{chosen['name']}'(분류 세부)를 사용자가 쓰는 '{alias}'(세부분류)로도 찾는다. 같은 이름 자료 {len(by_name[name])}건 중 앱 검색이 남기는 자료.",
        })
    return accepted, excluded, len(rows), len(by_name)


def rendered(entries):
    """참고표 파일의 항목 모양(2칸 들여쓰기)으로"""
    return ",\n".join("\n".join("  " + line for line in json.dumps(entry, ensure_ascii=False, indent=2).split("\n"))
                      for entry in entries)


def manual_text():
    """참고표 파일에서 이 스크립트가 넣은 항목을 뺀 원문(손으로 넣은 항목의 모양을 그대로 둔다)"""
    raw = REFERENCES.read_text()
    entries = json.loads(raw)
    generated = [entry for entry in entries if entry.get("basisNote", "").startswith(GENERATED_PREFIX)]
    if not generated:
        return raw, entries
    first = rendered([generated[0]]).split("\n")[0:2]
    marker = "\n".join(first)
    index = raw.index(",\n" + marker)
    manual = [entry for entry in entries if not entry.get("basisNote", "").startswith(GENERATED_PREFIX)]
    return raw[:index] + "\n]\n", manual


def main(argv):
    accepted, excluded, record_count, name_count = build()
    command = argv[1] if len(argv) > 1 else "report"
    if command == "json":
        print(json.dumps(accepted, ensure_ascii=False, indent=2))
        return 0
    if command == "excluded":
        for name, alias, reason in excluded:
            print(f"{name}\t{alias}\t{reason}")
        return 0
    if command in ("apply", "check"):
        manual_raw, manual = manual_text()
        text = manual_raw[:-len("\n]\n")] + ",\n" + rendered(accepted) + "\n]\n"
        if command == "check":
            same = REFERENCES.read_text() == text
            print("같음" if same else "다름: apply로 다시 만드세요")
            return 0 if same else 1
        json.loads(text)
        REFERENCES.write_text(text)
        print(f"참고표 손으로 넣은 항목 {len(manual)}개 + 어순 별칭 {len(accepted)}개 = {len(manual) + len(accepted)}개")
        return 0
    one_space = len(accepted) + len(excluded)
    print(f"브랜드 없는 '음식' 자료 {record_count}건, 고유 이름 {name_count}개, 띄어쓰기 하나인 이름 {one_space}개")
    print(f"별칭 {len(accepted)}개, 뺀 이름 {len(excluded)}개")
    reasons = {}
    for _, _, reason in excluded:
        reasons[reason] = reasons.get(reason, 0) + 1
    print("뺀 이유:", ", ".join(f"{reason} {count}" for reason, count in sorted(reasons.items(), key=lambda item: -item[1])))
    print("별칭 예시:", ", ".join(f"{entry['name']}→{entry['referenceName']}" for entry in accepted[:30]))
    print("뺀 예시:", ", ".join(f"{name}({alias}: {reason})" for name, alias, reason in excluded[:30]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
