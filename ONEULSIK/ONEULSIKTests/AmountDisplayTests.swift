import Foundation
import Testing
@testable import ONEULSIK

/// 고체 음식의 mL 표시 숨김(2026-11-25 사용자 결정, #43, MealAmountDisplay). 표시만 보고 저장 값은 보지 않는다.
/// 결과 카드(MealEntryItem.basisDescription·amountDescription)와 기록 목록(MealRecord.servingDescription, 기록은 MealRecordStore와 같은 방식으로 만든다).
/// - hidden: mL 숫자를 숨김(카드·기록 모두 mL 없음, 기록은 "4조각"처럼 수량·단위만)
/// - grams: 국물·면은 같은 숫자를 g으로
/// - milliliters: 음료·술 표·사용자가 적은 mL은 mL 그대로(분량 안내 문장 속 'mL' 글자는 보지 않고 숫자+mL만 본다)
/// - unchanged: g 자료라 규칙과 관계없음(g 그대로)
@MainActor
@Suite("분량 표시")
struct AmountDisplayTests {
    enum Expect: String { case hidden, grams, milliliters, unchanged }

    @Test("mL 자료 음식의 분량 표시", arguments: [
        ("W01", "피자 4조각", "피자", Expect.hidden),
        ("W02", "탕수육 절반", "탕수육", Expect.hidden),
        ("W03", "순두부찌개 절반", "순두부찌개", Expect.grams),
        ("W04", "육개장", "육개장", Expect.unchanged),
        ("W05", "아메리카노 한 잔", "아메리카노", Expect.unchanged),
        ("W06", "초코우유", "초코우유", Expect.milliliters),
        ("W07", "에너지드링크", "에너지드링크", Expect.milliliters),
        ("W08", "탕수육 300mL", "탕수육", Expect.milliliters),
    ])
    func display(_ id: String, _ input: String, _ food: String, _ expect: Expect) async throws {
        let script = MealCase.LLM(food: food, brand: nil, portion: .init(amount: 200, unit: nil), pick: nil, estimate: nil)
        let service = AIMealEntryService(interpreter: FakeMealFoodInterpreter(script: script), catalog: FoodCatalogService())
        var analysis = try await service.analyze(input)
        for _ in 0..<3 {
            guard case .question(let question) = analysis, let first = question.choices.first else { break }
            analysis = try await service.resolve(first)
        }
        var failures: [Failure] = []
        var actual = "기록 없음"
        if case .ready(let items) = analysis, let item = items.first {
            let record = MealRecord(kakaoUserID: 0, recordedAt: .now, foodID: item.food.id, foodName: item.food.recordedName,
                servingUnit: item.food.servingUnit, servingGrams: item.food.servingGrams, servingMilliliters: item.food.servingMilliliters,
                servingCount: item.count, calories: item.nutrition.calories, carbohydrateGrams: item.nutrition.carbohydrateGrams,
                proteinGrams: item.nutrition.proteinGrams, fatGrams: item.nutrition.fatGrams)
            record.portionBasisRawValue = item.portionBasis.rawValue
            let card = [item.amountDescription, item.basisDescription].compactMap { $0 }.joined(separator: " · ")
            let listed = record.servingDescription
            actual = "카드 ‘\(card) · \(item.displayedCalories)kcal’, 기록 목록 ‘\(listed)’, 자료 \(item.food.id)[\(item.food.amountUnit)]"
            let texts = [card, listed]
            let milliliterAmount = #"\d(?:[\d,.]*)mL"#
            let hasMilliliters = texts.contains { $0.range(of: milliliterAmount, options: .regularExpression) != nil }
            let gramAmount = #"\d(?:[\d,.]*)g"#
            switch expect {
            case .hidden:
                if item.food.amountUnit != "mL" { failures.append(Failure(type: .unit, message: "mL 자료가 아님(\(item.food.amountUnit))")) }
                if hasMilliliters || texts.contains(where: { $0.range(of: gramAmount, options: .regularExpression) != nil }) {
                    failures.append(Failure(type: .displayText, message: "분량 숫자가 보임"))
                }
            case .grams:
                if hasMilliliters { failures.append(Failure(type: .displayText, message: "mL가 보임")) }
                if !texts.allSatisfy({ $0.range(of: gramAmount, options: .regularExpression) != nil }) {
                    failures.append(Failure(type: .displayText, message: "g 분량이 안 보임"))
                }
            case .milliliters:
                if item.food.amountUnit != "mL" { failures.append(Failure(type: .unit, message: "mL 자료가 아님(\(item.food.amountUnit))")) }
                if !texts.allSatisfy({ $0.range(of: milliliterAmount, options: .regularExpression) != nil }) { failures.append(Failure(type: .displayText, message: "mL가 안 보임")) }
            case .unchanged:
                if item.food.amountUnit != "g" { failures.append(Failure(type: .unit, message: "g 자료가 아님(\(item.food.amountUnit))")) }
                if item.amountDisplayStyle != .asIs || hasMilliliters {
                    failures.append(Failure(type: .displayText, message: "g 자료의 표시가 바뀜"))
                }
            }
        } else {
            failures.append(Failure(type: .error, message: "기록되지 않음"))
        }
        report(suite: "분량 표시", id: id, input: input, expected: expect.rawValue, actual: actual, failures: failures)
    }
}
