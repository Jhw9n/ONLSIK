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
    /// 식약처 원본 `식품중량`의 제품 1개 총중량(baseAmount와 같은 단위). 없으면 0
    var packageAmount: Double = 0
    /// 식약처 원본의 식품 대·중·소분류 조합 코드(DB `category_code`, `food_categories.code`). 가공식품에만 있고 없으면 nil
    var categoryCode: Int? = nil
    /// 입력 단위(예: 1인분)를 대표 분량의 다른 단위(예: 1접시)로 계산했을 때 그 단위. 저장하지 않는 화면용 값
    var referencePortionUnit: String = ""

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

extension Array where Element == FoodCatalogItem {
    /// 같은 이름 후보의 분류 다수결 정렬. 정규화한 이름이 `name`과 같고 분류 코드가 있는 후보가 둘 이상이면,
    /// 그중 분류 코드가 같은 후보가 가장 많은 분류를 먼저 둔다. 동률이면 그대로 둔다.
    /// 같은 이름 후보들은 원래 차지하던 자리 안에서만 순서를 바꾸고(다른 후보의 자리는 그대로),
    /// 같은 분류 안의 순서는 원래 순서를 유지한다. 검색(FoodCatalogService)과 식사 입력 후보 정렬이 함께 쓴다.
    func groupedByMajorityCategory(sameNameAs name: String) -> [FoodCatalogItem] {
        let key = FoodReferenceCatalog.normalized(name)
        guard !key.isEmpty else { return self }
        let slots = indices.filter { self[$0].categoryCode != nil && FoodReferenceCatalog.normalized(self[$0].name) == key }
        guard slots.count >= 2 else { return self }
        var counts: [Int: Int] = [:]
        for index in slots { counts[self[index].categoryCode!, default: 0] += 1 }
        let ranked = counts.sorted { $0.value > $1.value }
        guard let majority = ranked.first, ranked.count >= 2, ranked[1].value < majority.value else { return self }
        let reordered = slots.filter { self[$0].categoryCode == majority.key } + slots.filter { self[$0].categoryCode != majority.key }
        var result = self
        for (slot, source) in zip(slots, reordered) { result[slot] = self[source] }
        return result
    }
}
