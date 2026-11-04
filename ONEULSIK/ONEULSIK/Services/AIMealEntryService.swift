import Foundation

struct MealFoodInput: Codable {
    let name: String
    let sourceText: String
    let quantity: Double
    let unit: String
    let brand: String
    var details: String = ""
    var isSideDish = false

    var isValid: Bool {
        !name.isEmpty && name.count <= 60 && sourceText.count <= 500
            && quantity.isFinite && (0.1...10000).contains(quantity)
            && Self.units.contains(unit) && brand.count <= 60 && details.count <= 200
    }

    static let units: Set<String> = ["인분", "개", "줄", "공기", "그릇", "접시", "컵", "잔", "조각", "봉", "팩", "숟가락", "큰술", "작은술", "소량", "g", "mL"]
}

struct MealFoodSelection {
    let input: MealFoodInput
    let food: FoodCatalogItem
    var isSimilar = false
}

struct MealFoodAssessment {
    let candidateIndex: Int
    let clarification: MealClarificationReason
}

enum MealClarificationReason: String {
    case none
    case sauce
    case preparation
    case ingredients

    func question(for name: String) -> String? {
        switch self {
        case .none: nil
        case .sauce: "‘\(name)’은 어떤 소스였나요?"
        case .preparation: "‘\(name)’은 어떻게 조리했나요?"
        case .ingredients: "‘\(name)’에 어떤 재료가 들어갔나요?"
        }
    }
}

struct MealNutritionEstimate {
    let referenceFood: String
    let amountPerUnit: Double
    let amountUnit: String
    let nutritionPer100: NutritionValues
    let ingredients: String

    var isValid: Bool {
        let macros = [nutritionPer100.carbohydrateGrams, nutritionPer100.proteinGrams, nutritionPer100.fatGrams]
        let macroEnergy = macros[0] * 4 + macros[1] * 4 + macros[2] * 9
        return !referenceFood.isEmpty && referenceFood.count <= 60
            && amountPerUnit.isFinite && (0.1...5000).contains(amountPerUnit)
            && ["g", "mL"].contains(amountUnit)
            && macros.allSatisfy { $0.isFinite && (0...100).contains($0) }
            && macros.reduce(0, +) <= 100
            && nutritionPer100.calories.isFinite && (0...950).contains(nutritionPer100.calories)
            && abs(nutritionPer100.calories - macroEnergy) <= max(25, macroEnergy * 0.25)
            && !ingredients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ingredients.count <= 200
    }
}

struct MealPortionEstimate {
    let amountPerUnit: Double
    let amountUnit: String

    func isPlausible(for unit: String, foodName: String = "") -> Bool {
        guard amountPerUnit.isFinite, (0.1...5000).contains(amountPerUnit) else { return false }
        let name = foodName.filter { !$0.isWhitespace }
        let bowlMeals = ["국밥", "덮밥", "비빔밥", "볶음밥", "짜장면", "자장면", "짬뽕", "냉면", "칼국수", "우동", "스파게티", "파스타"]
        if ["인분", "그릇", "접시", "공기"].contains(unit), bowlMeals.contains(where: name.hasSuffix) {
            return (200...2000).contains(amountPerUnit)
        }
        switch unit {
        case "숟가락", "큰술":
            return (1...50).contains(amountPerUnit)
        case "작은술":
            return (0.5...20).contains(amountPerUnit)
        case "공기", "그릇", "접시", "컵", "잔":
            return amountPerUnit >= 20
        case "인분", "줄", "봉", "팩":
            return amountPerUnit >= 5
        default:
            return true
        }
    }
}

@MainActor
protocol MealFoodInterpreting {
    func foods(in text: String) async throws -> [MealFoodInput]
    func portion(for input: MealFoodInput, food: FoodCatalogItem) async throws -> MealPortionEstimate
    func assess(_ input: MealFoodInput, candidates: [FoodCatalogItem]) async throws -> MealFoodAssessment
    func estimateNutrition(for input: MealFoodInput) async throws -> MealNutritionEstimate?
    func searchTerms(for input: MealFoodInput) async throws -> [String]
}

extension MealFoodInterpreting {
    func searchTerms(for input: MealFoodInput) async throws -> [String] { [] }
}

@MainActor
protocol MealFoodSearching {
    func search(query: String) async throws -> [FoodCatalogItem]
    func food(id: String) async throws -> FoodCatalogItem?
}

extension MealFoodSearching {
    func food(id: String) async throws -> FoodCatalogItem? { nil }
}

extension FoodCatalogService: MealFoodSearching {}

final class AIMealEntryService: MealEntryAnalyzing {
    private let interpreter: any MealFoodInterpreting
    private let catalog: any MealFoodSearching

    init(interpreter: (any MealFoodInterpreting)? = nil, catalog: (any MealFoodSearching)? = nil) {
        self.interpreter = interpreter ?? AppleMealFoodInterpreter()
        self.catalog = catalog ?? FoodCatalogService()
    }

    func analyze(_ text: String) async throws -> MealEntryAnalysis {
        try await MealPerformance.measure("analyze") { try await analyzeMeal(text) }
    }

    private func analyzeMeal(_ text: String) async throws -> MealEntryAnalysis {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MealEntryError.invalidResult }
        guard text.count <= 500 else { throw MealEntryError.inputTooLong }
        if let name = MealInputGrounding.setMenuName(in: text) {
            let input = MealFoodInput(name: name, sourceText: text, quantity: 1, unit: "인분", brand: "")
            return .question(MealEntryQuestion(
                title: "‘\(name)’에 어떤 음식이 있었나요?",
                explanation: "함께 먹은 음식까지 이번 식사 전체를 적어주세요. 구성은 임의로 추가하지 않아요",
                choices: [],
                clarification: MealEntryChoice(id: UUID().uuidString, title: "확인", items: [], continuationInput: input),
                inputPlaceholder: "예: 고등어구이, 밥 한 공기, 미소된장국"
            ))
        }
        let generated = try await interpreter.foods(in: MealFoodNames.extractionText(text))
        try Task.checkCancellation()
        let inputs = try MealInputGrounding.ground(generated, in: text)
        for input in inputs {
            guard input.isValid, !input.sourceText.isEmpty,
                  text.contains(input.sourceText),
                  normalized(input.sourceText).contains(normalized(input.name)),
                  input.brand.isEmpty || normalized(input.sourceText).contains(normalized(input.brand))
            else { throw MealEntryError.invalidResult }
        }
        return try await resolve(inputs, items: [])
    }

    func resolve(_ choice: MealEntryChoice) async throws -> MealEntryAnalysis {
        try await MealPerformance.measure("clarify") { try await resolveChoice(choice) }
    }

    private func resolveChoice(_ choice: MealEntryChoice) async throws -> MealEntryAnalysis {
        if let input = choice.continuationInput {
            guard input.isValid, !input.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MealEntryError.invalidResult
            }
            if MealInputGrounding.setMenuName(in: input.name) != nil {
                return try await analyzeMeal(input.details)
            }
            if isUnspecified(input.name) {
                let generated = try await interpreter.foods(in: MealFoodNames.extractionText(input.details))
                try Task.checkCancellation()
                let foods = try MealInputGrounding.ground(generated, in: input.details)
                guard foods.allSatisfy({ $0.isValid && !isUnspecified($0.name)
                    && ($0.brand.isEmpty || normalized($0.sourceText).contains(normalized($0.brand))) }) else {
                    throw MealEntryError.foodNotFound(input.name)
                }
                guard choice.items.count + foods.count + choice.remainingFoods.count <= 8 else { throw MealEntryError.inputTooLong }
                let clarified = foods.map { food in
                    let usesOriginalAmount = !MealInputGrounding.hasExplicitAmount(in: food.sourceText)
                        && food.unit == "인분" && food.quantity == 1
                    return MealFoodInput(
                        name: food.name, sourceText: food.sourceText,
                        quantity: usesOriginalAmount ? input.quantity : food.quantity,
                        unit: usesOriginalAmount ? input.unit : food.unit, brand: food.brand,
                        isSideDish: true
                    )
                }
                return try await resolve(clarified + choice.remainingFoods, items: choice.items)
            }
            return try await resolve([input] + choice.remainingFoods, items: choice.items)
        }
        guard let selection = choice.selection else { return .ready(choice.items) }
        let item = try await makeItem(selection)
        return try await resolve(choice.remainingFoods, items: choice.items + [item])
    }

    private func resolve(_ inputs: [MealFoodInput], items: [MealEntryItem]) async throws -> MealEntryAnalysis {
        var items = items
        for (index, original) in inputs.enumerated() {
            try Task.checkCancellation()
            let input = MealFoodInput(
                name: original.brand.isEmpty ? MealFoodNames.canonical(original.name) : original.name,
                sourceText: original.sourceText, quantity: original.quantity, unit: original.unit,
                brand: original.brand, details: original.details, isSideDish: original.isSideDish
            )
            let remaining = Array(inputs.dropFirst(index + 1))
            if isUnspecified(input.name) {
                return try clarification(for: input, question: "어떤 반찬을 드셨나요?", items: items, remaining: remaining)
            }
            if input.brand.isEmpty, input.details.isEmpty,
               let reference = FoodReferenceCatalog.entry(for: input.name),
               let food = try await catalog.food(id: reference.referenceID) {
                try Task.checkCancellation()
                if reference.matches(food), candidates(from: [food], input: input).first != nil {
                    items.append(try await makeItem(MealFoodSelection(input: input, food: food, isSimilar: normalized(food.name) != normalized(input.name))))
                    continue
                }
            }
            let foodName = input.brand.isEmpty ? input.name : input.name.replacingOccurrences(of: input.brand, with: "")
            let query = searchName(foodName)
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MealEntryError.invalidResult }
            let results = try await catalog.search(query: [input.brand, query].filter { !$0.isEmpty }.joined(separator: " "))
            try Task.checkCancellation()
            var compatible = candidates(from: results, input: input)
            var candidates = Array(compatible.prefix(8))

            let needsSauce = ["스파게티", "파스타"].contains(normalized(input.name)) && input.details.isEmpty
            if input.brand.isEmpty, input.details.isEmpty,
               let reference = FoodReferenceCatalog.entry(for: input.name),
               let food = compatible.first(where: reference.matches) {
                items.append(try await makeItem(MealFoodSelection(input: input, food: food, isSimilar: normalized(food.name) != normalized(input.name))))
                continue
            }
            let exact = compatible.filter { normalized($0.name) == normalized(query) }
            if let food = exact.first, !needsSauce, input.details.isEmpty,
               (input.brand.isEmpty ? food.brand.isEmpty && food.category != "가공식품" : true) {
                items.append(try await makeItem(MealFoodSelection(input: input, food: food)))
                continue
            }
            let sauces = needsSauce ? sauceCandidates(compatible) : []
            if !sauces.isEmpty {
                return .question(MealEntryQuestion(
                    title: "어떤 소스였나요?",
                    explanation: "먹은 음식과 가까운 종류를 골라주세요",
                    choices: sauces.map { food in
                        MealEntryChoice(
                            id: food.id, title: food.recordedName, items: items,
                            selection: MealFoodSelection(input: input, food: food),
                            remainingFoods: remaining
                        )
                    }
                ))
            }
            var selected: FoodCatalogItem?
            var missingInformation = MealClarificationReason.none
            for attempt in 0..<2 {
                if attempt == 1 {
                    let terms = try await interpreter.searchTerms(for: input)
                    try Task.checkCancellation()
                    var expanded = compatible
                    var seen = Set(expanded.map(\.id))
                    var searched = Set([normalized(query)])
                    for term in terms.prefix(2) {
                        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !term.isEmpty, term.count <= 60, searched.insert(normalized(term)).inserted else { continue }
                        let search = [input.brand, term].filter { !$0.isEmpty }.joined(separator: " ")
                        let matches = try await catalog.search(query: search)
                        try Task.checkCancellation()
                        expanded += self.candidates(from: matches, input: input).filter { seen.insert($0.id).inserted }
                    }
                    let additions = expanded.filter { food in !compatible.contains { $0.id == food.id } }
                    guard !additions.isEmpty else { break }
                    candidates = Array(additions.prefix(6)) + Array(compatible.prefix(2))
                    compatible = expanded
                }
                guard !candidates.isEmpty else { continue }
                let assessment = try await interpreter.assess(input, candidates: candidates)
                try Task.checkCancellation()
                guard (0...candidates.count).contains(assessment.candidateIndex) else {
                    throw MealEntryError.invalidResult
                }
                missingInformation = assessment.clarification
                if assessment.candidateIndex > 0 {
                    selected = candidates[assessment.candidateIndex - 1]
                    break
                }
            }
            if let food = selected {
                items.append(try await makeItem(MealFoodSelection(input: input, food: food, isSimilar: true)))
                continue
            }
            if input.details.isEmpty, let question = missingInformation.question(for: input.name) {
                return try clarification(for: input, question: question, items: items, remaining: remaining)
            }
            if let estimate = try await interpreter.estimateNutrition(for: input) {
                try Task.checkCancellation()
                guard try await hasGroundedReference(estimate, input: input) else {
                    return try clarification(for: input, question: "어떤 재료나 소스가 들어갔나요?", items: items, remaining: remaining)
                }
                items.append(try estimatedItem(input, estimate: estimate))
            } else {
                try Task.checkCancellation()
                return try clarification(for: input, question: "어떤 재료나 소스가 들어갔나요?", items: items, remaining: remaining)
            }
        }
        guard !items.isEmpty, items.allSatisfy(\.isValid) else { throw MealEntryError.invalidResult }
        return .ready(items)
    }

    private func candidates(from results: [FoodCatalogItem], input: MealFoodInput) -> [FoodCatalogItem] {
        let compatible = results.filter { food in
            guard food.baseAmount.isFinite, food.baseAmount > 0,
                  [food.nutrition.calories, food.nutrition.carbohydrateGrams, food.nutrition.proteinGrams, food.nutrition.fatGrams]
                    .allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
            if input.unit == "g" || input.unit == "mL", input.unit != food.amountUnit { return false }
            return input.brand.isEmpty || normalized(food.brand + food.name).contains(normalized(input.brand))
        }
        let filtered: [FoodCatalogItem]
        if input.brand.isEmpty {
            let general = compatible.filter { $0.brand.isEmpty && $0.category != "가공식품" }
            let exactProducts = compatible.filter { normalized($0.name) == normalized(searchName(input.name)) }
            let prepared = general.filter { $0.category == "음식" }
            let hasGeneralDish = prepared.contains {
                guard let dish = $0.name.split(whereSeparator: \.isWhitespace).first else { return false }
                return normalized(String(dish)) == normalized(searchName(input.name))
            }
            let hasReference = FoodReferenceCatalog.entry(for: input.name).map { reference in general.contains(where: reference.matches) } ?? false
            if input.isSideDish, !prepared.isEmpty {
                filtered = prepared
            } else {
                filtered = hasReference || hasGeneralDish || general.contains { normalized($0.name) == normalized(searchName(input.name)) } || exactProducts.isEmpty
                    ? general : exactProducts
            }
        } else {
            filtered = compatible
        }
        let reference = FoodReferenceCatalog.entry(for: input.name)
        let ordered = filtered.sorted { left, right in
            let leftIsReference = reference?.matches(left) == true
            let rightIsReference = reference?.matches(right) == true
            if leftIsReference != rightIsReference { return leftIsReference }
            if (left.amountUnit == "g") != (right.amountUnit == "g") { return left.amountUnit == "g" }
            return false
        }
        var seen = Set<String>()
        return ordered.filter { seen.insert(normalized($0.name + $0.brand)).inserted }
    }

    private func sauceCandidates(_ foods: [FoodCatalogItem]) -> [FoodCatalogItem] {
        ["토마토", "크림", "오일", "로제"].compactMap { sauce in
            let names = ["스파게티\(sauce)소스", "\(sauce)스파게티", "\(sauce)파스타"]
            return foods.first { names.contains(normalized($0.name)) && $0.category != "원재료성 식품" }
        }
    }

    private func hasGroundedReference(_ estimate: MealNutritionEstimate, input: MealFoodInput) async throws -> Bool {
        let reference = normalized(estimate.referenceFood)
        guard !reference.isEmpty, estimate.referenceFood.count <= 60,
              normalized(input.name + " " + input.details).contains(reference) else { return false }
        let query = searchName(estimate.referenceFood)
        let references = try await catalog.search(query: query)
        try Task.checkCancellation()
        let terms = query.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }
        return references.contains { food in
            terms.allSatisfy { normalized(food.name).contains($0) }
        }
    }

    private func clarification(for input: MealFoodInput, question: String, items: [MealEntryItem], remaining: [MealFoodInput]) throws -> MealEntryAnalysis {
        guard input.details.isEmpty else { throw MealEntryError.foodNotFound(input.name) }
        return .question(MealEntryQuestion(
            title: question,
            explanation: isUnspecified(input.name) ? "여러 가지라면 쉼표로 나눠 알려주세요" : "‘\(input.name)’에 대해 짧게 알려주세요",
            choices: [],
            clarification: MealEntryChoice(id: UUID().uuidString, title: "확인", items: items, remainingFoods: remaining, continuationInput: input),
            inputPlaceholder: isUnspecified(input.name) ? "먹은 반찬 이름을 적어주세요" : "재료나 조리 방법을 짧게 적어주세요"
        ))
    }

    private func isUnspecified(_ name: String) -> Bool {
        MealInputGrounding.isUnspecifiedSide(name)
    }

    private func estimatedItem(_ input: MealFoodInput, estimate: MealNutritionEstimate) throws -> MealEntryItem {
        guard estimate.isValid else { throw MealEntryError.invalidResult }
        let isMeasured = input.unit == "g" || input.unit == "mL"
        guard !isMeasured || input.unit == estimate.amountUnit else { throw MealEntryError.portionUnknown(input.name) }
        let portion = MealPortionEstimate(amountPerUnit: estimate.amountPerUnit, amountUnit: estimate.amountUnit)
        guard isMeasured || portion.isPlausible(for: input.unit, foodName: input.name) else { throw MealEntryError.portionUnknown(input.name) }
        let useAmount = isMeasured || input.unit == "소량"
        let basis = useAmount ? 1 : estimate.amountPerUnit
        let count = input.unit == "소량" ? input.quantity * estimate.amountPerUnit : input.quantity
        guard (0.1...10000).contains(basis * count) else { throw MealEntryError.portionUnknown(input.name) }
        let food = FoodCatalogItem(
            id: "estimated-\(UUID().uuidString)", name: input.name,
            servingUnit: useAmount ? estimate.amountUnit : input.unit,
            servingGrams: estimate.amountUnit == "g" ? basis : 0,
            nutrition: estimate.nutritionPer100 * (basis / 100),
            servingMilliliters: estimate.amountUnit == "mL" ? basis : 0,
            source: "온디바이스 영양 추정 · \(estimate.ingredients)", category: "추정 음식"
        )
        let item = MealEntryItem(food: food, servingCount: count, portionBasis: isMeasured ? .entered : .estimated, nutritionBasis: .estimated)
        guard item.isValid else { throw MealEntryError.invalidResult }
        return item
    }

    private func makeItem(_ selection: MealFoodSelection) async throws -> MealEntryItem {
        let input = selection.input
        let food = selection.food
        let basis: Double
        let count: Double
        let unit: String
        let origin: MealPortionBasis

        if input.unit == "g" || input.unit == "mL" {
            guard input.unit == food.amountUnit else { throw MealEntryError.portionUnknown(input.name) }
            basis = 1
            count = input.quantity
            unit = input.unit
            origin = .entered
        } else if let portion = food.representativePortion,
                  input.unit == portion.unit || input.unit == "인분" {
            basis = portion.grams
            count = input.quantity
            unit = portion.unit
            origin = .representative
        } else if input.brand.isEmpty, input.details.isEmpty,
                  let reference = FoodReferenceCatalog.entry(for: input.name),
                  let amount = reference.estimatedAmount(for: input.unit, food: food) {
            basis = amount
            count = input.quantity
            unit = input.unit
            origin = .estimated
        } else {
            let estimate = try await interpreter.portion(for: input, food: food)
            try Task.checkCancellation()
            guard estimate.isPlausible(for: input.unit, foodName: input.name),
                  estimate.amountUnit == food.amountUnit else { throw MealEntryError.portionUnknown(input.name) }
            basis = input.unit == "소량" ? 1 : estimate.amountPerUnit
            count = input.unit == "소량" ? estimate.amountPerUnit * input.quantity : input.quantity
            unit = input.unit == "소량" ? food.amountUnit : input.unit
            origin = .estimated
        }
        guard (0.1...10000).contains(basis * count) else { throw MealEntryError.portionUnknown(input.name) }
        let adjusted = FoodCatalogItem(
            id: food.id, name: selection.isSimilar ? input.name : food.name, servingUnit: unit,
            servingGrams: food.amountUnit == "g" ? basis : 0,
            nutrition: food.nutrition(for: basis / food.baseAmount),
            servingMilliliters: food.amountUnit == "mL" ? basis : 0,
            brand: selection.isSimilar ? "" : food.brand,
            source: selection.isSimilar ? "유사 음식: \(food.recordedName) · \(food.source)" : food.source,
            sourceDate: food.sourceDate, category: food.category
        )
        let item = MealEntryItem(food: adjusted, servingCount: count, portionBasis: origin, nutritionBasis: selection.isSimilar ? .similarFood : .database)
        guard item.isValid else { throw MealEntryError.invalidResult }
        return item
    }

    private func searchName(_ name: String) -> String {
        let name = MealFoodNames.canonical(name).replacingOccurrences(of: "파스타", with: "스파게티")
        let compact = normalized(name)
        if compact == "밥" { return "쌀밥" }
        if compact.hasSuffix("젓갈"), compact != "젓갈" {
            return "\(compact.dropLast(2)) 젓"
        }
        for sauce in ["토마토", "크림", "오일", "로제"] {
            if compact == sauce + "스파게티" || compact == "스파게티" + sauce {
                return "스파게티 \(sauce)소스"
            }
        }
        return name
    }

    private func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .replacingOccurrences(of: "계란", with: "달걀")
            .replacingOccurrences(of: "자장", with: "짜장")
            .replacingOccurrences(of: "돈까스", with: "돈가스")
    }
}
