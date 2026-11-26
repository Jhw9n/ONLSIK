import Foundation
import Observation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import ONEULSIK

/// 기록 화면·음식 검색의 + 버튼 누르는 영역(#51). 초록 원(26×26) 바깥을 감싼 영역 전체가 눌리는지 실제 탭으로 본다.
/// 창을 띄우는 묶음이라 운동 환산 창 탭 묶음(ExerciseGameTouchTests)과 같은 상위 묶음에서 차례로 돈다.
extension ExerciseGameTouchTests {
@MainActor
@Suite("+ 버튼 누르는 영역")
struct PlusButton {
    /// 탭 바 없이 화면 하나를 NavigationStack 안에 띄운다(+ 버튼은 라우터로 다음 화면을 push한다).
    private struct Host<Content: View>: View {
        @Bindable var router: AppRouter
        let content: Content
        var body: some View {
            NavigationStack(path: $router.path) {
                content
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: AppRouteEntry.self) { entry in
                        entry.makeView().toolbar(.hidden, for: .navigationBar)
                    }
            }
            .environment(\.appRouter, router)
        }
    }

    private func window<V: View>(_ view: V) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
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

    /// 창 세로선 x에서 초록 원(green03 #4AC364)이 칠해진 구간의 가운데 y들(높이 16~34pt 구간만)
    private func greenCircleCenters(_ window: UIWindow, x: CGFloat) -> [CGFloat] {
        // 원 바깥(왼쪽 22pt)도 초록이면 원이 아니라 초록 카드 안이다(기록 화면 위쪽 요약 카드)
        let outside = Set(greenRows(window, x: x - 22))
        return greenRuns(window, x: x).filter { !outside.contains(Int($0)) }
    }

    private func greenRows(_ window: UIWindow, x: CGFloat) -> [Int] {
        greenColumn(window, x: x).enumerated().compactMap { $0.element ? $0.offset : nil }
    }

    private func greenRuns(_ window: UIWindow, x: CGFloat) -> [CGFloat] {
        var runs: [(start: Int, end: Int)] = []
        for (y, isGreen) in greenColumn(window, x: x).enumerated() where isGreen {
            if let last = runs.last, last.end == y - 1 { runs[runs.count - 1].end = y } else { runs.append((y, y)) }
        }
        return runs.filter { (16...34).contains($0.end - $0.start + 1) }.map { CGFloat($0.start + $0.end + 1) / 2 }
    }

    private func greenColumn(_ window: UIWindow, x: CGFloat) -> [Bool] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let column = CGRect(x: x, y: 0, width: 1, height: window.bounds.height)
        let image = UIGraphicsImageRenderer(size: column.size, format: format).image { context in
            context.cgContext.translateBy(x: -column.minX, y: 0)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage, cgImage.bitsPerComponent == 8,
              let data = cgImage.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        return (0..<cgImage.height).map { y in
            let i = y * cgImage.bytesPerRow
            // 채널 순서(BGRA·RGBA)와 상관없이 초록(가운데 채널이 크고 나머지가 작음)
            return Int(bytes[i + 1]) > 170 && Int(bytes[i]) < 140 && Int(bytes[i + 2]) < 140
        }
    }

    @Test("기록 화면 + 버튼: 원 가운데와 영역 안쪽 모서리 4곳")
    func recordPlusButton() async throws {
        let container = try ModelContainer(for: UserProfile.self, MealRecord.self, WeightRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let profile = UserProfile(kakaoUserID: 1, nickname: "전시", weightTenthsKG: 650, hasCompletedOnboarding: true)
        container.mainContext.insert(profile)
        let store = MealRecordStore(modelContext: container.mainContext)
        let router = AppRouter()
        let window = try window(Host(router: router, content: RecordView(profile: profile, mealRecordStore: store)).modelContainer(container))
        try await Task.sleep(for: .milliseconds(1500))
        // + 원 가운데는 행 오른쪽 끝(창 오른쪽 - 가로 여백 16 - 줄 오른쪽 여백 2 - 56/2)
        let circleX = window.bounds.width - 16 - 2 - 28
        // 원 가운데 세로선은 흰 + 모양에 걸려 초록이 끊기므로 8pt 옆 세로선으로 찾는다(반지름 13 → 초록 약 20pt)
        let centers = greenCircleCenters(window, x: circleX - 8)
        var results: [String] = []
        var failures: [Failure] = []
        if centers.count < 2 {
            failures.append(Failure(type: .displayText, message: "+ 원을 찾지 못함(\(centers.count)개)"))
        }
        let rowHeight = centers.count >= 2 ? centers[1] - centers[0] : 60
        if let center = centers.first {
            // 누르는 영역: 너비 56(원 가운데 ±28) × 줄 높이. 모서리는 4pt 안쪽
            let halfWidth: CGFloat = 28 - 4, halfHeight = rowHeight / 2 - 4
            let points: [(String, CGPoint)] = [
                ("원 가운데", CGPoint(x: circleX, y: center)),
                ("왼쪽 위", CGPoint(x: circleX - halfWidth, y: center - halfHeight)),
                ("오른쪽 위", CGPoint(x: circleX + halfWidth, y: center - halfHeight)),
                ("왼쪽 아래", CGPoint(x: circleX - halfWidth, y: center + halfHeight)),
                ("오른쪽 아래", CGPoint(x: circleX + halfWidth, y: center + halfHeight)),
            ]
            for (name, point) in points {
                for _ in 0..<2 where router.routes != [.mealEntry] {   // 병렬 실행 때 합성 탭이 처리되지 않으면 한 번 더
                    try await TouchSynthesizer.tap(point, in: window)
                    try await wait(upTo: .seconds(3)) { router.routes == [.mealEntry] }
                }
                let opened = router.routes == [.mealEntry]
                results.append("\(name) \(opened ? "열림" : "안 열림")")
                if !opened { failures.append(Failure(type: .displayText, message: "\(name)(\(Int(point.x)), \(Int(point.y)))을 눌러도 식사 기록이 열리지 않음(스택 \(router.routes))")) }
                router.popToRoot()
                try await Task.sleep(for: .milliseconds(900))
            }
        }
        window.isHidden = true
        report(suite: "+ 버튼 누르는 영역", id: "PL01", input: "기록 화면 첫 끼니 + 버튼: 원 가운데와 영역(56 × 줄 높이) 안쪽 모서리 4곳 탭",
               expected: "5곳 모두 식사 기록 화면 열림", actual: results.joined(separator: ", ") + " (줄 높이 \(Int(rowHeight)))",
               failures: failures)
    }

    /// 기록 화면 스크린샷(+ 버튼 크기·자리 확인용). ONEULSIK_SNAPSHOT_DIR이 있을 때만 실행한다(평소 run_tests.sh에서는 건너뜀).
    @Test("기록 화면 스크린샷", .enabled(if: ProcessInfo.processInfo.environment["ONEULSIK_SNAPSHOT_DIR"] != nil))
    func recordSnapshot() async throws {
        let directory = try #require(ProcessInfo.processInfo.environment["ONEULSIK_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) })
        let container = try ModelContainer(for: UserProfile.self, MealRecord.self, WeightRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let profile = UserProfile(kakaoUserID: 1, nickname: "전시", weightTenthsKG: 650, hasCompletedOnboarding: true)
        container.mainContext.insert(profile)
        let store = MealRecordStore(modelContext: container.mainContext)
        let window = try window(Host(router: AppRouter(), content: RecordView(profile: profile, mealRecordStore: store)).modelContainer(container))
        try await Task.sleep(for: .milliseconds(1500))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try image.pngData()?.write(to: directory.appendingPathComponent("\(Int(window.bounds.width))x\(Int(window.bounds.height))_record_plus_button.png"))
        window.isHidden = true
    }

    @Test("음식 검색 + 버튼: 원 가운데와 영역 안쪽 모서리")
    func searchPlusButton() async throws {
        let container = try ModelContainer(for: UserProfile.self, MealRecord.self, WeightRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let profile = UserProfile(kakaoUserID: 1, nickname: "전시", weightTenthsKG: 650, hasCompletedOnboarding: true)
        container.mainContext.insert(profile)
        let store = MealRecordStore(modelContext: container.mainContext)
        let router = AppRouter()
        let window = try window(Host(router: router, content: FoodSearchView(profile: profile, mealType: .lunch, recordedAt: .now,
                                                                            mealRecordStore: store, onSaved: {})).modelContainer(container))
        try await Task.sleep(for: .milliseconds(1200))
        var failures: [Failure] = []
        var results: [String] = []
        // 검색창(위쪽 가운데)을 눌러 검색어를 넣는다
        try await TouchSynthesizer.tap(CGPoint(x: window.bounds.midX - 40, y: window.safeAreaInsets.top + 36), in: window)
        try await Task.sleep(for: .milliseconds(800))
        func focusedField(in view: UIView) -> UITextField? {
            if let field = view as? UITextField, field.isFirstResponder { return field }
            for subview in view.subviews { if let found = focusedField(in: subview) { return found } }
            return nil
        }
        if let field = focusedField(in: window) {
            field.insertText("김밥")
            field.resignFirstResponder()
        } else {
            failures.append(Failure(type: .displayText, message: "검색창에 포커스가 가지 않음"))
        }
        // + 원 가운데는 줄 오른쪽 끝(창 오른쪽 - 가로 여백 16 - 44/2)
        let circleX = window.bounds.width - 16 - 22
        // 검색 결과가 뜰 때까지(묶음 실행에서는 음식 DB 첫 조회가 늦을 수 있다) 최대 10초
        var centers: [CGFloat] = []
        try await wait(upTo: .seconds(10)) {
            centers = greenCircleCenters(window, x: circleX - 8)
            return !centers.isEmpty
        }
        try await Task.sleep(for: .milliseconds(300))
        if let center = centers.first {
            let points: [(String, CGPoint)] = [
                ("원 가운데", CGPoint(x: circleX, y: center)),
                ("왼쪽 위(4pt 안쪽)", CGPoint(x: circleX - 22 + 4, y: center - 24 + 4)),
                ("오른쪽 아래(4pt 안쪽)", CGPoint(x: circleX + 22 - 4, y: center + 24 - 4)),
            ]
            for (name, point) in points {
                for _ in 0..<2 where router.routes != [.foodQuantity] {
                    try await TouchSynthesizer.tap(point, in: window)
                    try await wait(upTo: .seconds(3)) { router.routes == [.foodQuantity] }
                }
                let opened = router.routes == [.foodQuantity]
                results.append("\(name) \(opened ? "열림" : "안 열림")")
                if !opened { failures.append(Failure(type: .displayText, message: "\(name)(\(Int(point.x)), \(Int(point.y)))을 눌러도 수량 선택이 열리지 않음")) }
                router.popToRoot()
                try await Task.sleep(for: .milliseconds(900))
            }
        } else {
            failures.append(Failure(type: .displayText, message: "검색 결과의 + 원을 찾지 못함"))
        }
        window.isHidden = true
        report(suite: "+ 버튼 누르는 영역", id: "PL02", input: "음식 검색 ‘김밥’ 첫 결과 + 버튼: 원 가운데와 영역(44×48) 안쪽 모서리 2곳 탭",
               expected: "모두 수량 선택 열림", actual: results.joined(separator: ", "), failures: failures)
    }
}
}
