import Foundation
import Observation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import ONEULSIK

/// 화면 이동(NavigationStack push, AppRouter)과 스와이프 뒤로가기, 주간 리포트 뒤로가기 누르는 영역.
/// 창을 띄우는 묶음이라 운동 환산 창 탭 묶음(ExerciseGameTouchTests)과 같은 상위 묶음에서 차례로 돈다.
extension ExerciseGameTouchTests {
@MainActor
@Suite("화면 이동")
struct Navigation {
    private final class Counter { var count = 0 }

    private func scene() throws -> UIWindowScene {
        try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    }

    private func window<V: View>(_ view: V) throws -> UIWindow {
        let window = UIWindow(windowScene: try scene())
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        return window
    }

    private func wait(upTo timeout: Duration, until condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition(), clock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
    }

    /// 실제 메인 화면(탭 + NavigationStack)을 창에 띄운다.
    private func mainTab(_ router: AppRouter) throws -> (UIWindow, ModelContainer) {
        let container = try ModelContainer(for: UserProfile.self, MealRecord.self, WeightRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let profile = UserProfile(kakaoUserID: 1, nickname: "전시", weightTenthsKG: 650, hasCompletedOnboarding: true)
        context.insert(profile)
        let view = MainTabView(profile: profile, mealRecordStore: MealRecordStore(modelContext: context),
                               onboardingStore: OnboardingStore(modelContext: context),
                               weightRecordStore: WeightRecordStore(modelContext: context),
                               onDeleteAccount: { false }, onLogout: {}, router: router)
            .modelContainer(container)
        return (try window(view), container)
    }

    private func navigationController(in view: UIView?) -> UINavigationController? {
        var queue: [UIView] = view.map { [$0] } ?? []
        while !queue.isEmpty {
            let current = queue.removeFirst()
            var responder: UIResponder? = current.next
            while let r = responder {
                if let navigation = r as? UINavigationController { return navigation }
                responder = r.next
            }
            queue.append(contentsOf: current.subviews)
        }
        return nil
    }

    /// 기본 스와이프 뒤로가기(interactivePopGestureRecognizer)가 켜져 있고, 지금 화면에서 시작을 허용하는지.
    /// 합성 터치에는 '화면 가장자리에서 시작함' 정보가 없어 가장자리 제스처가 일어나지 않으므로, 제스처의 판정(delegate)을 직접 묻는다.
    /// 실제 손가락 스와이프는 시뮬레이터의 가장자리 스와이프로 따로 확인한다.
    private func popGestureAllows(_ window: UIWindow) -> (installed: Bool, allows: Bool) {
        guard let navigation = navigationController(in: window), let gesture = navigation.interactivePopGestureRecognizer,
              let delegate = gesture.delegate else { return (false, false) }
        let installed = gesture.isEnabled && String(describing: type(of: delegate)).contains("Coordinator")
        return (installed, delegate.gestureRecognizerShouldBegin?(gesture) ?? true)
    }

    // MARK: - 라우터

    @Test("경로별 push·pop 스택")
    func routerStack() async throws {
        let router = AppRouter()
        var failures: [Failure] = []
        func expect(_ routes: [AppRoute], _ step: String) {
            if router.routes != routes { failures.append(Failure(type: .displayText, message: "\(step): \(router.routes) (기대 \(routes))")) }
        }
        let all: [AppRoute] = [.weeklyReport, .exerciseGame, .mealEntry, .foodSearch, .foodQuantity, .profileEdit("gender"), .settings]
        for route in all {
            router.push(route) { Color.clear }
            expect([route], "\(route) push")
            router.pop()
            expect([], "\(route) pop")
        }
        router.push(.mealEntry) { Color.clear }
        router.push(.foodSearch) { Color.clear }
        router.push(.foodQuantity) { Color.clear }
        expect([.mealEntry, .foodSearch, .foodQuantity], "식사 기록 → 검색 → 수량")
        router.pop()
        expect([.mealEntry, .foodSearch], "수량에서 뒤로")
        router.pop()
        expect([.mealEntry], "검색에서 뒤로")
        router.push(.foodSearch) { Color.clear }
        router.pop(.mealEntry)
        expect([], "식사 기록부터 모두 내림")
        router.push(.settings) { Color.clear }
        router.popToRoot()
        expect([], "로그아웃(스택 비움)")
        report(suite: "화면 이동", id: "Z01", input: "7개 경로 push·pop, 식사 기록 흐름 한 단계씩 뒤로, 처음까지 내림",
               expected: "스택이 기대대로", actual: failures.isEmpty ? "모두 기대대로" : "\(failures.count)개 다름", failures: failures)
    }

    @Test("주간 리포트가 빠지면(버튼·스와이프) 홈 맨 위 스크롤 트리거가 오름")
    func weeklyReportPopTrigger() async throws {
        let router = AppRouter()
        let trigger = Counter()
        // HomeView.openWeeklyReport와 같은 연결: 빠질 때 reportDismissScrollToTopTrigger += 1
        router.push(.weeklyReport, onPop: { trigger.count += 1 }) { Color.clear }
        router.pop(.weeklyReport)                      // 뒤로가기 버튼
        try await wait(upTo: .seconds(1)) { trigger.count == 1 }
        let afterButton = trigger.count
        router.push(.weeklyReport, onPop: { trigger.count += 1 }) { Color.clear }
        router.path.removeLast()                       // 스와이프로 NavigationStack이 path를 줄인 경우
        try await wait(upTo: .seconds(1)) { trigger.count == 2 }
        let afterSwipe = trigger.count
        let failures = (afterButton == 1 && afterSwipe == 2) ? [] :
            [Failure(type: .displayText, message: "트리거 버튼 뒤 \(afterButton), 스와이프 뒤 \(afterSwipe)")]
        report(suite: "화면 이동", id: "Z02", input: "주간 리포트 push → 버튼 pop, 다시 push → path 줄임(스와이프)",
               expected: "트리거 1 → 2", actual: "버튼 뒤 \(afterButton), 스와이프 뒤 \(afterSwipe)", failures: failures)
    }

    // MARK: - 식사 기록 흐름(실제 NavigationStack, 화면 코드와 같은 onPop·dismiss 연결, 가짜 저장소)

    @Observable
    @MainActor
    final class FlowProbe {
        var saved: [String] = []
        var reloadCount = 0
        var completeQuantity: (() -> Void)?
    }

    private struct FlowHost: View {
        @Bindable var router: AppRouter
        var body: some View {
            NavigationStack(path: $router.path) {
                Color.white
                    .navigationDestination(for: AppRouteEntry.self) { entry in
                        entry.makeView().environment(\.appRouteEntryID, entry.id)
                    }
            }
            .environment(\.appRouter, router)
        }
    }

    /// MealEntryView처럼: 검색을 push하고, 검색이 빠질 때 검색에서 저장했으면 onSaved 뒤 dismiss
    private struct EntryScreen: View {
        let probe: FlowProbe
        let onSaved: () -> Void
        @Environment(\.dismiss) private var dismiss
        @Environment(\.appRouter) private var router
        @State private var savedThroughSearch = false
        @State private var opened = false
        var body: some View {
            Color.white.task {
                guard !opened else { return }
                opened = true
                // 사용자가 누르는 것처럼 앞 화면이 다 들어온 뒤 연다.
                try? await Task.sleep(for: .milliseconds(700))
                router.push(.foodSearch, onPop: { finishFoodSearch() }) {
                    SearchScreen(probe: probe, onSaved: { savedThroughSearch = true })
                }
            }
        }
        private func finishFoodSearch() {
            guard savedThroughSearch else { return }
            onSaved()
            dismiss()
        }
    }

    /// FoodSearchView처럼: 수량을 push하고, 확정하면 저장 → 수량 pop → 수량이 빠질 때 onSaved 뒤 dismiss
    private struct SearchScreen: View {
        let probe: FlowProbe
        let onSaved: () -> Void
        @Environment(\.dismiss) private var dismiss
        @Environment(\.appRouter) private var router
        @State private var shouldDismissAfterSaving = false
        @State private var opened = false
        var body: some View {
            Color.white.task {
                guard !opened else { return }
                opened = true
                try? await Task.sleep(for: .milliseconds(700))
                let router = self.router
                router.push(.foodQuantity, onPop: { finishQuantitySelection() }) {
                    Color.white.onAppear {
                        probe.completeQuantity = {
                            probe.saved.append("시험 음식")   // 가짜 저장소
                            shouldDismissAfterSaving = true
                            router.pop(.foodQuantity)
                        }
                    }
                }
            }
        }
        private func finishQuantitySelection() {
            guard shouldDismissAfterSaving else { return }
            shouldDismissAfterSaving = false
            onSaved()
            dismiss()
        }
    }

    @Test("식사 기록 흐름: 수량 확정 → 검색·식사 기록이 닫히고 기록 화면 새로 읽음")
    func mealEntryFlow() async throws {
        let router = AppRouter()
        let probe = FlowProbe()
        let window = try window(FlowHost(router: router))
        try await Task.sleep(for: .milliseconds(600))
        // RecordView.openMealEntry와 같은 연결: 빠질 때 viewModel.reload()
        router.push(.mealEntry, onPop: { probe.reloadCount += 1 }) {
            EntryScreen(probe: probe, onSaved: { probe.reloadCount += 0 })
        }
        try await wait(upTo: .seconds(5)) { router.routes == [.mealEntry, .foodSearch, .foodQuantity] && probe.completeQuantity != nil }
        let stackBefore = router.routes
        probe.completeQuantity?()
        try await wait(upTo: .seconds(5)) { router.path.isEmpty && probe.reloadCount > 0 }
        try await Task.sleep(for: .milliseconds(500))
        window.isHidden = true
        var failures: [Failure] = []
        if stackBefore != [.mealEntry, .foodSearch, .foodQuantity] { failures.append(Failure(type: .displayText, message: "시험 준비: 스택 \(stackBefore)")) }
        if probe.saved != ["시험 음식"] { failures.append(Failure(type: .displayText, message: "저장 \(probe.saved)")) }
        if !router.path.isEmpty { failures.append(Failure(type: .displayText, message: "확정 뒤 스택이 남음: \(router.routes)")) }
        if probe.reloadCount != 1 { failures.append(Failure(type: .displayText, message: "기록 화면 새로 읽기 \(probe.reloadCount)번")) }
        report(suite: "화면 이동", id: "Z03", input: "식사 기록 → 검색 → 수량 push, 수량 확정(가짜 저장)",
               expected: "저장 1번, 수량·검색·식사 기록 모두 빠짐, 기록 화면 새로 읽기 1번",
               actual: "전 스택 \(stackBefore.count)개, 저장 \(probe.saved.count)번, 남은 스택 \(router.path.count)개, 새로 읽기 \(probe.reloadCount)번",
               failures: failures)
    }

    // MARK: - 실제 메인 화면에서 버튼·스와이프 뒤로가기

    @Test("주간 리포트: 뒤로가기 버튼 pop, 스와이프 제스처 허용")
    func weeklyReportPop() async throws {
        let router = AppRouter()
        let (window, container) = try mainTab(router)
        _ = container
        try await Task.sleep(for: .milliseconds(1200))
        var failures: [Failure] = []
        var actual: [String] = []
        let popped = Counter()
        func pushReport() {
            router.push(.weeklyReport, onPop: { popped.count += 1 }) {
                WeeklyReportView(preview: true, onBack: { router.pop(.weeklyReport) })
            }
        }
        // 버튼
        pushReport()
        try await Task.sleep(for: .milliseconds(1200))
        try await TouchSynthesizer.tap(CGPoint(x: 28, y: window.safeAreaInsets.top + 28), in: window)
        try await wait(upTo: .seconds(3)) { router.path.isEmpty }
        try await Task.sleep(for: .milliseconds(800))
        actual.append("버튼 뒤 스택 \(router.path.count)")
        if !router.path.isEmpty { failures.append(Failure(type: .displayText, message: "뒤로가기 버튼으로 빠지지 않음")) }
        // 스와이프: 기본 뒤로가기 제스처가 켜져 있고 시작을 허용하는지, 그리고 스와이프가 끝나면 SwiftUI가 하듯 path가 줄 때 onPop
        pushReport()
        try await Task.sleep(for: .milliseconds(1200))
        // 병렬 실행 때 push 전환이 늦게 끝날 수 있어(전환 중에는 일부러 허용하지 않음) 끝날 때까지 기다린다.
        try await wait(upTo: .seconds(4)) { popGestureAllows(window).allows }
        let gesture = popGestureAllows(window)
        actual.append("스와이프 제스처 설치 \(gesture.installed ? "예" : "아니오")·허용 \(gesture.allows ? "예" : "아니오")")
        if !gesture.installed { failures.append(Failure(type: .displayText, message: "기본 스와이프 뒤로가기 제스처가 이 스택에 설치되지 않음")) }
        if !gesture.allows { failures.append(Failure(type: .displayText, message: "주간 리포트에서 스와이프 뒤로가기를 허용하지 않음")) }
        router.path.removeLast()
        try await wait(upTo: .seconds(2)) { popped.count == 2 }
        try await Task.sleep(for: .milliseconds(800))
        let rootGesture = popGestureAllows(window)
        actual.append("빠짐 알림 \(popped.count)번, 홈에서 제스처 허용 \(rootGesture.allows ? "예" : "아니오")")
        if popped.count != 2 { failures.append(Failure(type: .displayText, message: "빠짐 알림(onPop) \(popped.count)번")) }
        if rootGesture.allows { failures.append(Failure(type: .displayText, message: "스택이 빈 홈에서 스와이프 뒤로가기를 허용함")) }
        window.isHidden = true
        report(suite: "화면 이동", id: "Z04", input: "메인 화면에서 주간 리포트 push → 뒤로가기 버튼, 다시 push → 스와이프 제스처 판정·path 줄임",
               expected: "버튼으로 스택 비움, 제스처 설치·허용, onPop 2번, 홈(스택 빔)에서는 허용 안 함", actual: actual.joined(separator: ", "), failures: failures)
    }

    @Test("운동 환산: 결과 화면은 스와이프가 막히고 입력 화면은 허용")
    func exerciseGamePop() async throws {
        let router = AppRouter()
        let (window, container) = try mainTab(router)
        _ = container
        try await Task.sleep(for: .milliseconds(1200))
        var failures: [Failure] = []
        var actual: [String] = []
        for (name, snapshot, expectPopped) in [("결과 화면", ExerciseGameSnapshot.result(ExerciseGameResult(displayName: "먹고 싶은 음식 1인분", kcal: 927)), false),
                                                ("입력 화면", ExerciseGameSnapshot.empty, true)] {
            router.push(.exerciseGame) {
                ExerciseGameView(weightKG: 65, usesFallbackWeight: true, analyzer: ExerciseGameAnalyzer(), snapshot: snapshot,
                                 onClose: { router.pop(.exerciseGame) })
            }
            try await Task.sleep(for: .milliseconds(1500))
            if expectPopped { try await wait(upTo: .seconds(4)) { popGestureAllows(window).allows } }
            let gesture = popGestureAllows(window)
            actual.append("\(name) 스와이프 \(gesture.allows ? "허용" : "막음")")
            if gesture.allows != expectPopped {
                failures.append(Failure(type: .displayText, message: "\(name): 스와이프 \(gesture.allows ? "허용" : "막음")(기대 \(expectPopped ? "허용" : "막음"))"))
            }
            router.popToRoot()
            try await Task.sleep(for: .milliseconds(800))
        }
        window.isHidden = true
        report(suite: "화면 이동", id: "Z05", input: "메인 화면에서 운동 환산(결과·입력) push → 스와이프 제스처 판정",
               expected: "결과 막음, 입력 허용", actual: actual.joined(separator: ", "), failures: failures)
    }

    @Test("화면별 버튼 뒤로가기로 pop(메인 화면 스택)")
    func buttonBackEveryScreen() async throws {
        let router = AppRouter()
        let (window, container) = try mainTab(router)
        let context = container.mainContext
        let profile = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        let store = MealRecordStore(modelContext: context)
        let onboardingStore = OnboardingStore(modelContext: context)
        let food = FoodCatalogItem(id: "nav-test", name: "시험 음식", servingUnit: "인분", servingGrams: 100,
                                   nutrition: NutritionValues(calories: 100, carbohydrateGrams: 10, proteinGrams: 5, fatGrams: 3))
        try await Task.sleep(for: .milliseconds(1200))
        let top = window.safeAreaInsets.top
        // (이름, push, 뒤로가기 위치: 왼쪽 위 48×48 가운데. 음식 검색은 "취소", 수량 선택은 어두운 바깥)
        let screens: [(String, () -> Void, CGPoint)] = [
            ("주간 리포트", { router.push(.weeklyReport) { WeeklyReportView(preview: true, onBack: { router.pop(.weeklyReport) }) } },
             CGPoint(x: 28, y: top + 28)),
            ("운동 환산", { router.push(.exerciseGame) {
                ExerciseGameView(weightKG: 65, usesFallbackWeight: true, analyzer: ExerciseGameAnalyzer(), onClose: { router.pop(.exerciseGame) })
            } }, CGPoint(x: 28, y: top + 28)),
            ("식사 기록", { router.push(.mealEntry) {
                MealEntryView(profile: profile, mealType: .lunch, recordedAt: .now, mealRecordStore: store, onSaved: {})
            } }, CGPoint(x: 28, y: top + 28)),
            ("음식 검색", { router.push(.foodSearch) {
                FoodSearchView(profile: profile, mealType: .lunch, recordedAt: .now, mealRecordStore: store, onSaved: {})
            } }, CGPoint(x: window.bounds.width - 32, y: top + 36)),
            ("수량 선택", { router.push(.foodQuantity) {
                FoodQuantityPresentation(food: food, onCancel: { router.pop(.foodQuantity) }, onComplete: { _ in })
            } }, CGPoint(x: window.bounds.midX, y: top + 80)),
            ("나의 정보 수정(성별)", { router.push(.profileEdit("gender")) {
                GenderOnboardingView(profile: profile, onboardingStore: onboardingStore, primaryButtonTitle: "저장",
                                     onBack: { router.pop() }, onNext: { router.pop() })
            } }, CGPoint(x: 24, y: top + 28)),
            ("설정", { router.push(.settings) { SettingsView(onBack: { router.pop(.settings) }, onLogout: {}, onDeleteAccount: { false }) } },
             CGPoint(x: 28, y: top + 28)),
        ]
        var results: [String] = []
        var failures: [Failure] = []
        for (name, open, fixedPoint) in screens {
            open()
            try await Task.sleep(for: .milliseconds(1500))
            // 수량 선택은 수량 칸에 포커스가 잡혀 바깥 첫 탭이 키보드만 내리므로, 카드 왼쪽 위 X 버튼을 찾아 누른다.
            // 카드가 키보드 높이에 따라 움직일 수 있어 누를 때마다 위치를 다시 잰다. 병렬 실행 때 합성 탭이 처리되지 않을 수 있어 최대 3번.
            for _ in 0..<3 where !router.path.isEmpty {
                let point = name == "수량 선택" ? (quantityCloseButton(window) ?? fixedPoint) : fixedPoint
                try await TouchSynthesizer.tap(point, in: window)
                try await wait(upTo: .seconds(3)) { router.path.isEmpty }
            }
            results.append("\(name) \(router.path.isEmpty ? "빠짐" : "그대로")")
            if !router.path.isEmpty { failures.append(Failure(type: .displayText, message: "\(name): 뒤로가기로 빠지지 않음") ) }
            router.popToRoot()
            try await Task.sleep(for: .milliseconds(900))
        }
        window.isHidden = true
        report(suite: "화면 이동", id: "Z06", input: "메인 화면 스택에 7개 화면을 하나씩 push → 각 화면의 뒤로가기(취소·바깥) 탭",
               expected: "모두 빠짐", actual: results.joined(separator: ", "), failures: failures)
    }

    /// 수량 선택 카드(밝은 바탕)의 윗변을 찾아 X 버튼(카드 위 + 30, x 28) 위치를 돌려준다.
    private func quantityCloseButton(_ window: UIWindow) -> CGPoint? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let column = CGRect(x: window.bounds.midX, y: 0, width: 1, height: window.bounds.height)
        let image = UIGraphicsImageRenderer(size: column.size, format: format).image { context in
            context.cgContext.translateBy(x: -column.minX, y: 0)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage, cgImage.bitsPerComponent == 8,
              let data = cgImage.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let start = Int(window.safeAreaInsets.top) + 60
        for y in start..<cgImage.height {
            let i = y * cgImage.bytesPerRow
            if Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2]) > 690 { return CGPoint(x: 28, y: CGFloat(y) + 30) }
        }
        return nil
    }

    // MARK: - 주간 리포트 뒤로가기 누르는 영역

    @Test("주간 리포트 뒤로가기 48×48 어디를 눌러도 닫힘")
    func weeklyReportBackEdges() async throws {
        var results: [String] = []
        var failures: [Failure] = []
        let probe = try window(Color.white)
        let top = probe.safeAreaInsets.top + 4
        try await Task.sleep(for: .milliseconds(800))
        try await TouchSynthesizer.tap(CGPoint(x: probe.bounds.midX, y: probe.bounds.midY), in: probe)
        try await Task.sleep(for: .milliseconds(300))
        probe.isHidden = true
        // 헤더 높이 56 가운데에 48×48 버튼(x 4~52): 아이콘 가운데와 네 모서리 4pt 안쪽
        let points: [(String, CGPoint)] = [("아이콘 가운데", CGPoint(x: 28, y: top + 24)),
                                           ("왼쪽 위", CGPoint(x: 8, y: top + 4)), ("오른쪽 위", CGPoint(x: 48, y: top + 4)),
                                           ("왼쪽 아래", CGPoint(x: 8, y: top + 44)), ("오른쪽 아래", CGPoint(x: 48, y: top + 44))]
        for (name, point) in points {
            let counter = Counter()
            let window = try window(WeeklyReportView(preview: true, onBack: { counter.count += 1 }))
            try await Task.sleep(for: .milliseconds(1200))
            try await TouchSynthesizer.tap(point, in: window)
            try await wait(upTo: .seconds(3)) { counter.count > 0 }
            try await Task.sleep(for: .milliseconds(200))
            window.isHidden = true
            results.append("\(name) \(counter.count == 1 ? "닫힘" : "안 닫힘")")
            if counter.count != 1 { failures.append(Failure(type: .displayText, message: "\(name)(\(Int(point.x)), \(Int(point.y)))을 눌러도 닫히지 않음")) }
        }
        report(suite: "주간 리포트 뒤로가기", id: "I01", input: "주간 리포트 뒤로가기 안 5곳 탭(아이콘 가운데·네 모서리 4pt 안쪽)",
               expected: "5곳 모두 onBack 1번", actual: results.joined(separator: ", "), failures: failures)
    }
}
}
