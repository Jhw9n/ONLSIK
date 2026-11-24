import Foundation
import Testing
@testable import ONEULSIK

/// 식약처 음식 DB 1인분 중량 점검(L04, #43). 실패 없이 보고서에 숫자와 목록만 남긴다.
/// - 표(DishServings.json)의 일반 음식 중 대표 분량표(FoodPortion)나 참고표(FoodReferences estimatedPortions) 값이 이미 있어
///   그 값이 먼저 쓰이는 음식에서, 두 값이 20% 넘게 다른 목록(고치지 않고 보고만 한다)
/// - 1인분 상한(MealPortionEstimate.isPlausible, 인분)을 넘어 앱이 쓰지 않는 값의 수
@MainActor
@Suite("음식 DB 1인분 중량")
struct DishServingTests {
    @Test("대표 분량표·참고표와 비교")
    func compareWithRepresentativePortions() async throws {
        let catalog = FoodCatalogService()
        var overlaps: [String] = []
        var different: [String] = []
        var implausible: [String] = []
        var usable = 0
        var missing = 0
        for id in DishServing.foodIDs {
            guard let food = try await catalog.food(id: id), let serving = DishServing.serving(for: food) else {
                missing += 1
                continue
            }
            let table = FoodPortion.representative(for: food, allowsVolumeAsWeight: true)
            let reference = FoodReferenceCatalog.entries.lazy.compactMap { entry in
                entry.estimatedAmount(for: "인분", food: food).map { (entry.name, $0) }
            }.first
            let existing: (String, Double)? = table.map { ("대표 분량표 1\($0.unit)", $0.grams) }
                ?? reference.map { ("참고표 \($0.0) 1인분", $0.1) }
            if let (label, amount) = existing {
                overlaps.append(food.id)
                let ratio = serving.amount / amount
                if abs(ratio - 1) > 0.2 {
                    different.append("\(food.name)(\(food.id)) \(label) \(amount.formatted())\(food.amountUnit) / 음식 DB \(serving.amount.formatted())\(serving.unit)")
                }
            } else if MealPortionEstimate(amountPerUnit: serving.amount, amountUnit: serving.unit).isPlausible(for: "인분", foodName: food.name) {
                usable += 1
            } else {
                implausible.append("\(food.name) \(serving.amount.formatted())\(serving.unit)")
            }
        }
        report(suite: "음식 DB 1인분 중량", id: "L04", input: "DishServings.json \(DishServing.foodIDs.count)개",
               expected: "보고만 함(실패 없음)",
               actual: "새로 쓰는 값 \(usable)개, 기존 표 값이 먼저인 음식 \(overlaps.count)개(20% 넘게 다름 \(different.count)개), 1인분 상한으로 안 쓰는 값 \(implausible.count)개, DB에 없음 \(missing)개",
               failures: [],
               details: ["20% 넘게 다름: " + different.joined(separator: "; "),
                         "1인분 상한으로 안 쓰는 값(앞 30개): " + implausible.prefix(30).joined(separator: "; ")])
    }
}
