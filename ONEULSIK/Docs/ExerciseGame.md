# 먹고 싶은 음식 → 운동 시간 화면(#49)

전시(2026-11-26) 관람객용 화면이다. 홈 배너("먹고 싶은 음식 담아보기")에서 fullScreenCover로 열고, 먹고 싶은 음식을 그릇에 담으면 그 열량을 걷기·러닝·천국의 계단 시간으로 보여 준다. 디자인은 Figma "운동 환산 이벤트 시안" 최종본(375×812 기준)을 따른다.

## 파일

| 파일 | 내용 |
| --- | --- |
| `ONEULSIK/Features/Home/ExerciseGame/ExerciseGameView.swift` | 담기(A)·담기 연출(B)·결과(C) 화면, 배치(`GameLayout`), 스크린샷용 고정 상태(`ExerciseGameSnapshot`) |
| `ONEULSIK/Features/Home/ExerciseGame/ExerciseBowlView.swift` | SwiftUI 도형으로 그린 그릇(몸통·테두리·안쪽·받침·그림자·초록 빛·김), 배너용 작은 그릇 |
| `ONEULSIK/Features/Home/ExerciseGame/ExerciseGameAnalyzer.swift` | 분석(기존 `AIMealEntryService`), 표시 이름, 조사 |
| `ONEULSIK/Features/Home/ExerciseGame/ExerciseGameBanner.swift` | 홈 배너, 배너 표시 스위치 `ExerciseGameFeature.isBannerEnabled` |
| `ONEULSIK/Models/ExerciseEquivalent.swift` | 운동 시간·거리 계산, 체중 선택 |
| `ONEULSIK/Resource/Data/ExerciseEquivalents.json` | MET 값과 출처 |

## 계산

- 분석: 기록 화면과 같은 `AIMealEntryService`로 분석하고 결과 열량만 쓴다. 질문이 나오면 보이지 않고 첫 선택지를 고른다(열량 확인 질문의 첫 선택지는 "맞아요, 그대로 기록"). 선택은 최대 5번, 시간 제한 60초. 음식이 여럿이면 열량을 합한다. 결과는 식사 기록(MealRecord)으로 저장하지 않는다.
- 운동: 2024 Adult Compendium of Physical Activities(Herrmann SD 외, J Sport Health Sci 2024;13(1):6-12, https://pacompendium.com). 걷기 17190 3.8 MET, 러닝 12030 8.5 MET, 천국의 계단 02065 9.3 MET.
- 분당 kcal = MET × 3.5 × 체중(kg) ÷ 200. 시간(분) = kcal ÷ 분당 kcal를 반올림. 거리 = 시속(걷기 5km, 러닝 8km) × 반올림 전 시간, 소수 첫째 자리.
- 체중: 가장 최근 체중 기록 → 프로필 체중 → 65kg(20kg 미만·300kg 초과는 쓰지 않음). 65kg를 쓰면 안내 문구가 "체중 65kg 기준 대략적인 시간이에요"로 바뀐다.
- 표시 이름: 음식 하나면 "이름 양"(0.5단위는 "반", 예: 반마리), 둘 이상이면 "첫 음식 외 N개". 이름은 기록 이름 대신 입력한 표기(참고표 별칭)를 쓴다. 조사 "은/는"은 마지막 글자 받침(숫자·단위는 읽는 소리)에 맞춘다.

## 연출(기준값)

| 단계 | 구현 |
| --- | --- |
| ① 담기 | 키보드 내림, 입력칸이 줄어들며 사라지고 칩이 나타남(spring 0.25초), 약한 진동, 분석 시작, 제목·부제 투명도 0.35 |
| ② 들어 올림 | 칩 1.05배, 위로 12pt·왼쪽 22pt, -8°(ease-out 0.15초) |
| ③ 떨어짐 | 가로 ease-out·세로 ease-in 0.45초로 작은 호, 회전 0°, 크기 0.6, 잔상 2개(0.3·0.12, 0.04·0.08초 지연). 입구 아래는 안쪽 타원 밖을 가려 그릇 속으로 들어가 보임 |
| ④ 닿음 | 중간 진동, 그릇 세로 0.96 → 1(spring 0.25초), 물결 고리(0.4초) |
| ⑤ 채워짐 | 안쪽이 아래부터 초록으로(0.4초), 초록 빛 0.75로 밝아졌다 0.45로, 김 3줄(0.2초 시간차 반복) |
| ⑥ 기다림 | 분석이 안 끝났으면 "계산하고 있어요" + 점 세 개 |
| ⑦ 결과 | 0.3초 교차 전환, kcal 0 → 값(0.6초), 카드 아래에서 16pt 떠오름(0.08초 간격), 시간도 0부터, 성공 진동 |
| 실패 | 분석이 떨어지기 전에 실패하면 칩이 그릇 오른쪽 가장자리에 부딪혀 튕겨 나옴(0.4초). 기다리다 실패하면 그릇이 비워지고 칩이 튀어나옴. 입력칸으로 돌아오고 안내 표시, 입력은 남김 |

- 동작 줄이기: 떨어짐·튕김·숫자 올라감·비눗방울·김 움직임 없이 교차 전환.
- 연타: 단계가 담기일 때만 시작한다(분석이 두 번 돌지 않음).
- 키보드: 키보드 높이만큼 하단 버튼을 올리고, 입력칸이 가려지면 화면을 올린다. 키보드 완료도 담기.

## 테스트

`ONEULSIKTests/ExerciseGameTests.swift`: 계산 E01~E05, 분석 흐름 Y01~Y05(가짜 해석기, MealRecord 저장 없음 포함), 표시 이름·조사 X01~X04. 스크린샷은 `ExerciseGameSnapshotTests`(환경 변수 `ONEULSIK_SNAPSHOT_DIR`이 있을 때만, 예: `TEST_RUNNER_ONEULSIK_SNAPSHOT_DIR=<폴더> xcodebuild test -only-testing:ONEULSIKTests/ExerciseGameSnapshotTests`).
