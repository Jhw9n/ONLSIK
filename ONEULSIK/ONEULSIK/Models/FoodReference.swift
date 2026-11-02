import Foundation

nonisolated struct FoodReference: Decodable, Sendable {
    let name: String
    let aliases: [String]
    let referenceID: String
    let referenceName: String
    let amountUnit: String
    let source: String
    let sourceDate: String
    let estimatedPortions: [String: Double]?

    var names: [String] { [name] + aliases }

    func matches(_ food: FoodCatalogItem) -> Bool {
        food.id == referenceID && food.name == referenceName && food.amountUnit == amountUnit
            && food.source == source && food.sourceDate == sourceDate
            && food.brand.isEmpty && food.category == "음식"
    }

    func estimatedAmount(for unit: String, food: FoodCatalogItem) -> Double? {
        guard matches(food), let amount = estimatedPortions?[unit],
              amount.isFinite, (0.1...5000).contains(amount) else { return nil }
        return amount
    }
}

nonisolated enum FoodReferenceCatalog {
    static let entries: [FoodReference] = {
        guard let url = Bundle.main.url(forResource: "FoodReferences", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([FoodReference].self, from: data) else { return [] }
        return entries
    }()

    static func entry(for name: String) -> FoodReference? {
        let key = normalized(name)
        return entries.first { $0.names.contains { normalized($0) == key } }
    }

    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .replacingOccurrences(of: "계란", with: "달걀")
            .replacingOccurrences(of: "자장", with: "짜장")
            .replacingOccurrences(of: "돈까스", with: "돈가스")
    }

    static func queries(for name: String) -> [String] {
        let reference = entry(for: name)
        var queries = [reference?.referenceName ?? name, reference?.name ?? name]
        let compact = normalized(name)
        if compact.hasSuffix("젓갈"), compact != "젓갈" {
            queries.append("\(compact.dropLast(2)) 젓")
        }
        for suffix in ["스파게티", "볶음밥", "순두부찌개", "김치찌개", "된장찌개", "돈가스", "김밥", "칼국수", "미역국", "초밥", "불고기", "덮밥", "찌개", "파스타"] {
            if compact.hasSuffix(suffix), compact.count > suffix.count {
                let dish = suffix == "파스타" ? "스파게티" : suffix
                queries.append("\(dish) \(compact.dropLast(suffix.count))")
                break
            }
        }
        var seen = Set<String>()
        return queries.filter { seen.insert($0).inserted }
    }

    static func spellingCandidates(for name: String) -> [FoodReference] {
        let query = normalized(name)
        guard query.count >= 4 else { return [] }
        return entries.filter { entry in
            entry.names.contains { candidate in
                let key = normalized(candidate)
                guard key.count >= 4, abs(key.count - query.count) <= 1,
                      !query.hasPrefix(key), !key.hasPrefix(query) else { return false }
                return distance(query, key) == 1
            }
        }.prefix(3).map { $0 }
    }

    private static func distance(_ left: String, _ right: String) -> Int {
        let right = Array(right)
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(current[rightIndex] + 1, previous[rightIndex + 1] + 1,
                                   previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)))
            }
            previous = current
        }
        return previous[right.count]
    }
}
