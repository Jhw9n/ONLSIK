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
    /// DB 항목의 분류. 없으면 조리 음식("음식")
    let category: String?
    /// 비슷한 음식 확인 질문에 보여줄 기준 설명(선택)
    let explanation: String?

    var names: [String] { [name] + aliases }

    func matches(_ food: FoodCatalogItem) -> Bool {
        food.id == referenceID && food.name == referenceName && food.amountUnit == amountUnit
            && food.source == source && food.sourceDate == sourceDate
            && food.brand.isEmpty && food.category == (category ?? "음식")
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
        standardizedSpelling(text).precomposedStringWithCompatibilityMapping.lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .replacingOccurrences(of: "계란", with: "달걀")
            .replacingOccurrences(of: "자장", with: "짜장")
            .replacingOccurrences(of: "돈까스", with: "돈가스")
    }

    static func standardizedSpelling(_ text: String) -> String {
        text.replacingOccurrences(of: #"소\s*세\s*지"#, with: "소시지", options: .regularExpression)
            .replacingOccurrences(of: #"오\s*뎅"#, with: "어묵", options: .regularExpression)
            .replacingOccurrences(of: #"쭈\s*꾸\s*미"#, with: "주꾸미", options: .regularExpression)
    }

    static func queries(for name: String) -> [String] {
        let reference = entry(for: name)
        var queries = [reference?.referenceName ?? name, reference?.name ?? name]
        queries.append(standardizedSpelling(name))
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

    static func similarDishQuery(for name: String) -> String? {
        similarDishIngredients(name)?.sorted().joined(separator: " ")
    }

    static func isSimilarPreparedDish(_ name: String, to candidate: String) -> Bool {
        guard let ingredients = similarDishIngredients(name),
              let candidateIngredients = similarDishIngredients(candidate) else { return false }
        return ingredients == candidateIngredients
    }

    private static func similarDishIngredients(_ name: String) -> Set<String>? {
        var remainder = normalized(name)
        let methods = ["볶음", "조림"].filter { remainder.contains($0) }
        guard methods.count == 1, let method = methods.first else { return nil }
        remainder = remainder.replacingOccurrences(of: method, with: "")
        let ingredients = ["소시지", "어묵", "돼지고기", "소고기", "닭고기", "오징어", "새우", "멸치",
                           "감자", "고구마", "양파", "당근", "양배추", "버섯", "두부", "김치", "가지", "애호박", "마늘", "햄"]
            .sorted { $0.count > $1.count }
        var found = Set<String>()
        while !remainder.isEmpty {
            guard let ingredient = ingredients.first(where: { remainder.hasPrefix($0) }),
                  found.insert(ingredient).inserted else { return nil }
            remainder.removeFirst(ingredient.count)
        }
        return found.count >= 2 ? found : nil
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
