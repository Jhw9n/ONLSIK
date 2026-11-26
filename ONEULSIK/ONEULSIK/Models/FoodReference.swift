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
    /// 비슷한 음식 확인 질문에 보여줄 화면 문구(선택). 날짜·결정·출처 메모는 넣지 않는다.
    let displayText: String?
    /// 내부 근거(결정 날짜, 출처 메모). 화면에 보여주지 않는다.
    let basisNote: String?
    /// 업체 제품(brand가 있는 레코드)을 기준 자료로 가리킬 수 있는지(선택, 기본 false, 2026-11-24 #43).
    /// true인 항목만 brand 있는 레코드를 referenceID로 쓸 수 있고, 이름·별칭이 맞는 업체명 없는 입력은 제품·비슷한 음식 질문 없이
    /// 그 제품의 영양값과 estimatedPortions 분량으로 기록한다(AIMealEntryService.resolveBrandedReference). 분류는 category로 적는다.
    let allowsBrandedProduct: Bool?

    var allowsBranded: Bool { allowsBrandedProduct == true }

    var names: [String] { [name] + aliases }

    func matches(_ food: FoodCatalogItem) -> Bool {
        food.id == referenceID && food.name == referenceName && food.amountUnit == amountUnit
            && food.source == source && food.sourceDate == sourceDate
            && (food.brand.isEmpty || allowsBranded) && food.category == (category ?? "음식")
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

    /// 이름(정규화 키) → 항목. 같은 키가 여러 항목에 있으면 파일 앞쪽 항목(전과 같은 `first` 규칙).
    /// 참고표가 수백 개라(어순 별칭, #51) 조회마다 모든 이름을 정규화하지 않도록 처음 한 번만 만든다. 결과는 전과 같다.
    private static let entryByKey: [String: FoodReference] = {
        var result: [String: FoodReference] = [:]
        for entry in entries {
            for name in entry.names where result[normalized(name)] == nil {
                result[normalized(name)] = entry
            }
        }
        return result
    }()

    /// 항목마다 정규화한 이름(spellingCandidates용, 항목 순서 그대로)
    private static let normalizedNames: [(entry: FoodReference, keys: [String])] = entries.map { entry in
        (entry, entry.names.map(normalized))
    }

    static func entry(for name: String) -> FoodReference? {
        entryByKey[normalized(name)]
    }

    /// 비교용 키: 표기 변형(SpellingVariants.json)을 맞추고 소문자·글자·숫자만 남긴다.
    static func normalized(_ text: String) -> String {
        SpellingVariant.standardize(text.precomposedStringWithCompatibilityMapping.lowercased())
            .filter { $0.isLetter || $0.isNumber }
    }

    /// 표기 변형만 표준 표기로 바꾼다(띄어쓰기·기호는 그대로).
    static func standardizedSpelling(_ text: String) -> String {
        SpellingVariant.standardize(text)
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
        return normalizedNames.filter { _, keys in
            keys.contains { key in
                guard key.count >= 4, abs(key.count - query.count) <= 1,
                      !query.hasPrefix(key), !key.hasPrefix(query) else { return false }
                return distance(query, key) == 1
            }
        }.prefix(3).map(\.entry)
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
