import Foundation

enum MealFoodNames {
    private static let aliases = Dictionary(uniqueKeysWithValues: FoodReferenceCatalog.entries.map { ($0.name, $0.names) })

    static func canonical(_ name: String) -> String {
        FoodReferenceCatalog.entry(for: name)?.name ?? name
    }

    static func range(of name: String, in text: String, after start: String.Index? = nil) -> Range<String.Index>? {
        let names = aliases[canonical(name)] ?? [name]
        return names.compactMap { variant -> Range<String.Index>? in
            let pattern = variant.filter { !$0.isWhitespace }
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "\\s*")
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
    private static let amountPattern = #"(?i)(-?\d{1,3}(?:,\d{3})+(?:\.\d+)?|-?\d+(?:[.,]\d+)?|하나|다섯|여섯|일곱|여덟|아홉|한|두|둘|세|셋|네|넷|열|반)\s*(밀리리터|킬로그램|숟가락|숟갈|수저|그램|리터|봉지|인분|그릇|접시|공기|조각|큰술|작은술|mL|kg|g|L|개|줄|컵|잔|봉|팩)(?:\s*(반))?"#

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
            let amount = explicitAmount(in: suffix) ?? explicitAmount(in: prefix)
            let isSmall = suffix.contains("조금") || suffix.contains("약간")
            let isHalf = suffix.range(of: #"(?:절반|반)(?:\s|$|만|을|은|는|에|과|이랑|랑|하고|먹|정도)"#, options: .regularExpression) != nil
            let name = String(text[ranges[index]])
            let isRice = MealFoodNames.canonical(name) == "쌀밥"
            let count = amount == nil ? standaloneCount(in: suffix) : nil
            let unit = amount?.unit ?? (isSmall ? "소량" : (isRice ? "공기" : "인분"))
            return MealFoodInput(
                name: name, sourceText: source,
                quantity: amount?.quantity ?? count ?? (isHalf ? 0.5 : 1),
                unit: isRice && unit == "개" ? "공기" : unit,
                brand: input.brand
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
        guard let range = text.range(of: #"^\s*(?:하나|둘|셋|넷|다섯|여섯|일곱|여덟|아홉|열)(?=\s|$|랑|와|과|만|을|먹)"#, options: .regularExpression) else { return nil }
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
