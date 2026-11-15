import Foundation

enum MealFoodNames {
    static func ramenCorrection(in text: String) -> String? {
        let compact = text.filter { !$0.isWhitespace }
        let expected = "야사이시오라멘"
        guard compact.count == expected.count,
              zip(compact, expected).filter({ $0 != $1 }).count == 1 else { return nil }
        return expected
    }

    static func relatedRamenQuery(_ name: String) -> String? {
        let compact = name.filter { !$0.isWhitespace }
        return ["야사이시오라멘", "야채시오라멘", "채소시오라멘"].contains(compact) ? "시오라멘" : nil
    }

    static func singleRelatedRamen(in text: String) -> [MealFoodInput]? {
        let pattern = #"^\s*((?:야\s*사\s*이|야\s*채|채\s*소)\s*시\s*오\s*라\s*멘)\s*(?:(?:\d+(?:\.\d+)?|한|두|반)\s*(?:인분|그릇|g))?\s*(?:먹었어|먹었어요)?[.!]?\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return [MealFoodInput(name: String(text[range]), sourceText: text, quantity: 1, unit: "인분", brand: "")]
    }

    private static let aliases = Dictionary(uniqueKeysWithValues: FoodReferenceCatalog.entries.map { ($0.name, $0.names) })

    static func canonical(_ name: String) -> String {
        FoodReferenceCatalog.entry(for: name)?.name ?? name
    }

    static func range(of name: String, in text: String, after start: String.Index? = nil) -> Range<String.Index>? {
        let names = name == "카레라이스" ? ["카레라이스", "카레"] : (aliases[canonical(name)] ?? [name])
        return names.compactMap { variant -> Range<String.Index>? in
            let pattern = FoodReferenceCatalog.standardizedSpelling(variant).filter { !$0.isWhitespace }
                .replacingOccurrences(of: "계란", with: "달걀")
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "\\s*")
                .replacingOccurrences(of: "달\\s*걀", with: "(?:달\\s*걀|계\\s*란)")
                .replacingOccurrences(of: "소\\s*시\\s*지", with: "소\\s*(?:시|세)\\s*지")
                .replacingOccurrences(of: "어\\s*묵", with: "(?:어\\s*묵|오\\s*뎅)")
                .replacingOccurrences(of: "주\\s*꾸\\s*미", with: "(?:주|쭈)\\s*꾸\\s*미")
            guard !pattern.isEmpty else { return nil }
            let boundary = names.count > 1 ? #"(?<![가-힣A-Za-z])"# : ""
            let ending = names.count > 1 ? #"(?=$|[\s\d.,!?·/]|이랑|랑|하고|이지만|은|는|을|에|과|와|도|만|없이|하나|한|두|둘|세|셋|네|넷|반|절반|조금|약간|먹)"# : ""
            return text.range(of: boundary + pattern + ending, options: [.regularExpression, .caseInsensitive], range: (start ?? text.startIndex)..<text.endIndex)
        }.sorted { left, right in
            left.lowerBound == right.lowerBound ? left.upperBound > right.upperBound : left.lowerBound < right.lowerBound
        }.first
    }

    static func extractionText(_ text: String) -> String {
        var result = text
        for name in aliases.keys.sorted(by: { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }) {
            var cursor = result.startIndex
            while let range = range(of: name, in: result, after: cursor) {
                if result[range].filter({ !$0.isWhitespace }) == "아아" {
                    cursor = range.upperBound
                    continue
                }
                let offset = result.distance(from: result.startIndex, to: range.lowerBound)
                result.replaceSubrange(range, with: name)
                cursor = result.index(result.startIndex, offsetBy: offset + name.count)
            }
        }
        return result
    }
}

enum MealInputGrounding {
    private static let amountPattern = #"(?i)(-?\d{1,3}(?:,\d{3})+(?:\.\d+)?|-?\d+(?:[.,]\d+)?|하나|다섯|여섯|일곱|여덟|아홉|한|두|둘|세|셋|네|넷|열|반)\s*(밀리리터|킬로그램|숟가락|숟갈|수저|그램|리터|봉지|인분|그릇|접시|공기|조각|큰술|작은술|국자|종지|mL|kg|g|L|개|줄|컵|잔|병|캔|봉|팩)(?:\s*(반))?"#

    /// 단위 없이 이름 뒤에 오는 개수(예: "김밥 하나", "만두 둘")
    private static let standaloneCountPattern = #"(?:하나|둘|셋|넷|다섯|여섯|일곱|여덟|아홉|열)"#

    static func singleFoodWithAmount(in text: String) -> MealFoodInput? {
        if let food = singleFoodWithCount(in: text) { return food }
        guard let range = text.range(of: amountPattern, options: .regularExpression),
              range.lowerBound != text.startIndex,
              text[range.upperBound...].range(of: #"^\s*(?:정도)?\s*(?:먹었어|먹었어요)?[.!]?\s*$"#, options: .regularExpression) != nil,
              let amount = explicitAmount(in: String(text[range])),
              amount.quantity.isFinite, (0.1...10000).contains(amount.quantity) else { return nil }
        let name = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60,
              name.allSatisfy({ $0.isLetter || $0.isWhitespace }),
              !["먹", "없이", "빼고", "말고", "대신", "하고", "이랑", "그리고"].contains(where: name.contains) else { return nil }
        return MealFoodInput(name: name, sourceText: text, quantity: amount.quantity, unit: amount.unit, brand: "")
    }

    /// "공기밥 하나"처럼 이름 + 단위 없는 개수. 단위는 음식을 찾은 뒤 대표 분량 단위로 정한다.
    private static func singleFoodWithCount(in text: String) -> MealFoodInput? {
        let pattern = #"^(.+?)\s+("# + standaloneCountPattern + #")\s*(?:정도)?\s*(?:먹었어|먹었어요)?[.!]?\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let nameRange = Range(match.range(at: 1), in: text),
              let countRange = Range(match.range(at: 2), in: text),
              let count = explicitAmount(in: String(text[countRange]) + "인분")?.quantity else { return nil }
        let name = text[nameRange].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, name.allSatisfy({ $0.isLetter || $0.isWhitespace }),
              !["먹", "없이", "빼고", "말고", "대신", "하고", "이랑", "그리고"].contains(where: name.contains) else { return nil }
        return MealFoodInput(name: name, sourceText: text, quantity: count, unit: "인분", brand: "", omittedUnit: true)
    }

    static func portionAnswer(_ answer: String, defaultUnit: String) -> (quantity: Double, unit: String)? {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["조금", "약간", "소량"].contains(text) { return (1, "소량") }
        if ["반", "절반"].contains(text) { return (0.5, defaultUnit) }
        let amount = amountPattern.replacingOccurrences(of: "(?i)", with: "")
        let pattern = "^" + amount + "\\s*(?:정도)?$"
        if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil,
           let parsed = explicitAmount(in: text), parsed.quantity.isFinite, (0.1...10000).contains(parsed.quantity) {
            return parsed
        }
        if text.range(of: #"^\d+(?:\.\d+)?$"#, options: .regularExpression) != nil,
           let quantity = Double(text), quantity.isFinite, (0.1...10000).contains(quantity) {
            return (quantity, defaultUnit)
        }
        return nil
    }

    static func singlePreparedReference(in text: String) -> [MealFoodInput]? {
        for reference in PreparedFoodReference.entries {
            guard let range = MealFoodNames.range(of: reference.food.name, in: text),
                  text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let amount = amountPattern.replacingOccurrences(of: "(?i)", with: "")
            let pattern = "^\\s*(?:" + amount + ")?\\s*(?:먹었어|먹었어요)?[.!]?\\s*$"
            guard String(text[range.upperBound...]).range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else { continue }
            return [MealFoodInput(name: String(text[range]), sourceText: text, quantity: 1, unit: "인분", brand: "")]
        }
        return nil
    }

    static func setMenuName(in text: String) -> String? {
        let pattern = #"(?<![가-힣A-Za-z])(?:[가-힣A-Za-z0-9]+\s*)?(?:정식|세트)(?=$|[\s\d.,!?]|이랑|랑|하고|은|는|을|에|과|와|도|만|하나|한|두|반|절반|먹)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let suffix = String(text[range.upperBound...])
            if suffix.range(of: #"^\s*(?:(?:은|는|을|도|만)\s*)*(?:안\s*먹|먹지\s*않|없|빼)"#, options: .regularExpression) != nil { continue }
            return String(text[range])
        }
        return nil
    }

    static func ground(_ inputs: [MealFoodInput], in text: String) throws -> [MealFoodInput] {
        let inputs = includingUnspecifiedSides(inputs, in: text)
        guard !inputs.isEmpty, inputs.count <= 8, inputs.allSatisfy(\.isValid) else {
            throw MealEntryError.invalidResult
        }
        var cursor = text.startIndex
        var ranges: [Range<String.Index>] = []
        for input in inputs {
            let name = foodName(input.name)
            guard let range = MealFoodNames.range(of: name, in: text, after: cursor)
            else { throw MealEntryError.invalidResult }
            ranges.append(range)
            cursor = range.upperBound
        }
        let grounded: [MealFoodInput] = inputs.enumerated().compactMap { index, input in
            let start = index == 0 ? text.startIndex : ranges[index].lowerBound
            let end = index + 1 < ranges.count ? ranges[index + 1].lowerBound : text.endIndex
            let source = String(text[start..<end])
            let suffix = String(text[ranges[index].upperBound..<end])
            if isUnspecifiedSide(input.name),
               suffix.range(of: #"^\s*(?:(?:은|는|을|도|조금|약간|만)\s*)*(?:안\s*먹|먹지\s*않|없|빼)"#, options: .regularExpression) != nil {
                return nil
            }
            let prefix = index == 0 ? String(text[start..<ranges[index].lowerBound]) : ""
            let amount = packageCount(in: suffix, name: foodName(input.name), brand: input.brand)
                ?? explicitAmount(in: suffix) ?? explicitAmount(in: prefix)
            let isSmall = suffix.contains("조금") || suffix.contains("약간") || suffix.contains("종지")
            let isHalf = suffix.range(of: #"(?:절반|반)(?:\s|$|만|을|은|는|에|과|이랑|랑|하고|먹|정도)"#, options: .regularExpression) != nil
            let name = String(text[ranges[index]])
            let isRice = MealFoodNames.canonical(name) == "쌀밥"
            let count = amount == nil ? standaloneCount(in: suffix) : nil
            let unit = amount?.unit ?? (isSmall ? "소량" : (isRice ? "공기" : "인분"))
            return MealFoodInput(
                name: name, sourceText: source,
                quantity: amount?.quantity ?? count ?? (isHalf ? 0.5 : 1),
                unit: isRice && unit == "개" ? "공기" : unit,
                brand: input.brand,
                omittedUnit: amount == nil && count != nil,
                omittedQuantity: amount == nil && count == nil && !isSmall && !isHalf
            )
        }
        guard !grounded.isEmpty else { throw MealEntryError.invalidResult }
        return grounded
    }

    static func isUnspecifiedSide(_ name: String) -> Bool {
        ["반찬", "반찬들", "밑반찬", "밑반찬들"].contains(name.filter { !$0.isWhitespace })
    }

    private static func includingUnspecifiedSides(_ inputs: [MealFoodInput], in text: String) -> [MealFoodInput] {
        guard let expression = try? NSRegularExpression(pattern: #"(?:밑반찬|반찬)(?:들)?(?=\s|조금|약간|도|은|는|을|과|이랑|랑|없이|$)"#) else { return inputs }
        var result = inputs
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let name = String(text[range])
            guard !result.contains(where: { $0.name.contains(name) || (isUnspecifiedSide($0.name) && isUnspecifiedSide(name)) }) else { continue }
            result.append(MealFoodInput(name: name, sourceText: text, quantity: 1, unit: "인분", brand: ""))
        }
        guard result.count != inputs.count else { return inputs }
        return result.sorted { left, right in
            let leftIndex = nameRange(foodName(left.name), in: text)?.lowerBound ?? text.endIndex
            let rightIndex = nameRange(foodName(right.name), in: text)?.lowerBound ?? text.endIndex
            return leftIndex < rightIndex
        }
    }

    private static func nameRange(_ name: String, in text: String) -> Range<String.Index>? {
        MealFoodNames.range(of: name, in: text)
    }

    private static func standaloneCount(in text: String) -> Double? {
        guard let range = text.range(of: #"^\s*"# + standaloneCountPattern + #"(?=\s|$|랑|와|과|만|을|정도|먹)"#, options: .regularExpression) else { return nil }
        return explicitAmount(in: text[range].trimmingCharacters(in: .whitespacesAndNewlines) + "인분")?.quantity
    }

    private static func foodName(_ name: String) -> String {
        guard let amountRange = name.range(of: amountPattern, options: .regularExpression),
              amountRange.lowerBound != name.startIndex,
              name[amountRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return name }
        return name[..<amountRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasExplicitAmount(in text: String) -> Bool {
        explicitAmount(in: text) != nil
    }

    private static func packageCount(in suffix: String, name: String, brand: String) -> (quantity: Double, unit: String)? {
        guard let product = PackagedFoodCatalog.candidates(name: name, brand: brand).first else { return nil }
        let grams = NSRegularExpression.escapedPattern(for: String(Int(product.packageGrams)))
        let pattern = #"^\s*"# + grams + #"\s*(?:g|그램)(?:짜리)?\s*((?:\d+(?:\.\d+)?|한|두|세|반)\s*(?:개|컵|봉|팩))(?:\s*먹(?:었어|었어요|음))?[.!]?\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: suffix, range: NSRange(suffix.startIndex..., in: suffix)),
              let countRange = Range(match.range(at: 1), in: suffix) else { return nil }
        return explicitAmount(in: String(suffix[countRange]))
    }

    private static func explicitAmount(in text: String) -> (quantity: Double, unit: String)? {
        let numbers: [String: Double] = ["한": 1, "하나": 1, "두": 2, "둘": 2, "세": 3, "셋": 3, "네": 4, "넷": 4, "다섯": 5, "여섯": 6, "일곱": 7, "여덟": 8, "아홉": 9, "열": 10, "반": 0.5]
        guard let expression = try? NSRegularExpression(pattern: amountPattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        let number = String(text[numberRange])
        let isGrouped = number.range(of: #"^-?\d{1,3}(?:,\d{3})+(?:\.\d+)?$"#, options: .regularExpression) != nil
        let numericText = number.replacingOccurrences(of: ",", with: isGrouped ? "" : ".")
        guard var quantity = numbers[number] ?? Double(numericText) else { return nil }
        if match.range(at: 3).location != NSNotFound { quantity += 0.5 }
        let originalUnit = String(text[unitRange]).lowercased()
        let unit: String
        switch originalUnit {
        case "kg", "킬로그램": unit = "g"; quantity *= 1000
        case "l", "리터": unit = "mL"; quantity *= 1000
        case "ml", "밀리리터": unit = "mL"
        case "그램": unit = "g"
        case "봉지": unit = "봉"
        case "숟갈", "수저": unit = "숟가락"
        default: unit = originalUnit
        }
        return (quantity, unit)
    }
}
