import Foundation
import Observation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import ONEULSIK

/// 운동 환산 화면(#49) 계산·분석 흐름·표시 이름 테스트.
@MainActor
@Suite("운동 환산")
struct ExerciseGameTests {
    private static func exercise(_ id: String) -> ExerciseEquivalent? {
        ExerciseEquivalentCatalog.exercises.first { $0.id == id }
    }

    /// (걷기 분, 걷기 km, 러닝 분, 러닝 km, 계단 분)
    private static func values(kcal: Double, weight: Double) -> (Int, Double?, Int, Double?, Int)? {
        guard let walk = exercise("walking"), let run = exercise("running"), let stairs = exercise("stairs") else { return nil }
        return (walk.minutes(kcal: kcal, weightKG: weight), walk.kilometers(kcal: kcal, weightKG: weight),
                run.minutes(kcal: kcal, weightKG: weight), run.kilometers(kcal: kcal, weightKG: weight),
                stairs.minutes(kcal: kcal, weightKG: weight))
    }

    @Test("운동 시간 계산", arguments: [
        // 분당 kcal = MET × 3.5 × 체중 ÷ 200, 시간은 반올림, 거리는 반올림 전 시간 × 시속
        ("E01", 927.0, 65.0, 214, 17.9, 96, 12.8, 88),
        ("E02", 927.0, 80.0, 174, 14.5, 78, 10.4, 71),
        ("E03", 349.0, 65.0, 81, 6.7, 36, 4.8, 33),
    ])
    func minutes(_ id: String, _ kcal: Double, _ weight: Double, _ walk: Int, _ walkKm: Double, _ run: Int, _ runKm: Double, _ stairs: Int) {
        var failures: [Failure] = []
        var actual = "운동 표 없음"
        if let v = Self.values(kcal: kcal, weight: weight) {
            actual = "걷기 \(ExerciseEquivalent.durationText(minutes: v.0))(\(v.1.map { "\($0)" } ?? "-")km), 러닝 \(ExerciseEquivalent.durationText(minutes: v.2))(\(v.3.map { "\($0)" } ?? "-")km), 천국의 계단 \(ExerciseEquivalent.durationText(minutes: v.4))"
            if v.0 != walk || v.1 != walkKm || v.2 != run || v.3 != runKm || v.4 != stairs {
                failures.append(Failure(type: .calories, message: "기대 걷기 \(walk)분 \(walkKm)km, 러닝 \(run)분 \(runKm)km, 계단 \(stairs)분"))
            }
        } else {
            failures.append(Failure(type: .error, message: "ExerciseEquivalents.json 없음"))
        }
        report(suite: "운동 환산", id: id, input: "\(Int(kcal))kcal, 체중 \(Int(weight))kg",
               expected: "걷기 \(ExerciseEquivalent.durationText(minutes: walk))(\(walkKm)km), 러닝 \(ExerciseEquivalent.durationText(minutes: run))(\(runKm)km), 천국의 계단 \(ExerciseEquivalent.durationText(minutes: stairs))",
               actual: actual, failures: failures)
    }

    @Test("시간 표기(60분 경계)")
    func durationText() {
        let cases = [(59, "59분"), (60, "1시간"), (61, "1시간 1분"), (120, "2시간"), (215, "3시간 35분")]
        let failures = cases.compactMap { minutes, text in
            ExerciseEquivalent.durationText(minutes: minutes) == text ? nil
                : Failure(type: .displayText, message: "\(minutes)분 → \(ExerciseEquivalent.durationText(minutes: minutes)) (기대 \(text))")
        }
        report(suite: "운동 환산", id: "E04", input: "59·60·61·120·215분", expected: cases.map(\.1).joined(separator: ", "),
               actual: cases.map { ExerciseEquivalent.durationText(minutes: $0.0) }.joined(separator: ", "), failures: failures)
    }

    @Test("체중 선택 순서와 65kg 대체")
    func weightOrder() {
        let cases: [(Int?, Int?, Double, Bool)] = [
            (702, 800, 70.2, false),   // 최근 체중 기록
            (nil, 800, 80, false),     // 프로필 체중
            (nil, nil, 65, true),      // 둘 다 없음
            (150, nil, 65, true),      // 20kg 미만
            (3100, 700, 70, false),    // 기록이 300kg 초과면 프로필
            (3100, 3200, 65, true),    // 둘 다 범위 밖
        ]
        var failures: [Failure] = []
        for (record, profile, kg, fallback) in cases {
            let weight = ExerciseEquivalentCatalog.weight(latestRecordTenthsKG: record, profileTenthsKG: profile)
            if weight.kg != kg || weight.isFallback != fallback {
                failures.append(Failure(type: .amount, message: "기록 \(record.map(String.init) ?? "-") 프로필 \(profile.map(String.init) ?? "-") → \(weight.kg)kg \(weight.isFallback) (기대 \(kg)kg \(fallback))"))
            }
        }
        report(suite: "운동 환산", id: "E05", input: "체중 기록·프로필 조합 6개", expected: "기록 → 프로필 → 65kg, 20~300kg만",
               actual: failures.isEmpty ? "6개 모두 기대대로" : "\(failures.count)개 다름", failures: failures)
    }

    private static func analyzer(_ script: MealCase.LLM) -> ExerciseGameAnalyzer {
        // 전체 테스트를 병렬로 돌리면 시뮬레이터가 느려져 기본 60초 제한에 걸릴 수 있어 넉넉히 둔다(분석 규칙과 무관).
        ExerciseGameAnalyzer(analyzer: AIMealEntryService(interpreter: FakeMealFoodInterpreter(script: script), catalog: FoodCatalogService()),
                             timeout: .seconds(180))
    }

    private static func llm(food: String? = nil, foods: [String]? = nil, portion: Double? = nil) -> MealCase.LLM {
        var script = MealCase.LLM(food: food, brand: nil, portion: portion.map { .init(amount: $0, unit: nil) }, pick: nil, estimate: nil)
        script.foods = foods
        return script
    }

    @Test("분석 흐름(가짜 해석기)", arguments: [
        // id, 입력, 해석기 음식, 여러 음식, 기대 표시 이름(nil이면 실패 기대), 최소 kcal, 최대 kcal
        ("Y01", "숯불쭈꾸미 1인분", "숯불쭈꾸미", [String](), "쭈꾸미", 1.0, 2000.0),        // 비슷한 음식 질문 → 첫 선택지
        ("Y02", "후라이드치킨 한마리", "후라이드치킨", [], "후라이드치킨 1마리", 2000.0, 2200.0), // 열량 확인 질문 → 그대로 기록
        ("Y03", "마라탕이랑 공기밥", "", ["마라탕", "공기밥"], "마라탕 외 1개", 1270.0, 1285.0), // 두 음식 합산(926.7 + 349)
        ("Y04", "알수없는음식이름", "", [], "", 0.0, 0.0),                                   // 실패
    ])
    func flow(_ id: String, _ input: String, _ food: String, _ foods: [String], _ expectedName: String, _ minKcal: Double, _ maxKcal: Double) async {
        let script = Self.llm(food: food.isEmpty ? nil : food, foods: foods.isEmpty ? nil : foods, portion: 200)
        var failures: [Failure] = []
        var actual: String
        do {
            let result = try await Self.analyzer(script).analyze(input)
            actual = "\(result.title) \(result.kcal.formatted(.number.precision(.fractionLength(0...1))))kcal"
            if expectedName.isEmpty {
                failures.append(Failure(type: .error, message: "실패해야 하는데 결과가 나옴"))
            } else {
                if !result.displayName.contains(expectedName) {
                    failures.append(Failure(type: .name, message: "표시 이름 ‘\(result.displayName)’에 ‘\(expectedName)’ 없음"))
                }
                if !(minKcal...maxKcal).contains(result.kcal) {
                    failures.append(Failure(type: .calories, message: "\(result.kcal)kcal (기대 \(minKcal)~\(maxKcal))"))
                }
            }
        } catch {
            actual = "실패: \(error)"
            if !expectedName.isEmpty { failures.append(Failure(type: .error, message: "실패함: \(error)")) }
        }
        report(suite: "운동 환산", id: id, input: input,
               expected: expectedName.isEmpty ? "실패(못 찾은 음식)" : "\(expectedName), \(Int(minKcal))~\(Int(maxKcal))kcal",
               actual: actual, failures: failures)
    }

    @Test("결과를 식사 기록으로 저장하지 않음")
    func noMealRecord() async throws {
        let container = try ModelContainer(for: UserProfile.self, MealRecord.self, WeightRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let before = try context.fetchCount(FetchDescriptor<MealRecord>())
        for (input, script) in [("마라탕", Self.llm(food: "마라탕", portion: 500)),
                                ("후라이드치킨 한마리", Self.llm(food: "후라이드치킨")),
                                ("알수없는음식이름", Self.llm())] {
            _ = try? await Self.analyzer(script).analyze(input)
        }
        let after = try context.fetchCount(FetchDescriptor<MealRecord>())
        let failures = after == before ? [] : [Failure(type: .error, message: "MealRecord \(before) → \(after)")]
        report(suite: "운동 환산", id: "Y05", input: "성공 2개·실패 1개 분석", expected: "MealRecord 0개 그대로",
               actual: "MealRecord \(before) → \(after)", failures: failures)
    }

    @Test("결과 표시 이름", arguments: [
        ("X01", "마라탕", "마라탕", [String](), 500.0, "마라탕 1인분은"),
        ("X02", "치킨 반마리", "치킨", [], 300.0, "치킨 반마리는"),
        ("X03", "마라탕이랑 공기밥", "", ["마라탕", "공기밥"], 200.0, "마라탕 외 1개는"),
    ])
    func displayName(_ id: String, _ input: String, _ food: String, _ foods: [String], _ portion: Double, _ expected: String) async {
        let script = Self.llm(food: food.isEmpty ? nil : food, foods: foods.isEmpty ? nil : foods, portion: portion)
        var failures: [Failure] = []
        var actual: String
        do {
            let result = try await Self.analyzer(script).analyze(input)
            actual = result.title
            if result.title != expected { failures.append(Failure(type: .name, message: "‘\(result.title)’ (기대 ‘\(expected)’)")) }
        } catch {
            actual = "실패: \(error)"
            failures.append(Failure(type: .error, message: "\(error)"))
        }
        report(suite: "운동 환산", id: id, input: input, expected: expected, actual: actual, failures: failures)
    }

    @Test("배너 김 멈춤 조건")
    func bannerSteamPause() {
        // (화면에 보임, 운동 환산 화면이 떠 있음, 앱 활성) → 멈춤
        let cases: [(Bool, Bool, Bool, Bool)] = [
            (true, false, true, false),   // 보이고 덮이지 않음 → 움직임
            (false, false, true, true),   // 스크롤·탭 전환으로 안 보임
            (true, true, true, true),     // 운동 환산 화면이 떠 있음
            (true, false, false, true),   // 앱이 활성 상태가 아님
        ]
        let failures = cases.compactMap { onScreen, covered, active, paused in
            ExerciseGameBanner.isSteamPaused(isOnScreen: onScreen, isCovered: covered, isActive: active) == paused ? nil
                : Failure(type: .displayText, message: "보임 \(onScreen) 덮임 \(covered) 활성 \(active) → 기대 멈춤 \(paused)")
        }
        report(suite: "운동 환산", id: "B01", input: "보임·덮임·활성 조합 4개", expected: "보이고 덮이지 않고 활성일 때만 움직임",
               actual: failures.isEmpty ? "4개 모두 기대대로" : "\(failures.count)개 다름", failures: failures)
    }

    @Test("조사 은/는")
    func particle() {
        let cases = [("마라탕 1인분", "마라탕 1인분은"), ("치킨 반마리", "치킨 반마리는"), ("마라탕 외 1개", "마라탕 외 1개는"),
                     ("탕수육 300g", "탕수육 300g은"), ("콜라 500mL", "콜라 500mL는"), ("쌀밥 2공기", "쌀밥 2공기는")]
        let failures = cases.compactMap { text, expected in
            ExerciseGameAnalyzer.withTopicParticle(text) == expected ? nil
                : Failure(type: .displayText, message: "\(ExerciseGameAnalyzer.withTopicParticle(text)) (기대 \(expected))")
        }
        report(suite: "운동 환산", id: "X04", input: cases.map(\.0).joined(separator: ", "), expected: cases.map(\.1).joined(separator: ", "),
               actual: cases.map { ExerciseGameAnalyzer.withTopicParticle($0.0) }.joined(separator: ", "), failures: failures)
    }
}

/// 운동 환산 화면 스크린샷(#49). ONEULSIK_SNAPSHOT_DIR이 있을 때만 실행한다(평소 run_tests.sh에서는 건너뜀).
/// 테스트 호스트 앱의 창에 실제 화면을 띄워 drawHierarchy로 그린다(입력칸도 그려진다). 애니메이션 중간은 고정 상태(ExerciseGameSnapshot)로 만든다.
@MainActor
// 창을 띄워 그리는 테스트라 서로 겹치지 않게 차례로 돌린다.
@Suite("운동 환산 스크린샷", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ONEULSIK_SNAPSHOT_DIR"] != nil))
struct ExerciseGameSnapshotTests {
    private static let directory = ProcessInfo.processInfo.environment["ONEULSIK_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }

    private func capture<V: View>(_ view: V, name: String) async throws {
        guard let directory = Self.directory,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(1.2))
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 파일 이름 앞에 화면 크기(pt)를 붙인다(예: 393x852_6_C_result.png).
        let bounds = window.bounds
        try image.pngData()?.write(to: directory.appendingPathComponent("\(Int(bounds.width))x\(Int(bounds.height))_\(name).png"))
        window.isHidden = true
    }

    private func game(_ snapshot: ExerciseGameSnapshot) -> some View {
        ExerciseGameView(weightKG: 65, usesFallbackWeight: true, analyzer: ExerciseGameAnalyzer(), snapshot: snapshot, onClose: {})
    }

    /// 배너 김이 움직이는지 픽셀로 본다. 덮이지 않음 → 움직임, 덮임(운동 환산 화면이 뜬 상태) → 멈춤, 다시 덮이지 않음 → 다시 움직임.
    @Test("배너 김 멈춤·재개")
    func bannerSteamResumes() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let state = BannerCoverState()
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: BannerHarness(state: state))
        window.makeKeyAndVisible()
        // 김 영역(배너 왼쪽 위, 화면 위 16 + 배너 안 y 0~40)
        let region = CGRect(x: 16 + 20, y: window.safeAreaInsets.top + 16, width: 60, height: 40)
        func capture() -> Data? {
            // 렌더러 bounds를 (0,0)에서 시작하게 하고 직접 옮긴다(bounds: region이면 원점이 두 번 옮겨진다).
            let image = UIGraphicsImageRenderer(size: region.size).image { context in
                context.cgContext.translateBy(x: -region.minX, y: -region.minY)
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            return image.pngData()
        }
        func moving() async throws -> Bool {
            let first = capture()
            try await Task.sleep(for: .milliseconds(450))
            let second = capture()
            return second != first
        }
        try await Task.sleep(for: .seconds(1.5))
        let before = try await moving()
        state.covered = true
        try await Task.sleep(for: .milliseconds(400))
        let whileCovered = try await moving()
        state.covered = false
        try await Task.sleep(for: .milliseconds(400))
        let after = try await moving()
        window.isHidden = true
        var failures: [Failure] = []
        if !before { failures.append(Failure(type: .displayText, message: "처음에 김이 움직이지 않음")) }
        if whileCovered { failures.append(Failure(type: .displayText, message: "덮인 동안 김이 움직임")) }
        if !after { failures.append(Failure(type: .displayText, message: "덮개를 닫은 뒤 김이 다시 움직이지 않음")) }
        report(suite: "운동 환산 스크린샷", id: "B02", input: "배너 김 영역 픽셀(0.45초 간격)",
               expected: "움직임 → 덮인 동안 멈춤 → 닫은 뒤 다시 움직임",
               actual: "처음 \(before ? "움직임" : "멈춤"), 덮인 동안 \(whileCovered ? "움직임" : "멈춤"), 닫은 뒤 \(after ? "움직임" : "멈춤")",
               failures: failures)
    }

    /// 실제 홈(HomeView, 배너가 UIKit 스크롤 NoBounceScrollView 안의 별도 UIHostingController에 있음)에서 김이 움직이는지 본다.
    /// 홈에서 움직이는 것은 배너 김뿐이라 0.45초 간격으로 찍은 창 전체가 달라지면 김이 움직이는 것이다.
    @Test("홈 배너 김이 홈 스크롤 안에서 움직임")
    func homeBannerSteamMoves() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let container = try ModelContainer(for: UserProfile.self, MealRecord.self, WeightRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let profile = UserProfile(kakaoUserID: 1, nickname: "전시", weightTenthsKG: 650, hasCompletedOnboarding: true)
        container.mainContext.insert(profile)
        let home = HomeView(profile: profile, mealRecordStore: MealRecordStore(modelContext: container.mainContext),
                            weightRecordStore: WeightRecordStore(modelContext: container.mainContext), aiReportState: .unavailable)
            .modelContainer(container)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: home)
        window.makeKeyAndVisible()
        func capture() -> Data? {
            UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }.pngData()
        }
        try await Task.sleep(for: .seconds(1.5))
        let first = capture()
        try await Task.sleep(for: .milliseconds(450))
        let moving = capture() != first
        window.isHidden = true
        report(suite: "운동 환산 스크린샷", id: "B03", input: "HomeView 창 전체(0.45초 간격)", expected: "배너 김이 움직임",
               actual: moving ? "움직임" : "멈춤",
               failures: moving ? [] : [Failure(type: .displayText, message: "홈 스크롤 안에서 배너 김이 움직이지 않음")])
    }

    @Test("화면 스크린샷")
    func screens() async throws {
        let result = ExerciseGameResult(displayName: "마라탕 1인분", kcal: 926.7)
        try await capture(game(.empty), name: "2_A_empty")
        try await capture(game(.typing("마라탕")), name: "3_A_typing")
        try await capture(game(.falling("마라탕", 0.55)), name: "4_B_falling")
        try await capture(game(.filled("마라탕")), name: "5_B_filled")
        try await capture(game(.result(result)), name: "6_C_result")
        try await capture(game(.failure("알수없는음식")), name: "7_failure")

        let container = try ModelContainer(for: UserProfile.self, MealRecord.self, WeightRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let profile = UserProfile(kakaoUserID: 1, nickname: "전시", weightTenthsKG: 650, hasCompletedOnboarding: true)
        container.mainContext.insert(profile)
        let home = HomeView(profile: profile, mealRecordStore: MealRecordStore(modelContext: container.mainContext),
                            weightRecordStore: WeightRecordStore(modelContext: container.mainContext), aiReportState: .unavailable)
            .modelContainer(container)
        try await capture(home, name: "1_home_banner")
    }
}

@Observable
@MainActor
final class BannerCoverState {
    var covered = false
}

private struct BannerHarness: View {
    let state: BannerCoverState

    // 홈처럼 UIKit 스크롤(NoBounceScrollView) 안에 배너를 둔다.
    var body: some View {
        NoBounceScrollView {
            VStack {
                ExerciseGameBanner(isCovered: state.covered) {}
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
    }
}

/// 운동 환산 화면 1번의 뒤로가기 버튼(48×48)을 실제 터치로 누른다(#49). 테스트 호스트 앱 창에 화면을 띄우고
/// TouchSynthesizer로 UITouch를 보내 onClose가 불리는지 본다. 창을 띄우므로 차례로 돌린다.
@MainActor
@Suite("운동 환산 뒤로가기", .serialized)
struct ExerciseGameBackButtonTests {
    private final class CloseCounter { var count = 0 }

    private func present(_ counter: CloseCounter) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: ExerciseGameView(
            weightKG: 65, usesFallbackWeight: true, analyzer: ExerciseGameAnalyzer(), onClose: { counter.count += 1 }))
        window.makeKeyAndVisible()
        return window
    }

    /// 전체 테스트를 병렬로 돌리면 메인 스레드가 바빠 탭 처리가 늦어질 수 있어 조건이 될 때까지 기다린다(최대 timeout).
    private func wait(upTo timeout: Duration, until condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition(), clock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
    }

    private func firstResponderField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField, field.isFirstResponder { return field }
        for subview in view.subviews { if let found = firstResponderField(in: subview) { return found } }
        return nil
    }

    /// 버튼(창 기준 x 4~52, y 안전 영역 위 + 4~52) 안 네 모서리 근처(가장자리에서 4pt)와 아이콘 가운데
    private func points(_ window: UIWindow) -> [(String, CGPoint)] {
        let top = window.safeAreaInsets.top + 4
        return [("아이콘 가운데", CGPoint(x: 28, y: top + 24)),
                ("왼쪽 위", CGPoint(x: 8, y: top + 4)), ("오른쪽 위", CGPoint(x: 48, y: top + 4)),
                ("왼쪽 아래", CGPoint(x: 8, y: top + 44)), ("오른쪽 아래", CGPoint(x: 48, y: top + 44))]
    }

    @Test("뒤로가기 48×48 어디를 눌러도 닫힘")
    func backButtonEdges() async throws {
        var results: [String] = []
        var failures: [Failure] = []
        // 준비: 전체 테스트를 병렬로 돌리면 첫 창의 첫 탭이 늦게 처리될 수 있어, 버튼과 먼 빈 곳(배경)을 한 번 눌러 터치 경로를 데운다.
        let probe = try present(CloseCounter())
        let cases = points(probe)
        try await Task.sleep(for: .milliseconds(1500))
        try await TouchSynthesizer.tap(CGPoint(x: probe.bounds.midX, y: probe.bounds.midY), in: probe)
        try await Task.sleep(for: .milliseconds(500))
        probe.isHidden = true
        for (name, point) in cases {
            let counter = CloseCounter()
            let window = try present(counter)
            try await Task.sleep(for: .milliseconds(1200))
            try await TouchSynthesizer.tap(point, in: window)
            try await wait(upTo: .seconds(3)) { counter.count > 0 }
            try await Task.sleep(for: .milliseconds(200))
            window.isHidden = true
            results.append("\(name) \(counter.count == 1 ? "닫힘" : "안 닫힘")")
            if counter.count != 1 { failures.append(Failure(type: .displayText, message: "\(name)(\(Int(point.x)), \(Int(point.y)))을 눌러도 닫히지 않음")) }
        }
        report(suite: "운동 환산 뒤로가기", id: "H01", input: "뒤로가기 버튼 안 5곳 탭(아이콘 가운데·네 모서리 4pt 안쪽)",
               expected: "5곳 모두 onClose 1번", actual: results.joined(separator: ", "), failures: failures)
    }

    @Test("입력칸에 포커스가 있을 때 뒤로가기 한 번에 닫힘")
    func backButtonWithKeyboard() async throws {
        let counter = CloseCounter()
        let window = try present(counter)
        try await Task.sleep(for: .milliseconds(1200))
        // 입력칸(가로 가운데, 안전 영역 위 + 252~308)을 눌러 포커스를 준다.
        try await TouchSynthesizer.tap(CGPoint(x: window.bounds.midX, y: window.safeAreaInsets.top + 280), in: window)
        try await wait(upTo: .seconds(3)) { firstResponderField(in: window) != nil }
        // 키보드가 올라오는 애니메이션이 끝날 때까지
        try await Task.sleep(for: .milliseconds(800))
        let focusedBefore = firstResponderField(in: window) != nil
        let corner = points(window)[4]
        try await TouchSynthesizer.tap(corner.1, in: window)
        try await wait(upTo: .seconds(3)) { counter.count > 0 }
        try await Task.sleep(for: .milliseconds(300))
        let focusedAfter = firstResponderField(in: window) != nil
        window.isHidden = true
        var failures: [Failure] = []
        if !focusedBefore { failures.append(Failure(type: .displayText, message: "입력칸을 눌러도 포커스가 가지 않음(시험 준비 실패)")) }
        if counter.count != 1 { failures.append(Failure(type: .displayText, message: "포커스가 있을 때 뒤로가기 \(corner.0)를 한 번 눌러 닫히지 않음(onClose \(counter.count)번)")) }
        if focusedAfter { failures.append(Failure(type: .displayText, message: "닫은 뒤에도 입력칸 포커스가 남음")) }
        report(suite: "운동 환산 뒤로가기", id: "H02", input: "입력칸 탭(포커스) → 뒤로가기 \(corner.0) 한 번 탭",
               expected: "포커스 해제, onClose 1번",
               actual: "탭 전 포커스 \(focusedBefore ? "있음" : "없음"), onClose \(counter.count)번, 탭 뒤 포커스 \(focusedAfter ? "남음" : "없음")",
               failures: failures)
    }
}
