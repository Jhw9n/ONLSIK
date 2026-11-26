import Foundation
import SwiftData
import Testing
@testable import ONEULSIK

/// 검색 개선 기록(#51). 화면 경로(MealEntryViewModel: submit → 질문 선택)를 가짜 분석기로 돌려 a~e가 각각 남는지,
/// 기록이 식사 저장에 영향을 주지 않는지 본다. 기록은 테스트마다 임시 파일에 남긴다.
@MainActor
@Suite("검색 개선 기록", .serialized)
struct SearchImprovementLogTests {
    /// 정해 둔 분석 결과를 돌려주는 분석기. 질문 선택은 그 선택지의 항목으로 바로 기록한다(기본 resolve).
    private final class ScriptedAnalyzer: MealEntryAnalyzing {
        let result: () throws -> MealEntryAnalysis
        init(_ result: @escaping () throws -> MealEntryAnalysis) { self.result = result }
        func analyze(_ text: String) async throws -> MealEntryAnalysis { try result() }
    }

    private static func temporaryLog() -> SearchImprovementLog {
        SearchImprovementLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("search-log-\(UUID().uuidString).json"))
    }

    private static func food(_ id: String, _ name: String, kcalPer100: Double = 100) -> FoodCatalogItem {
        FoodCatalogItem(id: id, name: name, servingUnit: "인분", servingGrams: 100,
                        nutrition: NutritionValues(calories: kcalPer100, carbohydrateGrams: 10, proteinGrams: 5, fatGrams: 3))
    }

    private static func item(_ food: FoodCatalogItem, basis: MealNutritionBasis = .database) -> MealEntryItem {
        MealEntryItem(food: food, servingCount: 1, nutritionBasis: basis)
    }

    private static func choice(_ id: String, _ title: String, _ food: FoodCatalogItem, input: String, estimate: Bool = false) -> MealEntryChoice {
        let foodInput = MealFoodInput(name: input, sourceText: input, quantity: 1, unit: "인분", brand: "")
        var choice = MealEntryChoice(id: id, title: title, items: [item(food)],
                                     selection: MealFoodSelection(input: foodInput, food: food))
        if estimate { choice.estimateInput = foodInput }
        return choice
    }

    private func run(_ text: String, analyzer: ScriptedAnalyzer, log: SearchImprovementLog,
                     select index: Int? = nil) async throws -> MealEntryViewModel {
        let model = MealEntryViewModel(mealType: .lunch, analyzer: analyzer, analysisTimeout: .seconds(30), searchLog: log)
        model.updateText(text)
        model.submit()
        try await wait { if case .analyzing = model.phase { return false } else { return true } }
        if let index, case .question(let question) = model.phase {
            model.select(question.choices[index])
            try await wait { if case .analyzing = model.phase { return false } else { return true } }
        }
        return model
    }

    private func wait(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        try await Task.sleep(for: .milliseconds(50))
        while !condition(), clock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
    }

    private func waitForEntries(_ log: SearchImprovementLog, count: Int) async throws {
        let clock = ContinuousClock()
        // 전체 테스트를 병렬로 돌리면 화면 분석 작업이 늦게 끝날 수 있어 넉넉히 기다린다.
        let deadline = clock.now + .seconds(15)
        while log.entries().count < count, clock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
    }

    private func check(_ id: String, _ input: String, _ entries: [SearchImprovementEntry],
                       reasons: [SearchImprovementEntry.Reason], action: SearchImprovementEntry.Action) {
        var failures: [Failure] = []
        if entries.count != 1 { failures.append(Failure(type: .error, message: "기록 \(entries.count)건(기대 1건)")) }
        if let entry = entries.first {
            if Set(entry.reasons) != Set(reasons) {
                failures.append(Failure(type: .error, message: "경우 \(entry.reasons.map(\.rawValue)) (기대 \(reasons.map(\.rawValue)))"))
            }
            if entry.action != action { failures.append(Failure(type: .error, message: "행동 \(entry.action.rawValue) (기대 \(action.rawValue))")) }
            if entry.inputText.isEmpty || entry.foodName.isEmpty { failures.append(Failure(type: .error, message: "입력 문장·음식 이름 없음")) }
        }
        report(suite: "검색 개선 기록", id: id, input: input,
               expected: "경우 \(reasons.map(\.rawValue).joined(separator: ",")), 행동 \(action.rawValue)",
               actual: entries.first?.summary ?? "기록 없음", failures: failures)
    }

    @Test("a 영양정보를 찾지 못함")
    func notFound() async throws {
        let log = Self.temporaryLog()
        _ = try await run("알수없는음식", analyzer: ScriptedAnalyzer { throw MealEntryError.foodNotFound("알수없는음식") }, log: log)
        check("SL01", "알수없는음식(영양정보 없음 오류)", log.entries(), reasons: [.notFound], action: .failed)
        log.clear()
    }

    @Test("b 비슷한 음식 질문 → 수락, d 거절")
    func similarQuestion() async throws {
        let suggested = Self.food("D405-297470000-0001", "선지해장국 내장")
        let question = MealEntryQuestion(title: "비슷한 음식 기준으로 기록할까요?", explanation: "",
                                         choices: [Self.choice("first", "선지해장국 내장", suggested, input: "선지해장국"),
                                                   Self.choice("none", "목록에 없어요", Self.food("estimate", "선지해장국"), input: "선지해장국", estimate: true)])
        let accepted = Self.temporaryLog()
        _ = try await run("선지해장국", analyzer: ScriptedAnalyzer { .question(question) }, log: accepted, select: 0)
        check("SL02", "비슷한 음식 질문에서 첫 제안 선택", accepted.entries(), reasons: [.similarQuestion], action: .accepted)
        accepted.clear()
        let rejected = Self.temporaryLog()
        _ = try await run("선지해장국", analyzer: ScriptedAnalyzer { .question(question) }, log: rejected, select: 1)
        check("SL03", "비슷한 음식 질문에서 ‘목록에 없어요’ 선택", rejected.entries(), reasons: [.similarQuestion, .userChangedChoice], action: .rejected)
        rejected.clear()
    }

    @Test("c 이름 다름(질문 없이 기록)")
    func nameMismatch() async throws {
        let log = Self.temporaryLog()
        // 음식 DB의 '해장국 선지'(D105)를 입력 이름 '선지해장국'으로 기록한 경우(앱이 남기는 저장 출처 형식 그대로)
        var food = Self.food("D105-256230000-0001", "선지해장국", kcalPer100: 29)
        food.source = "식품의약품안전처 · 해장국 선지 영양값 기준"
        let item = Self.item(food)
        _ = try await run("선지해장국", analyzer: ScriptedAnalyzer { .ready([item]) }, log: log)
        try await waitForEntries(log, count: 1)
        check("SL04", "선지해장국 → DB 해장국 선지(질문 없이 기록)", log.entries(), reasons: [.nameMismatch], action: .automatic)
        log.clear()
    }

    @Test("d 다른 항목 직접 고름")
    func otherItem() async throws {
        let question = MealEntryQuestion(title: "어떤 제품을 드셨나요?", explanation: "",
                                         choices: [Self.choice("one", "첫 제품", Self.food("p1", "첫 제품"), input: "제품"),
                                                   Self.choice("two", "둘째 제품", Self.food("p2", "둘째 제품"), input: "제품")])
        let log = Self.temporaryLog()
        _ = try await run("제품", analyzer: ScriptedAnalyzer { .question(question) }, log: log, select: 1)
        check("SL05", "제품 질문에서 둘째 항목 선택", log.entries(), reasons: [.userChangedChoice], action: .otherItem)
        log.clear()
    }

    @Test("e 열량 확인 문구, 기록이 식사 저장에 영향 없음")
    func calorieCheckAndSaving() async throws {
        let food = Self.food("big", "큰 음식", kcalPer100: 1200)
        let question = MealEntryQuestion(title: "열량이 높게 계산됐어요", explanation: "",
                                         choices: [Self.choice("keep", "맞아요, 그대로 기록", food, input: "큰 음식")])
        let log = Self.temporaryLog()
        let model = try await run("큰 음식", analyzer: ScriptedAnalyzer { .question(question) }, log: log, select: 0)
        check("SL06", "열량 확인 질문에서 그대로 기록", log.entries(), reasons: [.calorieCheck], action: .accepted)

        // 같은 결과를 기록 있음·없음(지운 뒤)으로 저장해 저장된 식사가 같은지 본다.
        let container = try ModelContainer(for: UserProfile.self, MealRecord.self, WeightRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = MealRecordStore(modelContext: container.mainContext)
        let savedWithLog = model.save(store: store, userID: 1, date: .now)
        let withLog = try container.mainContext.fetch(FetchDescriptor<MealRecord>()).map { "\($0.foodName) \($0.calories)" }
        log.clear()
        let second = try await run("큰 음식", analyzer: ScriptedAnalyzer { .question(question) }, log: log, select: 0)
        log.clear()
        let otherContainer = try ModelContainer(for: UserProfile.self, MealRecord.self, WeightRecord.self,
                                                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let savedAfterClear = second.save(store: MealRecordStore(modelContext: otherContainer.mainContext), userID: 1, date: .now)
        let afterClear = try otherContainer.mainContext.fetch(FetchDescriptor<MealRecord>()).map { "\($0.foodName) \($0.calories)" }
        var failures: [Failure] = []
        if !savedWithLog || !savedAfterClear { failures.append(Failure(type: .error, message: "저장 실패(기록 있음 \(savedWithLog), 지운 뒤 \(savedAfterClear))")) }
        if withLog != afterClear || withLog.isEmpty { failures.append(Failure(type: .error, message: "저장된 식사 다름: \(withLog) / \(afterClear)")) }
        if !log.entries().isEmpty { failures.append(Failure(type: .error, message: "지운 뒤에도 기록 \(log.entries().count)건")) }
        report(suite: "검색 개선 기록", id: "SL07", input: "같은 입력을 기록 있음·지운 뒤로 저장",
               expected: "둘 다 저장되고 저장된 식사가 같음, 기록 지우기는 식사 기록과 따로",
               actual: "기록 있음 \(withLog), 지운 뒤 \(afterClear)", failures: failures)
    }
}
