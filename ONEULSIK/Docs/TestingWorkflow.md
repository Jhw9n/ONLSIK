# 테스트·데이터·DB 작업 규칙

## 1. 적용 범위

오늘식(ONEULSIK)의 식사 입력 회귀 테스트, 음식 데이터 파일, 음식 DB(`FoodCatalog.sqlite`)를 다룰 때의 규칙이다.
Git 이슈·브랜치·커밋·PR 규칙은 `Docs/GitWorkflow.md`를 따른다.

| 대상 | 위치(앱 폴더 기준) |
| --- | --- |
| 회귀 케이스 | `ONEULSIKTests/MealRegressionCases.json` |
| 테스트 코드 | `ONEULSIKTests/` (가짜 해석기: `Support/FakeMealFoodInterpreter.swift`) |
| 전체 테스트 실행 | `Scripts/run_tests.sh` |
| 테스트 보고서 | `TestReports/YYYY-MM-DD_HHMM.md` |
| 메뉴 커버리지 점검 | `Scripts/check_menu_coverage.py`, `Docs/MenuCoverage.txt` |
| 대표 분량 연결 점검 | `ONEULSIKTests/PortionLinkTests.swift`(앱이 고르는 항목에 대표 분량이 붙는지) |
| 대표 분량 음식 전체 점검(L03) | `ONEULSIKTests/PortionAuditTests.swift`, 기준선 `ONEULSIKTests/PortionAuditBaseline.json`(규칙: `Docs/FoodResolution.md`) |
| 음식 DB 1인분 중량 점검(L04) | `ONEULSIKTests/DishServingTests.swift`(보고만 함: 대표 분량표·참고표와 20% 넘게 다른 음식, 1인분 상한으로 안 쓰는 값) |
| 음식 DB 1인분 중량 데이터 | `ONEULSIK/Resource/Data/DishServings.json`(생성: `Scripts/build_dish_servings.py <식약처 음식 DB xlsx>`, `--check`로 다시 만든 결과와 같은지 확인) |
| 음식 데이터 파일 | `ONEULSIK/Resource/Data/*.json` |
| 음식 DB | `ONEULSIK/Resource/Data/FoodCatalog.sqlite` |

## 2. 실패 사례를 받았을 때

1. 사례를 케이스 JSON에 먼저 추가하고 `run_tests.sh`로 실패를 확인한다.
2. 기대값이 정해지지 않았거나 기획 판단이 필요하면 코드를 고치기 전에 사용자에게 묻는다.
3. 비슷한 사례끼리 원인 단위(파싱, 정규화·별칭, 검색·정렬, 분량, 수식어 등)로 묶어 고친다.
   사례 하나씩 따로 고치지 않는다.
4. 음식별 예외, 별칭, 단위, 수식어는 코드가 아니라 `Resource/Data`의 데이터 파일에 둔다.
   코드는 데이터를 읽어 적용하는 일반 규칙만 가진다.
5. 고친 뒤 `run_tests.sh`로 전체 테스트를 돌려 `TestReports/`에 보고서를 남긴다.
   작업을 커밋으로 나누면 커밋마다 보고서를 남긴다.
6. 사례별 결과(전후 비교)와 변경 이유를 보고한다.

## 3. 기대값

- 기대값은 기준을 바로잡는 경우에만 바꾼다. 통과시키려고 기대값을 낮추거나 넓히지 않는다.
- 기대값을 바꾸면 커밋 메시지에 이유와 바꾼 케이스 목록을 적는다.
- 가짜 해석기가 정한 분량(케이스의 `llm.portion`)에서 나온 숫자는 기대값의 근거로 쓰지 않는다.
  연결된 항목의 종류, 이름, 단위, 분량·열량 범위처럼 앱 규칙이 정하는 결과를 기준으로 적는다.
- 아직 못 푸는 케이스는 기대값을 그대로 두고 "알려진 실패"로 따로 표시한다.
  케이스의 `note`에 이유를 적고, 보고할 때 새로 생긴 실패와 구분한다.

## 4. 화면 문구와 저장 문자열

- 데이터 파일에서 화면에 보이는 문구는 `displayText`(또는 `rawDisplayText`), 결정 날짜·출처 메모 같은
  내부 근거는 `basisNote`처럼 별도 필드에 둔다. 앱은 화면용 필드만 화면에 쓴다.
- 기록에 저장되는 문자열(`MealRecord.nutritionSource` 등)도 사용자에게 보여도 되는 문구만 쓴다.
- 날짜, "결정", "내부 기준", "대표값:" 같은 내부 용어가 화면 문구나 저장 문자열에 들어가면 실패하는
  테스트(`DisplayTextTests`, `StoredSourceTests`)를 유지한다. 화면용 필드를 새로 만들면 검사 대상에 추가한다.
- SwiftData 모델(`MealRecord`)에는 버전 스키마가 없다. 필드를 추가하거나 바꿔야 하면 구현 전에 사용자에게 알린다.

## 5. 음식 DB

- `FoodCatalog.sqlite`는 `Scripts/`의 스크립트로만 바꾼다. 직접 SQL로 고치거나 다른 도구로 편집하지 않는다.
  - 처음부터 만들기: `build_food_catalog.py`
  - 기존 DB에 덧붙이기: `add_package_weights.py`(제품 총중량, 식품 분류 코드)
- 스크립트는 실행 전후 기존 열과 영양 열의 해시를 비교하고, 같을 때만 DB를 교체한다.
- DB 크기는 100MiB(104,857,600바이트) 미만으로 유지한다. 열을 추가하기 전에 크기를 먼저 측정하고,
  넘을 것 같으면 쓰지 않는 열·인덱스 정리 방안을 먼저 보고한다.
- 바이너리라 커밋할 때마다 저장소가 커지므로 DB 변경 커밋은 작업당 한 번만 한다.
- 원본 엑셀은 저장소에 넣지 않는다. 사용한 파일의 SHA-256을 `Docs/FoodCatalogImport.json`에 기록하고,
  같은 원본인지는 SHA-256으로 확인한다.
- 원본 파일 경로가 필요하면 사용자에게 묻는다.

## 6. 검증 구분

- 테스트는 실제 Apple Intelligence 대신 가짜 해석기로 실행한다. 이 결과는 "실기기 미확인"으로 표시한다.
- 실기기에서 확인한 결과는 기기, 날짜, 입력, 화면 결과를 따로 적는다.
- 실행하지 않은 검증은 통과했다고 쓰지 않는다. 화면 배치처럼 테스트로 확인하기 어려운 항목은
  확인 방법(시뮬레이터 스냅샷 등)과 미확인 범위를 함께 적는다.

## 7. 금지 사항

- 특정 음식 이름을 코드에 추가해서 테스트를 통과시키기(데이터 파일에 넣는 것은 가능)
- 통과시키려고 기대값을 임의로 바꾸기
- `project.pbxproj` 직접 수정(타깃·파일 구성 변경이 필요하면 Xcode에서 하도록 사용자에게 안내)
- `.xcresult` 등 테스트 실행 결과 원본의 커밋(보고서 `.md`만 커밋)
