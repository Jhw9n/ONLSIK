import Foundation
import Testing
@testable import ONEULSIK

/// "이렇게 기록할까요?" 화면의 음식별 열량과 하단 합계가 서로 맞는지 검사한다.
@MainActor
@Suite("열량 합계")
struct MealEntryTotalsTests {
    private struct NoAnalyzer: MealEntryAnalyzing {
        func analyze(_ text: String) async throws -> MealEntryAnalysis { throw MealEntryError.invalidResult }
    }

    private static func item(_ name: String, unit: String, grams: Double, caloriesPer100: Double, count: Double = 1) -> MealEntryItem {
        MealEntryItem(
            food: FoodCatalogItem(id: "totals-\(name)", name: name, servingUnit: unit, servingGrams: grams,
                                  nutrition: NutritionValues(calories: caloriesPer100 * grams / 100, carbohydrateGrams: 10,
                                                             proteinGrams: 5, fatGrams: 3)),
            servingCount: count)
    }

    private static func model(_ items: [MealEntryItem]) -> MealEntryViewModel {
        let model = MealEntryViewModel(mealType: .lunch, analyzer: NoAnalyzer())
        model.configurePreview(text: "합계 검사", phase: .ready, recentMeals: [], items: items)
        return model
    }

    /// 화면 합계 = 카드 숫자의 합, 실제 합과의 차이는 반올림 오차(음식 수 × 0.5kcal) 이내
    private static func check(_ model: MealEntryViewModel, label: String) -> [Failure] {
        var failures: [Failure] = []
        let shownSum = model.items.reduce(0) { $0 + $1.displayedCalories }
        if model.displayedTotalCalories != shownSum {
            failures.append(Failure(type: .totals, message: "\(label): 합계 \(model.displayedTotalCalories) ≠ 카드 합 \(shownSum)"))
        }
        let tolerance = Double(model.items.count) * 0.5
        if abs(Double(model.displayedTotalCalories) - model.totalCalories) > tolerance {
            failures.append(Failure(type: .totals,
                message: "\(label): 표시 합계 \(model.displayedTotalCalories)와 실제 \(model.totalCalories.short) 차이가 \(tolerance)kcal 초과"))
        }
        return failures
    }

    @Test("반올림이 겹치는 여러 음식")
    func roundingAcrossItems() {
        // 소수점 .4/.5/.6이 섞여 실제 합(1,214.9)을 반올림하면 카드 합과 1kcal 달라지는 조합
        let items = [
            Self.item("김밥", unit: "줄", grams: 200, caloriesPer100: 160.2),       // 320.4
            Self.item("라면", unit: "그릇", grams: 500, caloriesPer100: 100.08),    // 500.4
            Self.item("계란말이", unit: "접시", grams: 100, caloriesPer100: 150.5), // 150.5
            Self.item("콜라", unit: "컵", grams: 250, caloriesPer100: 97.44),       // 243.6
        ]
        let model = Self.model(items)
        let failures = Self.check(model, label: "초기")
        report(suite: "열량 합계", id: "K01", input: items.map(\.food.name).joined(separator: ", "),
               expected: "합계 = 음식별 표시 값의 합, 실제 합과 ±\(Double(items.count) * 0.5)kcal 이내",
               actual: "카드 \(model.items.map { String($0.displayedCalories) }.joined(separator: " + ")) = \(model.displayedTotalCalories), 실제 \(model.totalCalories.short)",
               failures: failures)
    }

    @Test("± 버튼으로 분량을 바꾼 뒤")
    func afterQuantityChange() {
        let items = [
            Self.item("삼겹살구이", unit: "인분", grams: 130, caloriesPer100: 467),
            Self.item("쌀밥", unit: "공기", grams: 210, caloriesPer100: 143.33),
        ]
        let model = Self.model(items)
        var failures = Self.check(model, label: "초기")
        let before = model.items.map(\.displayedCalories)
        var steps: [String] = []
        for (index, delta) in [(0, 0.5), (1, -0.5), (0, 0.5)] {
            let current = model.items[index]
            model.setQuantity(current.quantity + delta * current.quantityStep / 0.5, for: current.id)
            steps.append("\(current.food.name) \(delta > 0 ? "+" : "−")")
            failures += Self.check(model, label: steps.joined(separator: ", "))
        }
        let after = model.items.map(\.displayedCalories)
        if after == before {
            failures.append(Failure(type: .totals, message: "분량을 바꿨는데 음식별 열량이 바뀌지 않음"))
        }
        // 1인분 → 2인분이면 열량도 두 배(반올림 오차 이내)
        let expectedPork = Int((467 * 1.3 * 2).rounded())
        if abs(model.items[0].displayedCalories - expectedPork) > 1 {
            failures.append(Failure(type: .totals, message: "삼겹살구이 2인분 \(model.items[0].displayedCalories)kcal (기대 약 \(expectedPork))"))
        }
        report(suite: "열량 합계", id: "K02", input: steps.joined(separator: " → "),
               expected: "분량 변경마다 음식별 열량 갱신, 합계 = 카드 합",
               actual: "전 \(before) → 후 \(after), 합계 \(model.displayedTotalCalories)", failures: failures)
    }
}

/// 최근 먹은 식사 제목(RecentMealEntry.title, #47). 음식 사이는 ", "로 잇는다.
/// 이전에는 " · "로 이어, 업체명이 붙은 기록 이름("고추참치 · 신진물산(주)")과 섞여 음식이 세 개처럼 보였다.
@MainActor
@Suite("최근 식사 제목")
struct RecentMealTitleTests {
    @Test("음식 두 개 기록의 제목")
    func twoFoods() {
        func item(_ name: String) -> MealEntryItem {
            MealEntryItem(food: FoodCatalogItem(id: "test-\(name)", name: name, servingUnit: "인분", servingGrams: 100,
                                                nutrition: NutritionValues(calories: 100, carbohydrateGrams: 0, proteinGrams: 0, fatGrams: 0)),
                          servingCount: 1)
        }
        let title = RecentMealEntry(items: [item("고추참치"), item("쌀밥")]).title
        let failures = title == "고추참치, 쌀밥" ? [] : [Failure(type: .displayText, message: "제목 ‘\(title)’ (기대 ‘고추참치, 쌀밥’)")]
        report(suite: "최근 식사 제목", id: "R02", input: "고추참치 + 쌀밥", expected: "고추참치, 쌀밥", actual: title, failures: failures)
    }
}
