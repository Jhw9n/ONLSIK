# 화면 이동(NavigationStack)

탭 위로 여는 화면은 `MainTabView`의 NavigationStack 하나로 push한다(2026-11-26, #49). 이전에는 fullScreenCover(애니메이션 끔)로 열어
왼쪽 가장자리 스와이프 뒤로가기가 없었고, 직접 만든 스와이프로 밀면 아래에 이전 화면 대신 빈 배경이 보였다
(fullScreenCover는 표시가 끝나면 아래 화면을 그리지 않는다). push로 바꿔 iOS 기본 슬라이드와 스와이프 뒤로가기
(이전 화면이 아래에서 따라옴)를 쓴다.

## 구조

- `MainTabView`: 탭(TabView)과 하단 탭바(`MainTabBar`, safeAreaInset)를 통째로 `NavigationStack(path:)` 하나로 감싼다.
  push한 화면은 탭바 없이 전체 화면이고, 뒤로 밀면 탭바가 있는 이전 화면이 아래에서 보인다. 각 탭 안에는 NavigationStack을 따로 두지 않는다.
- 모든 push 화면은 기본 내비게이션 바를 숨기고(`toolbar(.hidden, for: .navigationBar)`) 직접 만든 헤더와 뒤로가기 버튼을 쓴다. 뒤로가기 버튼은 pop.
- push·pop은 iOS 기본 슬라이드 애니메이션(전의 `disablesAnimations`는 쓰지 않음).

## 라우터(`ONEULSIK/App/AppRouter.swift`)

- `AppRoute`: 경로 이름 — `weeklyReport`, `exerciseGame`, `mealEntry`, `foodSearch`, `foodQuantity`, `profileEdit(항목)`, `settings`, `searchImprovementLog`(설정 > 검색 개선 기록, #51).
- `AppRouteEntry`: 스택에 올린 화면 하나(경로, 화면을 만드는 클로저, `onPop`).
- `AppRouter`(@Observable): `path`(NavigationStack에 묶음), `push(경로, onPop:) { 화면 }`, `pop()`, `pop(경로)`, `popToRoot()`, `contains(경로)`.
  `MainTabView`가 하나 만들어 `environment(\.appRouter)`로 내려 준다. 화면은 연 곳에서 만들어 넘긴다(그 화면의 값·콜백을 그대로 쓰기 위해).
- `onPop`: 화면이 스택에서 빠지면(버튼이든 스와이프든) 부른다. **예전 fullScreenCover의 `onDismiss` 자리**다. path를 바꾸는 중이라 다음 차례에 부르고,
  onPop 안에서 또 pop해도 된다.
- 홈·기록·내정보 내용은 `NoBounceScrollView` 안의 별도 UIHostingController라 environment가 그대로 전달되지 않을 수 있어, 화면 body에서 라우터를 꺼내 넘긴다.

| 화면 | 경로 | 여는 곳 | onPop(전의 onDismiss) |
| --- | --- | --- | --- |
| 주간 리포트 | `.weeklyReport` | `HomeView.openWeeklyReport` | 홈 맨 위 스크롤(`reportDismissScrollToTopTrigger += 1`) |
| 운동 환산 | `.exerciseGame` | `HomeView.openExerciseGame`(체중은 여는 순간 값) | 없음. 배너 김은 `router.contains(.exerciseGame)`이면 멈춤 |
| 식사 기록(MealEntryPresentation) | `.mealEntry` | `RecordView.openMealEntry` | 기록 화면 새로 읽기(`viewModel.reload`) |
| 음식 검색 | `.foodSearch` | `MealEntryView.openFoodSearch`(AI를 못 쓰는 기기는 MealEntryPresentation이 바로 보여 줌) | `finishFoodSearch`: 검색에서 저장했으면 onSaved 뒤 식사 기록도 닫음 |
| 수량 선택 | `.foodQuantity` | `FoodSearchView.openQuantitySelection` | `finishQuantitySelection`: 확정했으면 onSaved 뒤 검색도 닫음 |
| 나의 정보 수정(성별·생일·키·몸무게·활동량) | `.profileEdit(항목)` | `ProfileView.openEditor` | 없음(저장하면 `viewModel.reload` 뒤 pop) |
| 설정 | `.settings` | `ProfileView.openSettings` | 없음(로그아웃은 `popToRoot` 뒤 기존 로그아웃) |

- 식사 기록 흐름: 수량 선택에서 뒤로 → 음식 검색, 음식 검색에서 뒤로 → 식사 기록으로 한 단계씩. 수량을 확정하면 수량 → 검색 → 식사 기록이
  차례로 빠지고 기록 화면을 새로 읽는다(전과 같은 onSaved·dismiss 연결).
- 식사 상세(MealDetailView, sheet), 온보딩 흐름, 알림 alert는 바꾸지 않았다.
- push한 화면에서 돌아오면 아래 화면의 `onAppear`가 다시 불린다(홈은 내용을 다시 읽고, AI 리포트를 만드는 중이었다면 다시 시작).

## 내비게이션 바를 숨겨도 스와이프 뒤로가기가 되게

- 기본 내비게이션 바를 숨기면 `UINavigationController.interactivePopGestureRecognizer`가 동작하지 않는다.
- `PopGestureEnabler`(AppRouter.swift): `MainTabView`의 스택 안에 둔 빈 UIView에서 응답자 사슬로 **이 스택의 UINavigationController 하나**를 찾아
  `interactivePopGestureRecognizer.delegate`를 바꾼다. 앱 전체 UINavigationController 확장은 쓰지 않는다(적용 범위는 이 스택만).
- 시작 허용 조건: 화면이 2개 이상(`viewControllers.count > 1`), 전환 중이 아님, 맨 위 화면이 막지 않음. 시작할 때 키보드를 내린다.

## 화면별 스와이프 막기

`.popGestureDisabled(조건)`: 스택에 올린 화면 안에서 조건이 참인 동안 그 화면의 스와이프 뒤로가기를 막는다(뒤로가기 버튼은 그대로).

| 화면 | 막는 조건 |
| --- | --- |
| 운동 환산 | 뒤로가기 버튼이 안 보일 때: 칩이 떨어지는 연출·분석 중, 결과 화면(결과 화면은 "다시 담기"만 누를 수 있음) |
| 식사 기록 | 저장 중, AI 분석 중 |
| 설정 | 탈퇴 처리 중 |

## 수량 선택 화면

수량 선택(`FoodQuantityPresentation`)은 반투명 어두운 바탕 위 아래쪽 카드 모양이다. push로 바꾼 뒤에는 아래에 음식 검색 화면이 그려지지 않아,
카드 위쪽이 **어두운 바탕**으로 보인다. 수량 칸에 포커스가 잡혀 있으면 바깥을 처음 누를 때는 키보드만 내려간다(기존 동작).

## 테스트(`ONEULSIKTests/NavigationTests.swift`, 창 탭 묶음 `ExerciseGameTouchTests` 안에서 차례로 실행)

- Z01 경로별 push·pop 스택, Z02 주간 리포트가 빠질 때(버튼·path 줄임) 스크롤 트리거, Z03 식사 기록 → 검색 → 수량 확정 뒤 모두 빠지고 새로 읽기(가짜 저장소),
  Z04 주간 리포트 버튼 pop과 스와이프 제스처 설치·허용, Z05 운동 환산 결과 막음·입력 허용, Z06 화면 7개 뒤로가기 버튼 pop, I01 주간 리포트 뒤로가기 48×48.
- **합성 터치(TouchSynthesizer)로는 iOS 기본 가장자리 스와이프를 테스트할 수 없다.** 합성 이벤트에는 '화면 가장자리에서 시작함' 정보가 없어
  interactivePopGestureRecognizer가 시작되지 않는다. 그래서 테스트는 제스처의 판정(delegate)을 직접 묻고, 실제 스와이프는 실기기에서 확인했다(2026-11-26).
- 전체 테스트: `TestReports/2026-11-26_0502.md`(iOS 27.0 시뮬레이터 iPhone 18 Pro, 303개 중 301개 통과, L01·L02는 기존 실패).
