import Foundation
import Testing
@testable import ONEULSIK

/// 대표 분량 연결 점검. "DB에 항목이 있는가"(Scripts/validate_food_references.py)가 아니라
/// "앱이 실제로 고르는 항목에 대표 분량이 붙는가"를 본다.
/// 각 이름을 수량 없이 입력해 앱 흐름(검색 → 후보 선택 → 비슷한 음식 확인은 첫 선택지)을 그대로 돌리고,
/// 기록 카드까지 가면(대표 분량 또는 참고표 estimatedPortions로 1단위 가정) 연결된 것으로 본다.
/// 수량 질문으로 가면 연결되지 않은 항목이다.
@MainActor
@Suite("대표 분량 연결")
struct PortionLinkTests {
    struct Outcome {
        let linked: Bool
        let description: String
    }

    /// 수량 없이 입력해 1단위를 가정한 기록 중 근거 데이터(대표 분량·참고표·포장량)로 분량을 정한 것.
    /// 2026-11-24(#41 2차 B)부터 수량이 없으면 AI 분량 추정(aiEstimated)이나 영양 기준량(entered)으로도 묻지 않고 기록하고 같은 안내를
    /// 붙이므로, 안내만으로는 연결 여부를 알 수 없어 분량 근거도 본다.
    static func isLinked(_ item: MealEntryItem) -> Bool {
        item.quantityNote != nil && ![.aiEstimated, .entered].contains(item.portionBasis)
    }

    static func outcome(for name: String) async -> Outcome {
        let script = MealCase.LLM(food: name, brand: nil, portion: nil, pick: nil, estimate: nil)
        let service = AIMealEntryService(interpreter: FakeMealFoodInterpreter(script: script), catalog: FoodCatalogService())
        var selected = "-"
        func describe(_ food: FoodCatalogItem) async -> String {
            let database = try? await FoodCatalogService().food(id: food.id)
            return "\(database?.name ?? food.name)[\(database?.amountUnit ?? food.amountUnit)]"
        }
        do {
            var analysis = try await service.analyze(name)
            for _ in 0..<4 {
                switch analysis {
                case .ready(let items):
                    guard let item = items.first else { return Outcome(linked: false, description: "기록 없음") }
                    let amount = "\(item.count.short)\(item.food.servingUnit) \((item.food.baseAmount * item.count).short)\(item.food.amountUnit)"
                    return Outcome(linked: isLinked(item), description: "\(await describe(item.food)) \(amount)")
                case .question(let question):
                    if let food = question.choices.first?.selection?.food ?? question.clarification?.selection?.food {
                        selected = await describe(food)
                    }
                    guard !question.title.contains("얼마나"), let first = question.choices.first else {
                        return Outcome(linked: false, description: "\(selected) → \(question.title)")
                    }
                    analysis = try await service.resolve(first)
                }
            }
            return Outcome(linked: false, description: "\(selected) → 질문 반복")
        } catch {
            return Outcome(linked: false, description: "\(selected) → \(error.localizedDescription)")
        }
    }

    /// 한 행 안에서 같은 음식의 다른 표기끼리 묶는다(정규화 후 같음, 글자 순서만 다름, 한쪽이 다른 쪽을 포함).
    /// 대표 분량표는 분량이 같은 다른 음식을 한 행에 두기도 해서(예: 김치찌개·순두부찌개), 행 단위로 보면 하나만 연결돼도
    /// 나머지가 가려진다. 묶음마다 따로 검사한다.
    static func dishGroups(_ names: [String]) -> [[String]] {
        let keys = names.map { FoodPortion.lookupKey($0) }
        var parent = Array(names.indices)
        func root(_ index: Int) -> Int { parent[index] == index ? index : root(parent[index]) }
        for left in names.indices {
            for right in names.indices where left < right {
                let a = keys[left], b = keys[right]
                if a == b || a.sorted() == b.sorted() || a.contains(b) || b.contains(a) {
                    parent[root(right)] = root(left)
                }
            }
        }
        var groups: [Int: [String]] = [:]
        var order: [Int] = []
        for index in names.indices {
            let key = root(index)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(names[index])
        }
        return order.compactMap { groups[$0] }
    }

    private static func check(id: String, input: String, rows: [[String]], groupsDishes: Bool) async {
        var unlinked: [String] = []
        var linked = 0
        for names in groupsDishes ? rows.flatMap(dishGroups) : rows {
            // 사용자가 입력할 이름(기호 없는 첫 이름) 하나로 본다. 다른 표기가 연결돼도 이 이름이 안 붙으면 실패.
            let name = names.first { $0.allSatisfy { $0.isLetter } } ?? names[0]
            let outcome = await outcome(for: name)
            if outcome.linked { linked += 1 } else { unlinked.append("\(name): \(outcome.description)") }
        }
        report(suite: "대표 분량 연결", id: id, input: input,
               expected: "앱이 고른 항목에 대표 분량이 붙음(수량 없이 입력해 기록 카드까지)",
               actual: "음식 \(linked + unlinked.count)개 중 \(linked)개 연결, \(unlinked.count)개 안 붙음",
               failures: unlinked.map { Failure(type: .portionLink, message: $0) })
    }

    @Test("대표 분량표(FoodPortion)")
    func portionTable() async {
        await Self.check(id: "L01", input: "FoodPortion 대표 분량표(같은 음식의 표기 묶음마다 기호 없는 첫 이름으로 검사)", rows: FoodPortion.tableNames, groupsDishes: true)
    }

    @Test("참고표(FoodReferences.json)")
    func referenceTable() async {
        await Self.check(id: "L02", input: "FoodReferences.json 항목(항목의 대표 이름으로 검사)",
                         rows: FoodReferenceCatalog.entries.map(\.names), groupsDishes: false)
    }
}
