import Foundation

nonisolated struct PackagedFoodReference: Decodable, Sendable {
    let id: String
    let name: String
    let brand: String
    let aliases: [String]
    let productAliases: [String]?
    let brandAliases: [String]
    let catalogIDs: [String]
    let packageGrams: Double
    let calories: Double
    let carbohydrates: Double
    let protein: Double
    let fat: Double
    let sourceURL: String
    let checkedAt: String

    var isValid: Bool {
        !id.isEmpty && !name.isEmpty && !brand.isEmpty && !aliases.isEmpty
            && packageGrams.isFinite && (0.1...10000).contains(packageGrams)
            && [calories, carbohydrates, protein, fat].allSatisfy { $0.isFinite && $0 >= 0 }
            && carbohydrates + protein + fat <= packageGrams
            && calories <= packageGrams * 9.5
            && URL(string: sourceURL)?.scheme == "https" && !checkedAt.isEmpty
    }

    func matches(name: String, brand: String) -> Bool {
        let normalize = FoodReferenceCatalog.normalized
        guard brand.isEmpty || ([self.brand] + brandAliases).contains(where: { normalize($0) == normalize(brand) }) else { return false }
        let names = [self.name] + aliases
        let variants = names + ([self.brand] + brandAliases).flatMap { prefix in names.map { prefix + $0 } }
        return variants.contains { normalize($0) == normalize(name) }
    }

    func isExplicitProduct(name: String, brand: String) -> Bool {
        guard matches(name: name, brand: brand) else { return false }
        let normalize = FoodReferenceCatalog.normalized
        return !brand.isEmpty
            || ([self.brand] + brandAliases).contains { normalize(name).hasPrefix(normalize($0)) }
            || ([self.name] + (productAliases ?? [])).contains { normalize($0) == normalize(name) }
    }

    var food: FoodCatalogItem {
        FoodCatalogItem(
            id: id, name: name, servingUnit: "개", servingGrams: packageGrams,
            nutrition: NutritionValues(calories: calories, carbohydrateGrams: carbohydrates, proteinGrams: protein, fatGrams: fat),
            brand: brand, source: "제품 표시 영양정보 · \(sourceURL)", sourceDate: checkedAt, category: "가공식품"
        )
    }
}

nonisolated enum PackagedFoodCatalog {
    static let entries: [PackagedFoodReference] = {
        guard let url = Bundle.main.url(forResource: "PackagedFoodReferences", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([PackagedFoodReference].self, from: data),
              entries.allSatisfy(\.isValid), Set(entries.map(\.id)).count == entries.count else { return [] }
        return entries
    }()

    static func candidates(name: String, brand: String) -> [PackagedFoodReference] {
        entries.filter { $0.matches(name: name, brand: brand) }
    }

    static func entry(id: String) -> PackagedFoodReference? {
        entries.first { $0.id == id }
    }

    static func replacement(for food: FoodCatalogItem) -> PackagedFoodReference? {
        entries.first { $0.catalogIDs.contains(food.id) && $0.matches(name: food.name, brand: food.brand) }
    }
}

nonisolated enum FoodCatalogQuality {
    static let quarantinedIDs: Set<String> = ["D402-077000000-0001", "D702-077000000-0001"]

    static func isUsable(_ food: FoodCatalogItem) -> Bool {
        !quarantinedIDs.contains(food.id)
    }
}
