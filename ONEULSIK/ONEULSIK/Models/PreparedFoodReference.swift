import Foundation

nonisolated struct PreparedFoodReference: Sendable {
    let food: FoodCatalogItem
    let aliases: [String]

    static let entries: [PreparedFoodReference] = [
        PreparedFoodReference(
            food: FoodCatalogItem(
                id: "reference:egg-bread:2026-11-05",
                name: "계란빵", servingUnit: "개", servingGrams: 80,
                nutrition: NutritionValues(calories: 126, carbohydrateGrams: 10.66, proteinGrams: 6.16, fatGrams: 6.32),
                source: "FatSecret 일반 계란빵 참고값 · 개당 중량 약 80g 환산 · https://www.fatsecret.kr/칼로리-영양소/search?frc=True&q=계란빵",
                sourceDate: "2026-11-05", category: "일반 음식 참고값"
            ),
            aliases: ["달걀빵"]
        )
    ]

    static func entry(for name: String, brand: String = "", details: String = "") -> PreparedFoodReference? {
        guard brand.isEmpty, details.isEmpty else { return nil }
        let normalized = FoodReferenceCatalog.normalized(name)
        return entries.first { reference in
            ([reference.food.name] + reference.aliases).contains { FoodReferenceCatalog.normalized($0) == normalized }
        }
    }
}
