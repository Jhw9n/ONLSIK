# 음식 판정과 영양값·분량 출처

음식 하나가 기록될 때 어떤 DB 자료와 어떤 분량·영양값 출처가 쓰이는지를 한곳에 모은 문서입니다(2026-11-19 작성, #29).
**지금 코드가 실제로 하는 순서**를 함수 이름과 데이터 파일로 적습니다. 다른 문서의 설명과 코드가 다르면 이 문서는 코드를 따릅니다.
각 규칙의 근거와 결정 기록은 `FoodCatalog.md`, `FoodReferences.md`, `MealEntry.md`, `MealPortionValidation.md`에 있습니다.

경로는 두 가지입니다.

- **검색 화면**: `FoodSearchView` → `FoodCatalogService.search(query:)`로 고른 항목을 `FoodQuantityView`에서 기록합니다.
- **AI 식사 입력**: `AIMealEntryService.analyze(_:)` → `resolve(_:items:)` → `resolveSelection` → `makeItem`.

데이터 파일은 모두 `ONEULSIK/Resource/Data/` 아래에 있습니다.

## 1. 음식 판정 순서(입력 이름 → DB 자료 후보)

### 1-1. 문장에서 음식 이름 얻기(AI 식사 입력)

`AIMealEntryService.analyzeMeal`이 아래 순서로 처음 맞는 방법을 씁니다.

1. `MealFoodNames.ramenCorrection`: 알려진 메뉴와 한 글자만 다른 단독 입력이면 교정 질문
2. `MealInputGrounding.setMenuName`: 정식·세트면 구성 질문
3. `MealInputGrounding.singlePreparedReference`: 조리 음식 참고값(`PreparedFoodReference`) 단독 입력
4. `MealInputGrounding.singleFoodWithAmount` + `isKnownSingleFood`: 음식 하나 + 양. 참고표·술 표 이름이거나 검색에서 이름(수식어를 뗀 이름 포함)이 정확히 맞을 때만
5. `catalogFoodList`: 쉼표로 나눈 2~8개 이름이 모두 참고표·포장제품 표 이름이거나 검색에서 정확히 맞을 때
6. `MealFoodNames.singleRelatedRamen`
7. 그 밖에는 모델(`MealFoodInterpreting.foods`)

그다음 `MealInputGrounding.ground`가 양·단위를 원문에서 다시 읽습니다. 이름 끝에 붙은 양 표현은 떼고, 단위 없는 개수(하나/둘…)도 여기서 읽습니다.

### 1-2. 이름 하나를 DB 자료로(AI 식사 입력, `resolve(_:items:)`)

1. **대표 이름으로 바꾸기**
   - `MealFoodNames.canonical`: 참고표(`FoodReferences.json`)의 `name`·`aliases` 중 하나와 같으면 그 항목의 `name`으로 바꿉니다.
   - 이름 비교는 `FoodReferenceCatalog.normalized`로 합니다. 표기 변형(`SpellingVariants.json`)을 맞추고 글자·숫자만 남깁니다.
2. 제품을 원하는 입력인지 정합니다(`prefersProducts`: 브랜드, 봉·팩, 컵라면 등).
3. `PreparedFoodReference.entry`: 조리 음식 참고값이 있으면 바로 선택합니다.
4. `DrinkReferenceCatalog.entry`: 술 표(`DrinkReferences.json`) 이름이면 `resolveDrink`로 처리합니다.
5. 포장제품 표(`PackagedFoodReferences.json`) 후보는 제품을 원하는 입력일 때 질문합니다.
6. "반찬"처럼 무엇인지 모르는 이름이면 질문합니다.
7. **참고표 referenceID**: 이름이 참고표 항목이고 추가 설명이 없으면 `catalog.food(id:)`로 그 자료를 바로 가져옵니다.
   - `FoodReference.matches`가 이름·단위·출처·기준일까지 맞아야 합니다.
   - mL 자료면 `preferredReferenceFood` → `gramFood`로 같은 요리의 g 자료를 먼저 찾습니다.
8. **대표 분량표 별칭(2026-11-19 결정, #31)**: 참고표 이름이 아니고, 브랜드·제품 입력(`prefersProducts`)이 아니고, 추가 설명이 없을 때 적용합니다.
   - 입력 이름이 대표 분량표의 자료집 출처 행 이름 중 하나와 맞으면(`FoodPortion.guidePage(forName:)`, 이름 비교는 `lookupKey`) 그 행의 쪽 번호에 지정된 자료(`GuideRepresentativeCatalog.entry(forName:)`)를 `catalog.food(id:)`로 바로 가져옵니다.
   - 같은 행의 이름들을 같은 음식의 별칭으로 봅니다. 예: `소갈비찜` → 97쪽 → `갈비찜 소고기`(D307).
   - 표시는 참고표와 같습니다. 입력 이름과 DB 이름이 다르면 입력 이름으로 보여주고, 저장 출처는 `{출처} · {DB 이름} 영양값 기준`입니다(내부 영양값 근거는 `similarFood`). 지정 자료가 DB에 없으면 다음 단계로 갑니다.
9. **검색**: `searchName`(밥→쌀밥, 파스타→스파게티 등)으로 다듬은 이름을 `FoodCatalogService.search`에 넘깁니다. 1-3절의 규칙이 적용됩니다.
10. **후보 정리** `candidates(from:input:)`
   - 일반 음식만 남깁니다(브랜드 입력이면 전체, 제품 입력이면 가공식품만).
   - 정렬 순서: 참고표 자료 → 이름이 정확히 같은 자료 → 수식어 규칙 순위(`FoodModifiers.json`) → 분류 "음식" → g 기준
   - 같은 이름·업체는 하나만 남기고, 같은 이름 후보는 분류 코드 다수결로 정렬합니다(`groupedByMajorityCategory`).
11. **이름별로 미리 정한 갈림길**
    - 돼지갈비 조리법 질문
    - 검색 결과 안의 참고표 자료 선택
    - 이름이 정확히 같은 자료 선택
    - 라멘 관련 질문, 스파게티 소스 질문
    - 볶음·조림 재료가 같은 비슷한 음식 질문(`FoodReferenceCatalog.similarDishQuery`)
12. **모델 선택**: `interpreter.assess`가 후보 최대 8개 중에서 고릅니다. 못 고르면 `searchTerms`로 한 번 더 찾습니다.
    - 고른 자료의 이름이 입력과 다르면 "비슷한 음식 기준으로 기록할까요?" 질문을 합니다(`similarFoodQuestion`).
13. 그래도 없으면 포장제품 후보 질문, 정보 부족 질문, 모델 영양 추정(`estimateNutrition`, 근거 DB 항목 확인) 순으로 처리하고, 그것도 안 되면 질문합니다.

### 1-3. 검색(`FoodCatalogService.search`, 두 경로 공통)

1. `FoodReferenceCatalog.queries`로 검색어를 늘립니다. 검색어가 참고표 이름이 아니고 대표 분량표 별칭(1-2의 8번)에 맞으면, 지정 자료의 DB 이름을 맨 앞 검색어로 더하고 그 자료를 `preferredID`로 둡니다. 그래서 지정 자료가 첫 일반 음식 후보로 오고, 다른 후보는 빠지지 않습니다.
   - 참고표 대표 DB 이름과 대표 이름
   - 표기 변형을 맞춘 이름
   - 젓갈 → "○ 젓"
   - 끝말 목록(스파게티, 볶음밥, 순두부찌개, 김치찌개, 된장찌개, 돈가스, 김밥, 칼국수, 미역국, 초밥, 불고기, 덮밥, 찌개, 파스타)을 앞으로 보낸 이름(예: 참치김밥 → "김밥 참치")
2. `searchExact`: 공백으로 나눈 검색어 조각이 모두 이름이나 업체에 들어 있어야 합니다.
   - 한 단어가 김밥·볶음밥·찌개·칼국수로 끝나면 두 조각으로 나누고, 순서를 뒤집은 이름도 찾습니다(`reversedDishName`).
3. 결과가 없으면 참고표 이름과 한 글자만 다른 이름으로 찾습니다(`spellingCandidates`).
4. 일반 음식이 하나도 없으면 앞쪽 수식어(`FoodModifiers.json`: 냉동·생·숯불·직화 등)를 떼고 다시 찾아 뒤에 붙입니다.
5. 같은 이름·단위 일반 음식은 하나만 남깁니다(2절 순서).
6. 정렬 순서
   - 일반 음식·원재료 > 급식 > 브랜드·가공식품
   - 그 안에서는 전체 일치 > 쉼표 조각 일치 > 첫 단어 일치 > 접두사 > 조각 접두사 > 부분 일치
   - 원재료 우선, 이름 길이 순
7. 같은 이름 후보는 분류 코드 다수결로 정렬합니다.

## 2. 영양값 자료 선택 순서(같은 음식의 자료가 여러 개일 때)

| 순서 | 규칙 | 코드·데이터 | 검색 화면 | AI 식사 입력 |
|---|---|---|---|---|
| 1 | 참고표 지정 자료 | `FoodReferences.json`의 referenceID. 검색에서는 `preferredID(for:)`로 같은 이름·단위 중 맨 앞에 둠 | 검색어가 참고표 이름과 같을 때만 | 입력 이름이 참고표 이름이면 항상(1-2의 7번) |
| 2 | 대표 분량표 별칭의 자료집 지정 자료 | `FoodPortion.guidePage(forName:)` → `GuideRepresentativeCatalog.entry(forName:)`. 참고표·술 표 지정이 없을 때 | 검색어가 별칭에 맞으면 첫 일반 음식 후보 | 입력 이름이 별칭에 맞으면 항상(1-2의 8번) |
| 3 | 자료집 지정 자료 | `GuideRepresentatives.json`(53개). `searchExact`에서 같은 이름·단위 중 참고표 다음 | 적용 | 적용(검색 결과를 씀) |
| 4 | 같은 요리의 g 자료 | `gramFood(sameNameAs:)`: 이름이 같거나 어순만 다른 g 자료(`FoodPortion.sameDishNames`, 규칙 1~4) | 적용 안 함 | 국물·면 mL 자료에 대표 분량을 쓰기 직전(`makeItem`), 참고표가 mL 자료를 가리킬 때(`preferredReferenceFood`) |
| 5 | 국물·면 mL 자료(1mL=1g) | `VolumeAsWeight.json`, `FoodPortion.representative(for:allowsVolumeAsWeight: true)` | 적용 안 함(mL 직접 입력) | 같은 요리의 g 자료가 없을 때 |
| 6 | priority > 기준일 > 식품코드 | `searchExact`의 ROW_NUMBER 순서. priority: 일반 0, 급식 1, 브랜드 2 | 적용 | 적용 |

- 일반 음식은 기준일이 모두 2026-08-28이라, 1~3번 지정이 없으면 사실상 식품코드 순으로 정해집니다.
- 4번은 `gramFood`가 검색 결과의 첫 g 자료를 쓰므로 그 안에서도 3·6번 순서를 따릅니다.
- 검색 결과에서 무엇을 고를지(1-2의 10~12번)는 자료 선택과 별개입니다. 이름이 다른 자료가 뽑히면 내부 영양값 근거는 `similarFood`이고, 저장 출처는 `{출처} · {DB 이름} 영양값 기준`입니다(#33).

## 3. 분량 출처 순서

### AI 식사 입력(`makeItem`)

단위·수량을 적지 않은 입력은 먼저 `inputWithAssumedUnit`이 단위를 정합니다.
- 우선순위: 포장제품 → 개, 대표 분량이 있으면 → 그 단위, 참고표 `estimatedPortions`가 있으면 → 그 단위
- 셋 다 없으면 수량을 묻습니다(`portionUnknown` → `amountQuestion`). 이 경우 AI 추정은 쓰지 않습니다.

그다음 아래 순서로 처음 맞는 출처를 씁니다.

1. 조리 음식 참고값(`PreparedFoodReference`, `preparedItem`)
2. 술 용기 표(`DrinkReferences.json`, `drinkItem`)
3. 포장제품 표의 제품 총중량(`PackagedFoodReferences.json`)
4. 가공식품 DB의 제품 총중량(`package_amount`, 개·봉·팩·병·캔, `packageItem`)
5. 사용자가 적은 g/mL(DB 기준 단위와 같을 때만)
6. 소량·종지 반찬(`FoodPortion.smallSideGrams`)
7. 사용자가 질문에 답한 분량(`portionOverride`)
8. 대표 분량표(`FoodPortion.representative`, 국물·면 mL 포함)
9. 참고표 `estimatedPortions`
10. AI 분량 추정(`interpreter.portion`, `isPlausible` 범위 검사)
11. 그래도 안 되면 수량·중량 질문(`resolveSelection`의 `portionUnknown` 처리)

`resolveSelection`은 `makeItem` 전에 `suggestedPortion`(라멘의 우동 1그릇 참고, 너겟 1개)을 질문으로 먼저 보여줄 수 있습니다.

### 검색 화면(`FoodQuantityView`)

1. 대표 분량(`FoodCatalogItem.representativePortion` = `FoodPortion.representative(for:)`, g 기준만, 국물·면 mL 제외)
2. 없으면 g/mL 직접 입력이 기본입니다.

## 4. 목표 규칙

대표 분량 음식 전체 점검(`PortionAuditTests`의 L03)의 결과를 보고 할지와 방법을 정합니다.

### 구현됨

- **[구현됨, #31] 대표 분량표 이름을 그 음식의 별칭으로 보기.** 1-2의 8번, 2절의 2번입니다.
  - 예: `소갈비찜`은 이전에 mL 자료 `소갈비찜`(D407)으로 가서 양을 물었습니다. 이제 같은 행(자료집 97쪽)의 지정 자료 `갈비찜 소고기`(D307)로 1접시 250g 495kcal를 기록합니다.
  - L03의 이름 불일치 15건이 모두 해결됐습니다(위반 105 → 78건).

### 아직 구현 안 됨

- **[미구현] 동의어 데이터 파일.** 대표 분량표·참고표와 별도로 DB 이름의 동의어를 데이터로 관리하는 방법입니다. 이름 불일치 15건(어순 8, 표기 변형 5, 동의어 1, 재료 표기 1)이 별칭 규칙으로 모두 해결돼 **아직 필요 없습니다**. 대표 분량표에 없는 음식에서 같은 문제가 확인되면 다시 봅니다.
- **[미구현] 자료집 영양값 직접 사용.** 자료집과 맞는 DB 자료가 없을 때(예: 고등어구이) 자료집의 100g당 영양값을 쓰는 방법입니다.
- **[해결됨, #33] 같은 음식의 다른 이름에도 "유사 음식" 근거가 붙던 문제.** 다른 이름의 DB 자료로 기록하면 저장 출처를 `{출처} · {DB 이름} 영양값 기준`으로 남깁니다(술 기록과 같은 형식, 2026-11-20 결정). 예: `대구매운탕` → 저장 출처 `식품의약품안전처 · 매운탕 대구 영양값 기준`.
  - 같은 음식인지 비슷한 음식인지 판단은 기록에 남기지 않습니다. 내부 값 `MealNutritionBasis.similarFood`와 확인 질문 화면 문구("비슷한 음식 기준으로 기록할까요?")는 그대로입니다.
  - 이미 저장된 기록은 옮기지 않아 옛 문구(`유사 음식: … · …`)로 남습니다.
- **[미구현] 입력 방식 검토(자동완성 선택).** 이름 불일치가 동의어로 풀 수 있는 수준인지, 사용자가 DB 이름을 직접 고르게 하는 편이 나은지 점검 결과를 보고 판단합니다.
