import Foundation

nonisolated struct FoodCatalogItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let servingUnit: String
    let servingGrams: Double
    let nutrition: NutritionValues
    var servingMilliliters: Double = 0
    var brand: String = ""
    var source: String = ""
    var sourceDate: String = ""
    var category: String = ""

    var baseAmount: Double { servingMilliliters > 0 ? servingMilliliters : servingGrams }
    var amountUnit: String { servingMilliliters > 0 ? "mL" : "g" }
    var representativePortion: FoodPortion? { FoodPortion.representative(for: self) }

    var selectionDescription: String {
        guard let portion = representativePortion else {
            return "\(baseAmount.formatted(.number.precision(.fractionLength(0...2))))\(amountUnit) 기준"
        }
        return "1\(portion.unit) 약 \(portion.grams.formatted(.number.precision(.fractionLength(0))))g · 대표 분량"
    }

    var recordedName: String {
        brand.isEmpty ? name : "\(name) · \(brand)"
    }

    func nutrition(for servingCount: Double) -> NutritionValues {
        nutrition * servingCount
    }

    func servingDescription(for servingCount: Double) -> String {
        let count = servingCount.formatted(
            .number.precision(.fractionLength(servingCount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1))
        )
        let amount = ((servingMilliliters > 0 ? servingMilliliters : servingGrams) * servingCount).formatted(
            .number.precision(.fractionLength(0))
        )
        let unit = servingMilliliters > 0 ? "mL" : "g"
        return "\(count)\(servingUnit) (\(amount)\(unit))"
    }
}
