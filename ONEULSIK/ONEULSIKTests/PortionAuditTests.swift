import Foundation
import Testing
@testable import ONEULSIK

/// 대표 분량표 음식 전체 점검(L03, #29). Docs/FoodResolution.md의 규칙대로 기록되는지 원인별로 센다.
/// 입력은 대표 분량표(FoodPortion)의 같은 음식 표기 묶음마다 사용자가 입력할 이름 하나(L01과 같은 방식)이고,
/// 수량 없이 AI 식사 입력 흐름(가짜 해석기, 질문은 첫 선택지)으로 끝까지 진행한다.
/// 지금 위반 목록은 기준선(PortionAuditBaseline.json)에 있고, 기준선에 없는 새 위반이나 해결돼 기준선에서 지울 항목이
/// 생기면 실패한다. 기준선 다시 만들기: TEST_RUNNER_ONEULSIK_AUDIT_BASELINE_OUT=<경로>로 이 테스트를 돌려 나온 파일로 바꾼다.
@MainActor
@Suite("대표 분량 음식 점검")
struct PortionAuditTests {
    enum Cause: String, CaseIterable, Codable {
        case nameMismatch = "이름 불일치"      // (a) 자료집 지정 자료가 있는데 다른 자료로 기록됨
        case noMatchingFood = "맞는 자료 없음"  // (b) 대표 분량 출처가 자료집인데 지정 자료가 없음
        case milliliterOnly = "mL만"          // (c) 기록 자료가 mL이고 국물·면 규칙도 적용되지 않음
        case portionUnlinked = "대표 분량 미연결" // (d) L01과 같은 기준
        case other = "기타"                   // (e) 기록할 자료를 정하지 못함 등
    }

    struct Violation: Codable, Hashable {
        let name: String
        let cause: Cause
        let detail: String
    }

    struct Baseline: Codable {
        var _readme: [String]
        var violations: [Violation]
    }

    struct Observation {
        let name: String
        let food: FoodCatalogItem?      // 최종(또는 질문에서 멈춘) DB 자료
        let item: MealEntryItem?
        let stage: String
        let expected: [String]
        let isGuideSource: Bool
        let stopped: String
        var linked: Bool { item.map(PortionLinkTests.isLinked) ?? false }
    }

    /// 대표 분량 출처 URL에서 자료집 쪽 번호를 읽는다(FoodPortion.guideSource 형식).
    static func guidePage(of source: String) -> Int? {
        guard source.contains("/upload/mkisna/2013.pdf#page="),
              let page = source.split(separator: "=").last.flatMap({ Int($0) }) else { return nil }
        return page
    }

    /// 대표 분량표에서 그 이름이 걸리는 행의 출처. 같은 이름의 g 기준 일반 음식을 만들어 표를 찾는다(앱 코드와 같은 조회).
    static func portionSource(for name: String) -> String? {
        let probe = FoodCatalogItem(id: "audit", name: name, servingUnit: "g", servingGrams: 100,
                                    nutrition: NutritionValues(calories: 100, carbohydrateGrams: 0, proteinGrams: 0, fatGrams: 0),
                                    category: "음식")
        return FoodPortion.representative(for: probe)?.source
    }

    struct GuideFile: Decodable {
        struct Entry: Decodable { let foodID: String; let guidePage: Int }
        let entries: [Entry]
    }

    static func guideEntries() -> [GuideFile.Entry] {
        guard let url = Bundle.main.url(forResource: "GuideRepresentatives", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(GuideFile.self, from: data) else { return [] }
        return file.entries
    }

    static func loadBaseline() -> Baseline? {
        guard let url = Bundle(for: AuditBundleToken.self).url(forResource: "PortionAuditBaseline", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Baseline.self, from: data)
    }

    /// 영양값 자료가 Docs/FoodResolution.md 2절의 어느 단계에서 정해졌는지 밖에서 본 추정.
    static func stage(name: String, food: FoodCatalogItem, item: MealEntryItem?, guideIDs: Set<String>) async -> String {
        let reference = FoodReferenceCatalog.entry(for: name)
        if reference?.referenceID == food.id { return "참고표 지정" }
        if guideIDs.contains(food.id) { return "자료집 지정" }
        if item?.volumeNote != nil { return "국물·면 mL(1mL=1g)" }
        if food.amountUnit == "g" {
            if let id = reference?.referenceID, let referenced = try? await FoodCatalogService().food(id: id),
               referenced.amountUnit == "mL" { return "같은 요리 g 항목(참고표 mL)" }
            let keys = Set(FoodPortion.sameDishNames(food.name).map(FoodReferenceCatalog.normalized))
            let results = (try? await FoodCatalogService().search(query: name)) ?? []
            if results.contains(where: { $0.amountUnit == "mL" && $0.brand.isEmpty && $0.category != "가공식품"
                && FoodReferenceCatalog.normalized($0.name) == FoodReferenceCatalog.normalized(name)
                && FoodPortion.sameDishNames($0.name).contains { keys.contains(FoodReferenceCatalog.normalized($0)) } }) {
                return "같은 요리 g 항목"
            }
        }
        return "기본 순서(priority·기준일·식품코드)"
    }

    static func observe(_ name: String, guide: [GuideFile.Entry]) async -> Observation {
        let source = portionSource(for: name)
        let page = source.flatMap(guidePage)
        let expected = page.map { page in guide.filter { $0.guidePage == page }.map(\.foodID) } ?? []
        let script = MealCase.LLM(food: name, brand: nil, portion: nil, pick: nil, estimate: nil)
        let service = AIMealEntryService(interpreter: FakeMealFoodInterpreter(script: script), catalog: FoodCatalogService())
        var food: FoodCatalogItem?
        var item: MealEntryItem?
        var stopped = ""
        do {
            var analysis = try await service.analyze(name)
            loop: for _ in 0..<4 {
                switch analysis {
                case .ready(let items):
                    item = items.first
                    if let id = items.first?.food.id { food = try? await FoodCatalogService().food(id: id) }
                    break loop
                case .question(let question):
                    if let selected = question.choices.first?.selection?.food ?? question.clarification?.selection?.food {
                        food = try? await FoodCatalogService().food(id: selected.id) ?? selected
                    }
                    guard !question.title.contains("얼마나"), let first = question.choices.first else {
                        stopped = question.title
                        break loop
                    }
                    analysis = try await service.resolve(first)
                }
            }
        } catch {
            stopped = error.localizedDescription
        }
        let guideIDs = Set(guide.map(\.foodID))
        let stage = food == nil ? "-" : await stage(name: name, food: food!, item: item, guideIDs: guideIDs)
        return Observation(name: name, food: food, item: item, stage: stage, expected: expected,
                           isGuideSource: page != nil, stopped: stopped)
    }

    static func violations(of observation: Observation) -> [Violation] {
        let food = observation.food
        let recorded = food.map { "\($0.id) \($0.name)[\($0.amountUnit)]" } ?? "자료 없음"
        var result: [Violation] = []
        func add(_ cause: Cause, _ detail: String) { result.append(Violation(name: observation.name, cause: cause, detail: detail)) }
        if !observation.expected.isEmpty, !observation.expected.contains(food?.id ?? "") {
            add(.nameMismatch, "\(recorded) ≠ 지정 \(observation.expected.joined(separator: ","))")
        }
        if observation.isGuideSource, observation.expected.isEmpty {
            add(.noMatchingFood, "자료집 출처, 지정 자료 없음 → \(recorded)")
        }
        if let food, food.amountUnit == "mL", observation.item?.volumeNote == nil {
            add(.milliliterOnly, recorded)
        }
        if !observation.linked {
            add(.portionUnlinked, observation.stopped.isEmpty ? recorded : "\(recorded) → \(observation.stopped)")
        }
        if food == nil {
            add(.other, observation.stopped.isEmpty ? "기록할 자료 없음" : observation.stopped)
        }
        return result
    }

    @Test("대표 분량표 음식 전체")
    func audit() async {
        let guide = Self.guideEntries()
        let names = FoodPortion.tableNames.flatMap(PortionLinkTests.dishGroups).map { names in
            names.first { $0.allSatisfy { $0.isLetter } } ?? names[0]
        }
        var observations: [Observation] = []
        for name in names { observations.append(await Self.observe(name, guide: guide)) }
        let current = observations.flatMap(Self.violations)

        if let path = ProcessInfo.processInfo.environment["ONEULSIK_AUDIT_BASELINE_OUT"], !path.isEmpty {
            let baseline = Baseline(_readme: [
                "대표 분량 음식 점검(L03, PortionAuditTests) 기준선. 지금 알려진 위반 목록이다(테스트 데이터).",
                "새 위반(이 목록에 없는 이름·원인)이 생기거나 목록의 항목이 해결되면 L03이 실패한다. 해결된 항목은 이 파일에서 지운다.",
                "다시 만들기: TEST_RUNNER_ONEULSIK_AUDIT_BASELINE_OUT=<경로>로 PortionAuditTests를 돌린 결과로 바꾼다. 비교는 이름과 원인만 보고 detail은 참고용이다.",
            ], violations: current)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(baseline) { try? data.write(to: URL(fileURLWithPath: path)) }
        }

        let baseline = Self.loadBaseline()
        let key = { (violation: Violation) in "\(violation.name)\t\(violation.cause.rawValue)" }
        let known = Set((baseline?.violations ?? []).map(key))
        let found = Set(current.map(key))
        var failures: [Failure] = []
        if baseline == nil { failures.append(Failure(type: .audit, message: "기준선 파일(PortionAuditBaseline.json)을 읽지 못함")) }
        failures += current.filter { !known.contains(key($0)) }
            .map { Failure(type: .audit, message: "새 위반: \($0.name) [\($0.cause.rawValue)] \($0.detail)") }
        failures += (baseline?.violations ?? []).filter { !found.contains(key($0)) }
            .map { Failure(type: .audit, message: "기준선에서 지울 항목(해결됨): \($0.name) [\($0.cause.rawValue)]") }

        let violating = Set(current.map(\.name)).count
        let counts = Cause.allCases.map { cause in "\(cause.rawValue) \(current.filter { $0.cause == cause }.count)" }
        var details = ["입력 \(names.count)개, 위반 있는 입력 \(violating)개, 위반 \(current.count)건(\(counts.joined(separator: ", ")))"]
        for cause in Cause.allCases {
            let items = current.filter { $0.cause == cause }
            details.append("원인 \(cause.rawValue) \(items.count)건: " + items.map { "\($0.name) — \($0.detail)" }.joined(separator: "; "))
        }
        for observation in observations {
            let food = observation.food.map { "\($0.id) \($0.name)[\($0.amountUnit)]" } ?? "자료 없음"
            details.append("입력 \(observation.name): \(food), 대표 분량 \(observation.linked ? "붙음" : "안 붙음"), 영양값 단계 \(observation.stage)"
                + (observation.expected.isEmpty ? "" : ", 지정 \(observation.expected.joined(separator: ","))"))
        }
        report(suite: "대표 분량 연결", id: "L03",
               input: "FoodPortion 대표 분량표 음식 전체(L01과 같은 묶음 방식, 수량 없이 입력)",
               expected: "기준선(PortionAuditBaseline.json)과 같은 위반 목록",
               actual: "입력 \(names.count)개, 위반 \(current.count)건(\(counts.joined(separator: ", "))), 기준선 \(known.count)건",
               failures: failures, details: details)
    }
}

private final class AuditBundleToken {}
