import Foundation
@testable import ONEULSIK

/// LLM 대신 케이스에 적힌 응답을 돌려주는 해석기.
/// - foods: llm.food 한 개를 돌려준다(분량은 앱이 원문에서 다시 파싱한다).
/// - portion: llm.portion이 없으면 "모름"(portionUnknown)으로 답한다. unit 생략 시 DB 항목 단위를 쓴다.
/// - assess: llm.pick과 이름이 맞는 후보, 없으면 첫 후보를 고른다.
/// - estimateNutrition: llm.estimate가 있을 때만 추정값을 돌려준다.
/// - searchTerms: llm.searchTerms(실기기 모델 검색어 재현, 없으면 빈 목록). foods: llm.foods가 있으면 원문에 든 이름만.
/// - fail: llm.fail에 적은 단계를 실패시킨다(#41). foods·assess·estimate는 generationFailed, portion은 portionUnknown,
///   searchTerms는 빈 목록(실제 해석기가 그 단계 실패를 바꾸는 방식 그대로, #41 2차 A).
/// - rawFoods: llm.rawFoods가 있으면 원문과 상관없이 그대로(#41, 원문에 없는 이름을 섞어 돌려주는 모델 재현).
/// 실제 해석기(AppleMealFoodInterpreter)와 같은 조건으로 nil·예외를 낸다(#41 2차 A, Docs/FoodResolution.md 비교표):
/// - searchTerms: 실패해도 예외 없이 빈 목록(실제는 모델 오류를 삼킨다). 빈 검색어·60자 초과는 뺀다.
/// - portion: 어떤 실패든 portionUnknown(실제는 생성 오류도 분량 모름으로 바꾼다). 분량 검사(isPlausible)를 통과한 값만 돌려준다.
/// - estimateNutrition: g·mL 입력은 단위가 다르면 portionUnknown, 1을 돌려준다. 그 밖의 단위는 실제처럼 분량 추정을 거치는데,
///   llm.estimate.amount를 그 분량 추정의 답으로 본다. 분량 검사를 못 넘거나 portion 단계 실패면 기준량 100과 portionEstimated false.
@MainActor
final class FakeMealFoodInterpreter: MealFoodInterpreting {
    private let script: MealCase.LLM?
    private(set) var calls: [String] = []

    init(script: MealCase.LLM?) {
        self.script = script
    }

    private func failIfScripted(_ stage: String) throws {
        if script?.fail?.contains(stage) == true { throw MealEntryError.generationFailed }
    }

    func foods(in text: String) async throws -> [MealFoodInput] {
        calls.append("foods")
        try failIfScripted("foods")
        if let foods = script?.rawFoods {
            return foods.map { MealFoodInput(name: $0, sourceText: text, quantity: 1, unit: "인분", brand: "") }
        }
        if let foods = script?.foods {
            let compact = FoodReferenceCatalog.normalized(text)
            return foods.filter { compact.contains(FoodReferenceCatalog.normalized($0)) }
                .map { MealFoodInput(name: $0, sourceText: text, quantity: 1, unit: "인분", brand: "") }
        }
        guard let food = script?.food else { return [] }
        return [MealFoodInput(name: food, sourceText: text, quantity: 1, unit: "인분", brand: script?.brand ?? "")]
    }

    func portion(for input: MealFoodInput, food: FoodCatalogItem) async throws -> MealPortionEstimate {
        calls.append("portion")
        guard script?.fail?.contains("portion") != true, let portion = script?.portion else { throw MealEntryError.portionUnknown(input.name) }
        let estimate = MealPortionEstimate(amountPerUnit: portion.amount, amountUnit: portion.unit ?? food.amountUnit)
        guard estimate.isPlausible(for: input.unit, foodName: input.name) else { throw MealEntryError.portionUnknown(input.name) }
        return estimate
    }

    func assess(_ input: MealFoodInput, candidates: [FoodCatalogItem]) async throws -> MealFoodAssessment {
        calls.append("assess")
        try failIfScripted("assess")
        guard !candidates.isEmpty else { return MealFoodAssessment(candidateIndex: 0, clarification: .none) }
        if let pick = script?.pick {
            let index = candidates.firstIndex { $0.name.contains(pick) }.map { $0 + 1 } ?? 0
            return MealFoodAssessment(candidateIndex: index, clarification: .none)
        }
        return MealFoodAssessment(candidateIndex: 1, clarification: .none)
    }

    func searchTerms(for input: MealFoodInput) async throws -> [String] {
        calls.append("searchTerms")
        guard script?.fail?.contains("searchTerms") != true else { return [] }
        return (script?.searchTerms ?? []).filter { !$0.isEmpty && $0.count <= 60 }
    }

    func estimateNutrition(for input: MealFoodInput) async throws -> MealNutritionEstimate? {
        calls.append("estimate")
        try failIfScripted("estimate")
        guard let estimate = script?.estimate, !estimate.referenceFood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var amount = estimate.amount
        var portionEstimated = true
        if input.unit == "g" || input.unit == "mL" {
            guard input.unit == estimate.amountUnit else { throw MealEntryError.portionUnknown(input.name) }
            amount = 1
        } else {
            calls.append("portion")
            let portion = MealPortionEstimate(amountPerUnit: estimate.amount, amountUnit: estimate.amountUnit)
            if script?.fail?.contains("portion") == true || !portion.isPlausible(for: input.unit, foodName: input.name) {
                amount = 100
                portionEstimated = false
            }
        }
        return MealNutritionEstimate(
            referenceFood: estimate.referenceFood,
            amountPerUnit: amount,
            amountUnit: estimate.amountUnit,
            nutritionPer100: NutritionValues(calories: estimate.calories, carbohydrateGrams: estimate.carbohydrate,
                                             proteinGrams: estimate.protein, fatGrams: estimate.fat),
            ingredients: estimate.ingredients,
            portionEstimated: portionEstimated
        )
    }
}
