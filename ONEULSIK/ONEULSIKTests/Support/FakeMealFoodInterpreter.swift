import Foundation
@testable import ONEULSIK

/// LLM 대신 케이스에 적힌 응답을 돌려주는 해석기.
/// - foods: llm.food 한 개를 돌려준다(분량은 앱이 원문에서 다시 파싱한다).
/// - portion: llm.portion이 없으면 "모름"(portionUnknown)으로 답한다. unit 생략 시 DB 항목 단위를 쓴다.
/// - assess: llm.pick과 이름이 맞는 후보, 없으면 첫 후보를 고른다.
/// - estimateNutrition: llm.estimate가 있을 때만 추정값을 돌려준다.
@MainActor
final class FakeMealFoodInterpreter: MealFoodInterpreting {
    private let script: MealCase.LLM?
    private(set) var calls: [String] = []

    init(script: MealCase.LLM?) {
        self.script = script
    }

    func foods(in text: String) async throws -> [MealFoodInput] {
        calls.append("foods")
        guard let food = script?.food else { return [] }
        return [MealFoodInput(name: food, sourceText: text, quantity: 1, unit: "인분", brand: script?.brand ?? "")]
    }

    func portion(for input: MealFoodInput, food: FoodCatalogItem) async throws -> MealPortionEstimate {
        calls.append("portion")
        guard let portion = script?.portion else { throw MealEntryError.portionUnknown(input.name) }
        return MealPortionEstimate(amountPerUnit: portion.amount, amountUnit: portion.unit ?? food.amountUnit)
    }

    func assess(_ input: MealFoodInput, candidates: [FoodCatalogItem]) async throws -> MealFoodAssessment {
        calls.append("assess")
        guard !candidates.isEmpty else { return MealFoodAssessment(candidateIndex: 0, clarification: .none) }
        if let pick = script?.pick {
            let index = candidates.firstIndex { $0.name.contains(pick) }.map { $0 + 1 } ?? 0
            return MealFoodAssessment(candidateIndex: index, clarification: .none)
        }
        return MealFoodAssessment(candidateIndex: 1, clarification: .none)
    }

    func estimateNutrition(for input: MealFoodInput) async throws -> MealNutritionEstimate? {
        calls.append("estimate")
        guard let estimate = script?.estimate else { return nil }
        return MealNutritionEstimate(
            referenceFood: estimate.referenceFood,
            amountPerUnit: estimate.amount,
            amountUnit: estimate.amountUnit,
            nutritionPer100: NutritionValues(calories: estimate.calories, carbohydrateGrams: estimate.carbohydrate,
                                             proteinGrams: estimate.protein, fatGrams: estimate.fat),
            ingredients: estimate.ingredients
        )
    }
}
