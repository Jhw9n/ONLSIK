import Foundation

struct MealFoodInput: Codable {
    let name: String
    let sourceText: String
    let quantity: Double
    let unit: String
    let brand: String
    var details: String = ""
    var isSideDish = false
    var hasConfirmedPortion = false
    /// 개수만 있고 단위가 없음(예: "김밥 하나"). 단위는 음식의 대표 분량 단위로 정한다.
    var omittedUnit = false
    /// 수량을 적지 않음(예: "순두부찌개"). 대표 분량이 있으면 1단위로 가정하고, 없으면 수량을 묻는다.
    var omittedQuantity = false

    /// 단위만 바꾼 입력(수량·단위를 적지 않은 입력의 단위를 정할 때)
    func withUnit(_ unit: String) -> MealFoodInput {
        MealFoodInput(name: name, sourceText: sourceText, quantity: quantity, unit: unit,
            brand: brand, details: details, isSideDish: isSideDish,
            hasConfirmedPortion: hasConfirmedPortion, omittedUnit: omittedUnit, omittedQuantity: omittedQuantity)
    }

    var isValid: Bool {
        !name.isEmpty && name.count <= 60 && sourceText.count <= 500
            && quantity.isFinite && (0.1...10000).contains(quantity)
            && Self.units.contains(unit) && brand.count <= 60 && details.count <= 200
    }

    static let units: Set<String> = ["인분", "개", "줄", "공기", "그릇", "접시", "컵", "잔", "병", "캔", "조각", "봉", "팩", "숟가락", "큰술", "작은술", "국자", "종지", "마리", "소량", "g", "mL"]
}

struct MealFoodSelection {
    let input: MealFoodInput
    let food: FoodCatalogItem
    var isSimilar = false
    var portionOverride: MealPortionEstimate? = nil
    var portionUnit: String? = nil
    var isProductConfirmed = false
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
    /// 1단위 분량을 모델이 추정했는지(#41 2차 B). false면 분량 추정이 실패해 amountPerUnit이 영양 기준량(100)이다.
    var portionEstimated = true

    /// 영양 추정의 1단위 분량을 물을 때 쓰는 임시 자료(100g 또는 100mL 기준). 실제 해석기와 서비스가 같은 값을 쓴다.
    static func portionReference(name: String, amountUnit: String, nutrition: NutritionValues) -> FoodCatalogItem {
        FoodCatalogItem(id: "portion-reference", name: name, servingUnit: "회",
            servingGrams: amountUnit == "g" ? 100 : 0, nutrition: nutrition,
            servingMilliliters: amountUnit == "mL" ? 100 : 0, category: "조리 음식")
    }

    /// 영양 추정에 쓰지 않는 표기(#41 2차 A). 모델이 재료를 영어로 돌려주면(예: 포케 → fish, sliced fish) 화면·저장 출처에 내보내지 않는다.
    var displayIngredients: String? {
        let text = ingredients.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }) else { return nil }
        return text
    }

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

    /// 인분·접시·그릇 한 단위의 상한(g 또는 mL). 이 값 미만만 허용한다(1,000g 자체도 거부).
    static let servingUpperBound = 1000.0

    /// AI가 추정한 1단위(개·잔·병·인분 등) 분량의 상한(#41). 포장 총중량 상한(AIMealEntryService.packageAmountLimit)과 같은 값이다.
    /// 실기기에서 초코우유 1개를 1,500mL로 추정해 0.5개가 약 533kcal로 계산됐다. 이 값 이상이면 추정 실패로 본다.
    static let unitUpperBound = 1500.0

    func isPlausible(for unit: String, foodName: String = "") -> Bool {
        guard amountPerUnit.isFinite, (0.1...5000).contains(amountPerUnit) else { return false }
        if !["g", "mL"].contains(unit), amountPerUnit >= Self.unitUpperBound { return false }
        if DrinkReferenceCatalog.recognizes(foodName) {
            guard amountUnit == "mL" else { return false }
            if unit == "mL" { return true }
            return DrinkReferenceCatalog.plausibleRange(for: unit)?.contains(amountPerUnit) ?? false
        }
        let name = foodName.filter { !$0.isWhitespace }
        if ["개", "조각"].contains(unit), ["너겟", "너깃", "너켓"].contains(where: name.hasSuffix) {
            return amountUnit == "g" && (1...60).contains(amountPerUnit)
        }
        let bowlMeals = ["국밥", "덮밥", "비빔밥", "볶음밥", "짜장면", "자장면", "짬뽕", "냉면", "칼국수", "우동", "스파게티", "파스타"]
        if ["인분", "그릇", "접시", "공기"].contains(unit), bowlMeals.contains(where: name.hasSuffix) {
            return unit == "공기" ? (200...2000).contains(amountPerUnit) : (200..<Self.servingUpperBound).contains(amountPerUnit)
        }
        switch unit {
        case "국자":
            return (10...250).contains(amountPerUnit)
        case "종지":
            return (5...100).contains(amountPerUnit)
        case "숟가락", "큰술":
            return (1...50).contains(amountPerUnit)
        case "작은술":
            return (0.5...20).contains(amountPerUnit)
        case "그릇", "접시":
            return (20..<Self.servingUpperBound).contains(amountPerUnit)
        case "인분":
            return (5..<Self.servingUpperBound).contains(amountPerUnit)
        case "공기", "컵", "잔":
            return amountPerUnit >= 20
        case "줄", "봉", "팩":
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

    /// DEBUG 기록의 오류 줄에 남길 단계(#41 작업 K). 모델 호출과 DB 검색·기록 계산 직전에 바꾼다.
    private var stage = "시작"

    private func model(_ stage: String) -> any MealFoodInterpreting {
        self.stage = stage
        return interpreter
    }

    func analyze(_ text: String) async throws -> MealEntryAnalysis {
        MealDebugLog.log("원문: \(text)")
        stage = "원문 해석"
        do {
            let result = try await MealPerformance.measure("analyze") { try await analyzeMeal(text) }
            #if DEBUG
            MealDebugLog.log(MealDebugLog.describe(result))
            #endif
            return result
        } catch {
            MealDebugLog.log("오류: \(stage) \(error)")
            throw error
        }
    }

    private func analyzeMeal(_ text: String) async throws -> MealEntryAnalysis {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MealEntryError.invalidResult }
        guard text.count <= 500 else { throw MealEntryError.inputTooLong }
        if let corrected = MealFoodNames.ramenCorrection(in: text) {
            return .question(MealEntryQuestion(
                title: "‘\(corrected)’을 말씀하셨나요?",
                explanation: "비슷한 이름의 음식을 찾았어요. 맞으면 선택해주세요",
                choices: [MealEntryChoice(id: UUID().uuidString, title: corrected, items: [], correctedText: corrected)]
            ))
        }
        // 정식·세트는 구성을 글로 적어 달라고 묻지 않고(선택지 0개 질문 없음, #41) 이름 하나의 음식으로 처리한다.
        // 구성은 임의로 추가하지 않는다. DB에 없으면 모델 영양 추정으로 기록된다.
        if let name = MealInputGrounding.setMenuName(in: text) {
            let input = MealFoodInput(name: name, sourceText: text, quantity: 1, unit: "인분", brand: "")
            return try await resolve([input], items: [])
        }
        // 쉼표로 나뉜 한 줄은 모델에 보내기 전에 앱이 나눠 각각 처리한다(2026-11-23, #39). 실기기에서
        // "와인 한잔, 김치찌게 1인분"을 모델이 김치찌개 하나로만 돌려줘 와인이 빠졌다. 이름만 쉼표로 늘어놓은 줄은
        // 지금처럼 catalogFoodList가 먼저 처리한다. "와·랑·하고"로 이어진 줄은 모델에 맡긴다.
        let pieces = Self.commaSeparatedPieces(text)
        if pieces.count >= 2, try await catalogFoodList(in: text) == nil {
            guard pieces.count <= 8 else { throw MealEntryError.inputTooLong }
            var inputs: [MealFoodInput] = []
            for piece in pieces {
                inputs += try await foodInputs(in: piece)
            }
            guard inputs.count <= 8 else { throw MealEntryError.inputTooLong }
            return try await resolve(inputs, items: [])
        }
        return try await resolve(try await foodInputs(in: text), items: [])
    }

    /// 입력 전체가 참고표(FoodReferences.json)·술 표(DrinkReferences.json)의 이름·별칭 하나와 정확히 같으면 그 음식(양 없음).
    /// 끝의 "먹었어"·문장부호는 뗀다. 맞춤법 변형(SpellingVariants.json)은 이름 비교에서 맞춘다.
    static func knownDataName(in text: String) -> MealFoodInput? {
        let name = text.replacingOccurrences(of: #"\s*(?:먹었어요|먹었어|마셨어요|마셨어)?[.!]*\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, name.allSatisfy({ $0.isLetter || $0.isWhitespace }),
              FoodReferenceCatalog.entry(for: name) != nil || DrinkReferenceCatalog.recognizes(name) else { return nil }
        return MealFoodInput(name: name, sourceText: text, quantity: 1, unit: "인분", brand: "")
    }

    /// 원문 전체를 음식 하나로 볼 때의 입력(#41). 양 표현이 있으면 그 앞까지, 없으면 끝의 "먹었어"·문장부호를 뗀 원문.
    static func wholeTextFood(_ text: String) -> MealFoodInput {
        if let single = MealInputGrounding.singleFoodWithAmount(in: text) { return single }
        let name = text.replacingOccurrences(of: #"\s*(?:먹었어요|먹었어|마셨어요|마셨어)?[.!]*\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return MealFoodInput(name: name.isEmpty ? text : name, sourceText: text, quantity: 1, unit: "인분", brand: "")
    }

    /// 쉼표로 나눈 조각. 숫자 사이의 쉼표(1,000g)는 나누지 않는다. 빈 조각은 버린다.
    static func commaSeparatedPieces(_ text: String) -> [String] {
        let marked = text.replacingOccurrences(of: #"(?<!\d),|,(?!\d)"#, with: "\u{1F}", options: .regularExpression)
        return marked.split(separator: "\u{1F}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// 한 줄(또는 쉼표로 나눈 한 조각)에서 음식 입력을 뽑아 원문에 맞춰 검증한다.
    private func foodInputs(in text: String) async throws -> [MealFoodInput] {
        let generated: [MealFoodInput]
        var usesModel = false
        if let singleFood = MealInputGrounding.singlePreparedReference(in: text) {
            generated = singleFood
        } else if let singleFood = MealInputGrounding.singleFoodWithAmount(in: text),
                  try await isKnownSingleFood(singleFood) {
            generated = [singleFood]
        } else if let known = Self.knownDataName(in: text) {
            // 참고표·술 표의 이름·별칭과 정확히 같은 입력은 모델 추출 없이 처리한다(2026-11-24, #41).
            // 양을 적은 입력("아메리카노 한잔")은 위 singleFoodWithAmount가 같은 방식으로 처리한다.
            MealDebugLog.log("데이터 이름과 일치: 모델 음식 추출 없이 '\(known.name)'")
            generated = [known]
        } else if let listedFoods = try await catalogFoodList(in: text) {
            generated = listedFoods
        } else if let singleFood = MealFoodNames.singleRelatedRamen(in: text) {
            generated = singleFood
        } else {
            usesModel = true
            do {
                generated = try await model("음식 추출").foods(in: MealFoodNames.extractionText(text))
            } catch MealEntryError.generationFailed {
                // 음식 추출 단계가 실패하면 원문을 음식 하나로 보고 DB 검색부터 계속한다(#41, 작업 G).
                MealDebugLog.log("오류 대신 계속: 음식 추출 단계 generationFailed → 원문을 음식 하나로 처리: \(text)")
                generated = [Self.wholeTextFood(text)]
            }
        }
        try Task.checkCancellation()
        var inputs: [MealFoodInput]
        do {
            inputs = try MealInputGrounding.ground(generated, in: text)
        } catch MealEntryError.invalidResult where usesModel && !generated.isEmpty {
            // 모델이 뽑은 이름이 모두 원문에 없으면 원문을 음식 하나로 보고 계속한다(#41). 오류를 내지 않는다.
            MealDebugLog.log("모델 음식 추출이 원문과 맞지 않음 → 원문을 음식 하나로 처리: \(text)")
            inputs = try MealInputGrounding.ground([Self.wholeTextFood(text)], in: text)
        }
        if usesModel {
            inputs = try await supplementedInputs(inputs, in: text)
        }
        for input in inputs {
            guard input.isValid, !input.sourceText.isEmpty,
                  text.contains(input.sourceText),
                  normalized(input.sourceText).contains(normalized(input.name)),
                  input.brand.isEmpty || normalized(input.sourceText).contains(normalized(input.brand))
            else { throw MealEntryError.invalidResult }
        }
        return inputs
    }

    /// 모델이 빠뜨린 음식을 원문 단어에서 보충한다(2026-11-24, #41 작업 J). 실기기에서 "오늘 점심에 친구랑 김치찌기 먹고
    /// 아메리카노 마셨어"의 모델 추출이 "김치찌기" 하나뿐이었다. 원문을 단어로 나누고 끝의 조사·어미(MealTextParticles.json)를
    /// 뗀 단어가 참고표·술 표 이름·별칭이나 DB 일반 음식(브랜드 없는 "음식" 분류) 이름과 정확히 맞고(맞춤법 변형 적용),
    /// 이미 뽑힌 음식의 원문 범위와 겹치지 않으면 음식으로 더한다. 음식 이름은 코드에 넣지 않는다.
    private func supplementedInputs(_ inputs: [MealFoodInput], in text: String) async throws -> [MealFoodInput] {
        let covered = inputs.compactMap { MealFoodNames.range(of: $0.name, in: text) }
        var extra: [(input: MealFoodInput, position: String.Index)] = []
        for (word, range) in MealTextParticles.words(in: text) where !MealTextParticles.isStandalone(word) {
            guard !covered.contains(where: { $0.overlaps(range) }) else { continue }
            for candidate in [word, MealTextParticles.stripped(word)].compactMap({ $0 }) where candidate.count >= 2 {
                let key = normalized(candidate)
                guard !inputs.contains(where: { normalized($0.name) == key }),
                      !extra.contains(where: { normalized($0.input.name) == key }) else { break }
                guard try await isSupplementName(candidate) else { continue }
                extra.append((MealFoodInput(name: candidate, sourceText: text, quantity: 1, unit: "인분", brand: ""), range.lowerBound))
                break
            }
        }
        guard !extra.isEmpty else { return inputs }
        let merged = (inputs.map { ($0, MealFoodNames.range(of: $0.name, in: text)?.lowerBound ?? text.endIndex) } + extra)
            .sorted { $0.1 < $1.1 }.map(\.0)
        guard merged.count <= 8 else { return inputs }
        MealDebugLog.log("모델이 빠뜨린 음식 보충: " + extra.map(\.input.name).joined(separator: ", "))
        return try MealInputGrounding.ground(merged, in: text)
    }

    private func isSupplementName(_ name: String) async throws -> Bool {
        if FoodReferenceCatalog.entry(for: name) != nil || DrinkReferenceCatalog.recognizes(name) { return true }
        let matches = try await catalog.search(query: name)
        try Task.checkCancellation()
        return matches.contains { food in
            food.brand.isEmpty && food.category == "음식" && FoodCatalogQuality.isUsable(food) && normalized(food.name) == normalized(name)
        }
    }

    private func catalogFoodList(in text: String) async throws -> [MealFoodInput]? {
        let names = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard (2...8).contains(names.count), names.allSatisfy({
            !$0.isEmpty && $0.count <= 60 && $0.allSatisfy { $0.isLetter || $0.isWhitespace }
        }) else { return nil }
        var inputs: [MealFoodInput] = []
        for name in names {
            try Task.checkCancellation()
            let isReference = FoodReferenceCatalog.entry(for: name) != nil
                || PreparedFoodReference.entry(for: name) != nil
                || !PackagedFoodCatalog.candidates(name: name, brand: "").isEmpty
            if !isReference {
                let matches = try await catalog.search(query: name)
                guard matches.contains(where: { normalized($0.name) == normalized(name) }) else { return nil }
            }
            inputs.append(MealFoodInput(name: name, sourceText: name, quantity: 1, unit: "인분", brand: ""))
        }
        return inputs
    }

    private func isKnownSingleFood(_ input: MealFoodInput) async throws -> Bool {
        if FoodReferenceCatalog.entry(for: input.name) != nil || PreparedFoodReference.entry(for: input.name) != nil
            || DrinkReferenceCatalog.recognizes(input.name) {
            return true
        }
        let matches = try await catalog.search(query: input.name)
        try Task.checkCancellation()
        // 수식어를 뗀 이름(냉동만두 → 만두)이 알려진 음식이어도 한 음식으로 본다. 기록 전에 비슷한 음식 확인을 거친다.
        let names = [input.name] + (FoodModifierCatalog.stripped(input.name).map { [$0.base] } ?? [])
        return matches.contains { food in FoodCatalogQuality.isUsable(food) && names.contains { normalized(food.name) == normalized($0) } }
            || names.dropFirst().contains { FoodReferenceCatalog.entry(for: $0) != nil }
    }

    func resolve(_ choice: MealEntryChoice) async throws -> MealEntryAnalysis {
        MealDebugLog.log("선택: \(choice.title)\(choice.subtitle.map { " (\($0))" } ?? "")\(choice.continuationInput.map { $0.details.isEmpty ? "" : " 입력 \($0.details)" } ?? "")")
        stage = "선택 처리"
        do {
            let result = try await MealPerformance.measure("clarify") { try await resolveChoice(choice) }
            #if DEBUG
            MealDebugLog.log(MealDebugLog.describe(result))
            #endif
            return result
        } catch {
            MealDebugLog.log("오류: \(stage) \(error)")
            throw error
        }
    }

    private func resolveChoice(_ choice: MealEntryChoice) async throws -> MealEntryAnalysis {
        try Task.checkCancellation()
        if choice.requiresPackageCount, let selection = choice.selection,
           let answer = choice.continuationInput?.details {
            let pattern = #"^\s*(\d+(?:\.\d+)?)\s*(?:개|컵|봉|팩)?\s*$"#
            let expression = try NSRegularExpression(pattern: pattern)
            guard let match = expression.firstMatch(in: answer, range: NSRange(answer.startIndex..., in: answer)),
                  let range = Range(match.range(at: 1), in: answer), let count = Double(answer[range]),
                  count.isFinite, (0.1...100).contains(count) else {
                return packageCountQuestion(selection, items: choice.items, remaining: choice.remainingFoods)
            }
            let input = MealFoodInput(name: selection.input.name, sourceText: "\(selection.input.name) \(count)개",
                quantity: count, unit: "개", brand: selection.input.brand)
            return try await resolveSelection(MealFoodSelection(input: input, food: selection.food,
                isProductConfirmed: selection.isProductConfirmed), items: choice.items, remaining: choice.remainingFoods)
        }
        if let corrected = choice.correctedText {
            return try await analyzeMeal(corrected)
        }
        if let input = choice.estimateInput {
            return try await estimatedChoice(input, items: choice.items, remaining: choice.remainingFoods)
        }
        if let original = choice.portionInput,
           let answer = choice.continuationInput?.details {
            let defaultUnit = householdUnit(for: original, food: choice.selection?.food)
            guard let amount = MealInputGrounding.portionAnswer(answer, defaultUnit: defaultUnit) else {
                return amountQuestion(original, selection: choice.selection, items: choice.items, remaining: choice.remainingFoods, invalid: true,
                    estimate: choice.estimate)
            }
            let input = MealFoodInput(
                name: original.name, sourceText: "\(original.name) \(amount.quantity)\(amount.unit)",
                quantity: amount.quantity, unit: amount.unit, brand: original.brand, details: original.details,
                isSideDish: original.isSideDish, hasConfirmedPortion: true
            )
            if let selection = choice.selection {
                let keepsOverride = amount.unit == selection.portionUnit
                return try await resolveSelection(MealFoodSelection(input: input, food: selection.food, isSimilar: selection.isSimilar,
                    portionOverride: keepsOverride ? selection.portionOverride : nil, portionUnit: keepsOverride ? selection.portionUnit : nil,
                    isProductConfirmed: selection.isProductConfirmed),
                    items: choice.items, remaining: choice.remainingFoods)
            }
            if let estimate = choice.estimate {
                return try await reusedEstimate(input, estimate: estimate, items: choice.items, remaining: choice.remainingFoods)
            }
            return try await resolve([input] + choice.remainingFoods, items: choice.items)
        }
        if let input = choice.continuationInput {
            guard input.isValid, !input.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MealEntryError.invalidResult
            }
            if MealInputGrounding.setMenuName(in: input.name) != nil {
                return try await analyzeMeal(input.details)
            }
            if isUnspecified(input.name) {
                let generated = try await model("음식 추출").foods(in: MealFoodNames.extractionText(input.details))
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
        return try await resolveSelection(selection, items: choice.items, remaining: choice.remainingFoods)
    }

    private func resolveSelection(_ selection: MealFoodSelection, items: [MealEntryItem], remaining: [MealFoodInput]) async throws -> MealEntryAnalysis {
        let selection = selectionWithAssumedPackageUnit(selection)
        guard FoodCatalogQuality.isUsable(selection.food) else { throw MealEntryError.foodNotFound(selection.input.name) }
        if let product = PackagedFoodCatalog.replacement(for: selection.food) {
            return packagedQuestion([product], input: selection.input, items: items, remaining: remaining)
        }
        if selection.food.category == "가공식품", !selection.isProductConfirmed {
            return try await productQuestion([selection.food], input: selection.input, items: items, remaining: remaining)
        }
        if selection.portionOverride == nil, !["g", "mL"].contains(selection.input.unit),
           let fallback = suggestedPortion(selection) {
            var confirmed = selection
            confirmed.portionOverride = fallback.estimate
            confirmed.portionUnit = fallback.unit
            return .question(MealEntryQuestion(
                title: "\(fallback.unit) 단위로 기록할까요?",
                explanation: fallback.explanation + " 기록 전 수량을 조절할 수 있어요",
                choices: [MealEntryChoice(id: UUID().uuidString, title: "이 기준으로 계산", items: items,
                    selection: confirmed, remainingFoods: remaining)]
            ))
        }
        var item: MealEntryItem
        do {
            stage = "기록 계산"
            item = try await makeItem(selection)
            if selection.input.omittedQuantity, item.portionBasis != .entered {
                item.quantityNote = MealEntryItem.assumedQuantityNote(unit: item.food.servingUnit)
            }
        } catch MealEntryError.portionUnknown {
            try Task.checkCancellation()
            if PackagedFoodCatalog.entry(id: selection.food.id) != nil {
                return packageCountQuestion(selection, items: items, remaining: remaining)
            }
            if requiresUnitAmount(selection) {
                return try await estimatedUnitQuestion(selection, items: items, remaining: remaining)
            }
            if selection.input.unit == "국자" {
                if let question = try await recoveredPortionQuestion(selection, items: items, remaining: remaining) {
                    return question
                }
                return try await portionFallback(selection, items: items, remaining: remaining)
            }
            // DB 자료는 있는데 분량만 못 정했을 때(#41): 제품 포장량 → 대표 분량 → 1인분 순서로 기록한다.
            // 수량을 적지 않은 입력도 수량을 묻지 않고 1단위로 가정한다(2026-11-24, #41 2차 B 사용자 결정).
            return try await portionFallback(selection, items: items, remaining: remaining)
        }
        return try await resolve(remaining, items: items + [item])
    }

    private func packagedQuestion(_ products: [PackagedFoodReference], input: MealFoodInput, items: [MealEntryItem], remaining: [MealFoodInput]) -> MealEntryAnalysis {
        .question(MealEntryQuestion(
            title: "이 제품을 드셨나요?",
            explanation: "제품과 용량이 맞으면 선택해주세요",
            choices: products.map { product in
                MealEntryChoice(id: product.id,
                    title: product.name.replacingOccurrences(of: #"\s+\d+(?:\.\d+)?g$"#, with: "", options: .regularExpression),
                    items: items, selection: MealFoodSelection(input: input, food: product.food, isProductConfirmed: true), remainingFoods: remaining,
                    subtitle: "\(product.brand) · 1개 \(product.packageGrams.formatted(.number.precision(.fractionLength(0...1))))g · \(Int(product.calories))kcal")
            }
        ))
    }

    private func productQuestion(_ foods: [FoodCatalogItem], input: MealFoodInput, items: [MealEntryItem], remaining: [MealFoodInput]) async throws -> MealEntryAnalysis {
        // 업체명·브랜드 없는 입력에 이름이 같은 제품이 2개 이상이면 묻지 않고 가운데 제품을 쓴다(2026-11-24, #41 사용자 결정).
        // 실기기에서 아이스티처럼 선택지 이름이 모두 같아 방문자가 구분할 수 없었다. 분량을 정하는 방식은 그대로다.
        if input.brand.isEmpty, let median = Self.medianSameNameProduct(foods, name: searchName(foodName(of: input))) {
            var food = median.food
            food.source = "\(food.source) · \([food.brand, food.name].filter { !$0.isEmpty }.joined(separator: " ")) 영양값 기준"
            MealDebugLog.log("같은 이름 제품 \(median.count)개 → 묻지 않고 가운데 제품: \(food.id) \(food.name) · \(food.brand)")
            return try await resolveSelection(MealFoodSelection(input: input, food: food, isProductConfirmed: true),
                items: items, remaining: remaining)
        }
        var seen = Set<String>()
        let choices = foods.compactMap { candidate -> MealEntryChoice? in
            let product = PackagedFoodCatalog.entry(id: candidate.id) ?? PackagedFoodCatalog.replacement(for: candidate)
            let food = product?.food ?? candidate
            guard seen.insert(food.id).inserted else { return nil }
            let subtitle = [food.brand, productBasis(food, isReference: product != nil, unit: input.unit)]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            return MealEntryChoice(id: food.id, title: food.name, items: items,
                selection: MealFoodSelection(input: input, food: food, isProductConfirmed: true),
                remainingFoods: remaining, subtitle: subtitle)
        }
        return .question(MealEntryQuestion(
            title: "이 제품을 드셨나요?",
            explanation: "포장제품 후보예요. 먹은 제품과 같을 때만 선택해주세요. 없다면 음식 이름이나 브랜드를 수정해주세요",
            choices: Array(choices.prefix(4))
        ))
    }

    /// 이름이 입력과 같은 가공식품이 2개 이상일 때의 가운데 제품(#41). 같은 이름 제품 중 많은 단위(g 또는 mL, 같으면 g) 묶음을
    /// 100g(mL)당 열량으로 정렬해 가운데를 고른다. 짝수면 가운데 둘 중 열량이 낮은 쪽. 같은 열량은 식품코드 순.
    /// 포장제품 표(PackagedFoodReferences.json) 항목은 이미 확인된 제품이라 이 규칙에서 뺀다.
    static func medianSameNameProduct(_ foods: [FoodCatalogItem], name: String) -> (food: FoodCatalogItem, count: Int)? {
        let key = FoodReferenceCatalog.normalized(name)
        return medianProduct(foods) { FoodReferenceCatalog.normalized($0.name) == key }
    }

    /// 이름이 입력으로 시작하는 한 업체의 제품 묶음의 가운데 제품(#41 2차 E). 조건:
    /// - 가공식품이고 정규화한 이름이 입력 이름으로 시작하며 더 길다(같은 이름 제품은 medianSameNameProduct 몫).
    /// - 입력 이름 바로 뒤가 띄어쓰기로 나뉜 다른 단어면 뺀다(예: "진라면 볶음밥"은 다른 음식, "진라면(순한맛)"은 같은 제품군).
    /// - 2개 이상이고 업체 표기("(주)", "주식회사" 등 법인 표기·띄어쓰기를 뗀 이름)가 모두 같다.
    static func productLine(_ foods: [FoodCatalogItem], name: String) -> (food: FoodCatalogItem, count: Int)? {
        let key = FoodReferenceCatalog.normalized(name)
        guard key.count >= 2 else { return nil }
        let line = foods.filter { food in
            guard food.category == "가공식품", !food.brand.isEmpty else { return false }
            let compact = FoodReferenceCatalog.normalized(food.name)
            guard compact.hasPrefix(key), compact != key else { return false }
            var joined = ""
            let words = food.name.split(whereSeparator: \.isWhitespace)
            for (index, word) in words.enumerated() {
                joined += FoodReferenceCatalog.normalized(String(word))
                if joined.count >= key.count { return !(joined.count == key.count && index < words.count - 1) }
            }
            return false
        }
        let brands = Set(line.map { companyKey($0.brand) })
        guard brands.count == 1, brands.first?.isEmpty == false else { return nil }
        return medianProduct(line) { _ in true }
    }

    /// 업체 표기 비교용 키: 법인 표기와 띄어쓰기·기호를 뗀다(예: "오뚜기라면(주)" = "오뚜기라면 주식회사").
    static func companyKey(_ brand: String) -> String {
        var text = brand
        for mark in ["주식회사", "유한회사", "(주)", "㈜", "(유)", "농업회사법인", "영농조합법인"] {
            text = text.replacingOccurrences(of: mark, with: "")
        }
        return FoodReferenceCatalog.normalized(text)
    }

    /// 제품 묶음의 가운데 제품: 많은 단위(g 또는 mL, 같으면 g) 묶음을 100당 열량으로 정렬해 가운데. 짝수면 낮은 쪽, 같은 열량은 식품코드 순.
    /// 포장제품 표(PackagedFoodReferences.json) 항목은 이미 확인된 제품이라 뺀다.
    private static func medianProduct(_ foods: [FoodCatalogItem], where matches: (FoodCatalogItem) -> Bool) -> (food: FoodCatalogItem, count: Int)? {
        var seen = Set<String>()
        let same = foods.filter { food in
            food.category == "가공식품" && PackagedFoodCatalog.entry(id: food.id) == nil
                && matches(food) && food.baseAmount > 0 && seen.insert(food.id).inserted
        }
        guard same.count >= 2 else { return nil }
        let grams = same.filter { $0.amountUnit == "g" }, milliliters = same.filter { $0.amountUnit == "mL" }
        let group = (milliliters.count > grams.count ? milliliters : grams)
            .sorted { left, right in
                let a = left.nutrition.calories / left.baseAmount, b = right.nutrition.calories / right.baseAmount
                return a == b ? left.id < right.id : a < b
            }
        guard !group.isEmpty else { return nil }
        return (group[(group.count - 1) / 2], same.count)
    }

    /// 후보 카드의 분량 표시. 제품 총중량을 알면 "1개 120g · 약 500kcal", 모르면 영양 기준량.
    private func productBasis(_ food: FoodCatalogItem, isReference: Bool, unit: String) -> String {
        func number(_ value: Double, digits: Int) -> String { value.formatted(.number.precision(.fractionLength(0...digits))) }
        if isReference {
            return "1개 \(number(food.baseAmount, digits: 1))g · \(number(food.nutrition.calories, digits: 0))kcal"
        }
        if Self.usesPackageAmount(food) {
            let packageUnit = Self.packageUnits.contains(unit) ? unit : "개"
            let calories = food.nutrition.calories * food.packageAmount / food.baseAmount
            return "1\(packageUnit) \(number(food.packageAmount, digits: 1))\(food.amountUnit) · 약 \(number(calories, digits: 0))kcal"
        }
        return "\(number(food.baseAmount, digits: 1))\(food.amountUnit) 기준 · \(number(food.nutrition.calories, digits: 0))kcal"
    }

    private func prefersProducts(_ input: MealFoodInput) -> Bool {
        if !input.brand.isEmpty || ["봉", "팩"].contains(input.unit) { return true }
        if PackagedFoodCatalog.candidates(name: input.name, brand: input.brand)
            .contains(where: { $0.isExplicitProduct(name: input.name, brand: input.brand) }) { return true }
        return input.sourceText.range(of: #"컵라면|봉지라면|(?:냉동|레토르트|즉석)\s*(?:제품|식품)|포장\s*제품"#,
            options: .regularExpression) != nil
    }

    private func packageCountQuestion(_ selection: MealFoodSelection, items: [MealEntryItem], remaining: [MealFoodInput]) -> MealEntryAnalysis {
        func choice(_ count: String) -> MealEntryChoice {
            var answer = selection.input
            answer.details = count
            return MealEntryChoice(id: UUID().uuidString, title: "\(count)개", items: items, selection: selection,
                remainingFoods: remaining, continuationInput: answer, requiresPackageCount: true)
        }
        // 선택지 없이 글로만 답하는 질문은 내지 않는다(#41).
        return .question(MealEntryQuestion(
            title: "제품을 몇 개 드셨나요?",
            explanation: "조리 후 무게 대신 포장 개수로 골라주세요",
            choices: ["1", "0.5", "1.5", "2"].map(choice),
            clarification: MealEntryChoice(id: UUID().uuidString, title: "확인", items: items, selection: selection,
                remainingFoods: remaining, continuationInput: selection.input, requiresPackageCount: true),
            inputPlaceholder: "예: 1개, 0.5개"
        ))
    }

    /// 포장 단위 중량을 모르는 가공식품. 검증된 제공량이 DB에 없다.
    private func requiresUnitAmount(_ selection: MealFoodSelection) -> Bool {
        selection.food.category == "가공식품" && !["g", "mL"].contains(selection.input.unit)
            && selection.portionOverride == nil && !isOversizedPackage(selection.food)
    }

    /// 방문자에게 무게(g·mL)를 묻지 않는다(#39). 모델이 1단위 분량을 추정하고, 그 기준으로 먹은 수량을 고르게 한다.
    /// 추정이 안 되거나 그럴듯하지 않으면 분량을 알 수 없다고 알린다.
    private func estimatedUnitQuestion(_ selection: MealFoodSelection, items: [MealEntryItem], remaining: [MealFoodInput]) async throws -> MealEntryAnalysis {
        let unit = selection.input.unit == "소량" ? "개" : selection.input.unit
        let single = MealFoodInput(name: selection.input.name, sourceText: selection.input.sourceText,
            quantity: 1, unit: unit, brand: selection.input.brand, details: selection.input.details)
        let estimate: MealPortionEstimate
        do {
            estimate = try await model("분량 추정").portion(for: single, food: selection.food)
        } catch let error as MealEntryError {
            guard case .portionUnknown = error else {
                MealDebugLog.log("오류 대신 대체 분량: 분량 추정 단계 \(error)")
                return try await portionFallback(selection, items: items, remaining: remaining)
            }
            MealDebugLog.log("1\(unit) 분량 추정 실패: \(selection.food.id) \(selection.food.name) → 대체 분량")
            return try await portionFallback(selection, items: items, remaining: remaining)
        }
        try Task.checkCancellation()
        guard estimate.amountUnit == selection.food.amountUnit,
              estimate.isPlausible(for: unit, foodName: selection.input.name) else {
            MealDebugLog.log("1\(unit) 분량 추정값 사용 안 함: \(estimate.amountPerUnit)\(estimate.amountUnit), 자료 \(selection.food.amountUnit) → 대체 분량")
            return try await portionFallback(selection, items: items, remaining: remaining)
        }
        return try await unitPortionChoice(selection, estimate: estimate, unit: unit,
            explanation: "제품 1\(unit) 중량 정보가 없어 AI가 1\(unit)을 약 \(Self.amountText(estimate.amountPerUnit))\(estimate.amountUnit)으로 추정했어요.",
            items: items, remaining: remaining)
    }

    private static func amountText(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }

    /// 분량 정보가 없어 영양 기준량(100g·mL)을 1단위로 기록했다는 안내(#41 2차 B). 수량도 없었으면 그 가정도 함께 적는다.
    static func baseAmountNote(base: Double, unit: String, assumedQuantity: Bool, servingUnit: String = "인분") -> String {
        let note = "분량 정보가 없어 1\(servingUnit) 분량을 영양 기준량(\(amountText(base))\(unit))으로 계산했어요"
        return assumedQuantity ? MealEntryItem.assumedQuantityNote(unit: servingUnit) + ". " + note : note
    }

    /// 1단위 분량을 정한 뒤의 기록(#41). 원문에 수량이 있으면("1인분", "반", "두 개") 그 수량으로 바로 기록한다.
    /// 수량이 없으면 묻지 않고 1단위로 가정해 기록하고 "수량이 없어서 1{단위}로 가정했어요"를 붙인다(2026-11-24, #41 2차 B 사용자 결정).
    /// 방문자에게 무게는 묻지 않는다.
    private func unitPortionChoice(_ selection: MealFoodSelection, estimate: MealPortionEstimate, unit: String, explanation: String,
                                   items: [MealEntryItem], remaining: [MealFoodInput]) async throws -> MealEntryAnalysis {
        let assumed = selection.input.omittedQuantity && !selection.input.hasConfirmedPortion
        let input = MealFoodInput(name: selection.input.name, sourceText: selection.input.sourceText,
            quantity: assumed ? 1 : selection.input.quantity, unit: unit, brand: selection.input.brand, details: selection.input.details,
            isSideDish: selection.input.isSideDish, hasConfirmedPortion: true, omittedQuantity: assumed)
        MealDebugLog.log("\(assumed ? "수량 없음 → 질문 없이 1\(unit)로 가정" : "원문 수량 \(Self.amountText(input.quantity))\(unit) → 수량 질문 없이"), "
            + "1\(unit) \(Self.amountText(estimate.amountPerUnit))\(estimate.amountUnit)로 기록: \(explanation)")
        return try await resolveSelection(MealFoodSelection(input: input, food: selection.food, isSimilar: selection.isSimilar,
            portionOverride: estimate, portionUnit: unit, isProductConfirmed: selection.isProductConfirmed),
            items: items, remaining: remaining)
    }

    /// DB 자료는 있는데 분량 추정이 실패했을 때의 대체 흐름(#41, 작업 H). 오류 대신 아래 순서로 기록한다. 무게는 묻지 않는다.
    /// 1. 제품 포장량(총중량·총열량이 상한 미만, usesPackageAmount) 2. 대표 분량(같은 음식 또는 같은 이름의 대표 분량표)
    /// 3. 1인분 선택 질문: 분량 정보가 없어 DB 영양 기준량(100g 또는 100mL)을 1인분으로 계산한다고 알리고 0.5·1·1.5인분을 고르게 한다.
    private func portionFallback(_ selection: MealFoodSelection, items: [MealEntryItem], remaining: [MealFoodInput]) async throws -> MealEntryAnalysis {
        let food = selection.food
        let unit = selection.input.unit == "소량" ? "개" : selection.input.unit
        let name = selection.input.name
        // 각 대체 분량은 makeItem의 분량 검사(isPlausible)를 통과할 때만 쓴다. 통과하지 못하는 값을 쓰면 같은 대체 흐름이 되풀이된다.
        // 포장 총중량 규칙(usesPackageAmount: 총중량·총열량 상한 미만)을 넘는 대용량 포장은 1단위로 쓰지 않는다(#41 2차).
        // 300개 점검에서 수량 없는 "초코케이크"가 700g 2,450kcal 제품 1개로 기록됐다.
        if Self.usesPackageAmount(food), !["g", "mL"].contains(unit),
           MealPortionEstimate(amountPerUnit: food.packageAmount, amountUnit: food.amountUnit).isPlausible(for: unit, foodName: name) {
            let estimate = MealPortionEstimate(amountPerUnit: food.packageAmount, amountUnit: food.amountUnit)
            MealDebugLog.log("대체 분량: 제품 포장량 \(Self.amountText(food.packageAmount))\(food.amountUnit)를 1\(unit)으로")
            return try await unitPortionChoice(selection, estimate: estimate, unit: unit,
                explanation: "제품 포장량(\(Self.amountText(food.packageAmount))\(food.amountUnit))을 1\(unit)으로 계산해요.",
                items: items, remaining: remaining)
        }
        // 대표 분량: g 자료, 또는 국물·면 mL 자료(대표 분량 N g을 N mL로 보는 규칙, VolumeAsWeight.json)
        let usesVolumeAsWeight = food.amountUnit == "mL" && food.category != "가공식품" && VolumeAsWeight.rule?.matches(food.name) == true
        if food.amountUnit == "g" || usesVolumeAsWeight,
           let portion = FoodPortion.representative(for: food, allowsVolumeAsWeight: true)
               ?? FoodPortion.tablePortion(forName: name) ?? FoodPortion.tablePortion(forName: food.name),
           MealPortionEstimate(amountPerUnit: portion.grams, amountUnit: food.amountUnit).isPlausible(for: portion.unit, foodName: name) {
            let estimate = MealPortionEstimate(amountPerUnit: portion.grams, amountUnit: food.amountUnit)
            MealDebugLog.log("대체 분량: 대표 분량 1\(portion.unit) \(Self.amountText(portion.grams))\(food.amountUnit)")
            return try await unitPortionChoice(selection, estimate: estimate, unit: portion.unit,
                explanation: "대표 분량(1\(portion.unit) 약 \(Self.amountText(portion.grams))\(food.amountUnit))으로 계산해요.",
                items: items, remaining: remaining)
        }
        // 3. 1인분 선택 질문. AI 추정값이 아니라 DB 영양 기준량을 그대로 쓰는 것이라 분량 검사(isPlausible) 대신
        //    고른 인분만큼의 기준량(g·mL)으로 기록한다. 방문자는 인분만 고른다.
        let base = food.baseAmount
        guard base > 0 else {
            MealDebugLog.log("오류: 분량 추정 대체 분량 없음(영양 기준량 없음) \(food.id)")
            throw MealEntryError.portionUnknown(selection.input.name)
        }
        if selection.input.omittedQuantity, !selection.input.hasConfirmedPortion {
            // 수량도 분량 정보도 없으면 묻지 않고 영양 기준량을 1인분으로 기록한다(#41 2차 B).
            MealDebugLog.log("대체 분량: 수량 없음 → 질문 없이 영양 기준량 \(Self.amountText(base))\(food.amountUnit)를 1인분으로 기록")
            let input = MealFoodInput(name: selection.input.name, sourceText: selection.input.sourceText,
                quantity: base, unit: food.amountUnit, brand: selection.input.brand, details: selection.input.details,
                isSideDish: selection.input.isSideDish, hasConfirmedPortion: true)
            stage = "기록 계산"
            var item = try await makeItem(MealFoodSelection(input: input, food: food, isSimilar: selection.isSimilar,
                isProductConfirmed: selection.isProductConfirmed))
            item.quantityNote = Self.baseAmountNote(base: base, unit: food.amountUnit, assumedQuantity: true)
            return try await resolve(remaining, items: items + [item])
        }
        MealDebugLog.log("대체 분량: 1인분 선택 질문(영양 기준량 \(Self.amountText(base))\(food.amountUnit))")
        return .question(MealEntryQuestion(
            title: "‘\(selection.input.name)’을 얼마나 드셨나요?",
            explanation: "분량 정보를 찾지 못해 영양 기준량(\(Self.amountText(base))\(food.amountUnit))을 1인분으로 계산해요. 먹은 양을 골라주세요.",
            choices: [1, 0.5, 1.5].map { quantity in
                let input = MealFoodInput(name: selection.input.name, sourceText: selection.input.sourceText,
                    quantity: base * quantity, unit: food.amountUnit, brand: selection.input.brand, details: selection.input.details,
                    isSideDish: selection.input.isSideDish, hasConfirmedPortion: true)
                return MealEntryChoice(id: UUID().uuidString, title: "\(Self.amountText(quantity))인분", items: items,
                    selection: MealFoodSelection(input: input, food: food, isSimilar: selection.isSimilar,
                        isProductConfirmed: selection.isProductConfirmed),
                    remainingFoods: remaining, subtitle: "약 \(Self.amountText(base * quantity))\(food.amountUnit)")
            }
        ))
    }

    private func suggestedPortion(_ selection: MealFoodSelection) -> (estimate: MealPortionEstimate, unit: String, explanation: String)? {
        guard selection.input.brand.isEmpty, selection.food.brand.isEmpty,
              selection.food.amountUnit == "g" else { return nil }
        let name = normalized(selection.input.name)
        if name.hasSuffix("라멘"), ["인분", "그릇"].contains(selection.input.unit) {
            let reference = FoodCatalogItem(id: "portion-reference", name: "우동", servingUnit: "g", servingGrams: 100,
                nutrition: selection.food.nutrition, category: "음식")
            guard let portion = reference.representativePortion else { return nil }
            return (MealPortionEstimate(amountPerUnit: portion.grams, amountUnit: "g"), "그릇",
                "라멘의 확인된 분량이 없어 국물 면요리인 우동의 한 그릇 기준(약 \(Int(portion.grams))g)을 참고해요. 실제 무게와는 다를 수 있어요.")
        }
        if ["치킨너겟", "너겟", "치킨너깃", "너깃", "치킨너켓"].contains(name),
           ["개", "조각"].contains(selection.input.unit) {
            return (MealPortionEstimate(amountPerUnit: 16, amountUnit: "g"), selection.input.unit,
                "비슷한 제품인 맥너겟 4조각 64g을 참고해 한 개 약 16g으로 계산해요. 제품에 따라 크기가 달라요.")
        }
        return nil
    }

    private func householdUnit(for input: MealFoodInput, food: FoodCatalogItem?) -> String {
        if let drink = DrinkReferenceCatalog.entry(for: input.name) {
            return drink.container(for: input.unit)?.unit ?? drink.defaultUnit
        }
        if !["인분", "g", "mL", "소량"].contains(input.unit) { return input.unit }
        if let food, let reference = PreparedFoodReference.entries.first(where: { $0.food.id == food.id }) {
            return reference.food.servingUnit
        }
        if let portion = food?.representativePortion { return portion.unit }
        let name = normalized(input.name)
        if ["밥", "쌀밥", "흰밥", "백미밥", "잡곡밥", "현미밥", "흑미밥", "공기밥"].contains(name) { return "공기" }
        if ["덮밥", "볶음밥", "비빔밥", "카레라이스"].contains(where: name.hasSuffix) { return "그릇" }
        if ["국", "탕", "찌개", "국수", "라멘", "우동"].contains(where: name.hasSuffix) { return "그릇" }
        if ["빵", "만두", "달걀", "너겟", "까스", "가스"].contains(where: name.hasSuffix) { return "개" }
        if ["우유", "주스", "콜라", "커피", "아메리카노"].contains(where: name.hasSuffix) { return "컵" }
        return "인분"
    }

    private func recoveredPortionQuestion(_ selection: MealFoodSelection, items: [MealEntryItem], remaining: [MealFoodInput]) async throws -> MealEntryAnalysis? {
        guard selection.food.category != "가공식품" else { return nil }
        let unit: String
        let estimate: MealPortionEstimate
        let basis: String
        if let portion = selection.food.representativePortion {
            unit = portion.unit
            estimate = MealPortionEstimate(amountPerUnit: portion.grams, amountUnit: "g")
            basis = "대표 분량"
        } else {
            guard selection.input.unit != "인분" else { return nil }
            let serving = MealFoodInput(name: selection.input.name, sourceText: selection.input.sourceText,
                quantity: 1, unit: "인분", brand: selection.input.brand, details: selection.input.details)
            do {
                estimate = try await model("분량 추정").portion(for: serving, food: selection.food)
            } catch MealEntryError.portionUnknown { return nil } catch MealEntryError.generationFailed { return nil }
            try Task.checkCancellation()
            guard estimate.amountUnit == selection.food.amountUnit,
                  estimate.isPlausible(for: "인분", foodName: selection.input.name) else { return nil }
            unit = "인분"
            basis = "일반적인 1인분 추정값"
        }
        return .question(MealEntryQuestion(
            title: "‘\(selection.input.name)’을 \(unit) 기준으로 골라주세요",
            explanation: "입력한 \(selection.input.unit) 분량은 환산하기 어려워요. \(basis)(1\(unit) 약 \(Int(estimate.amountPerUnit))\(estimate.amountUnit))을 참고해 먹은 양을 골라주세요. 국자와 같은 양이라는 뜻은 아니에요.",
            choices: [0.5, 1, 1.5].map { quantity in
                let input = MealFoodInput(name: selection.input.name, sourceText: selection.input.sourceText,
                    quantity: quantity, unit: unit, brand: selection.input.brand, details: selection.input.details,
                    isSideDish: selection.input.isSideDish, hasConfirmedPortion: true)
                return MealEntryChoice(id: UUID().uuidString, title: "\(quantity.formatted(.number.precision(.fractionLength(0...1))))\(unit)",
                    items: items, selection: MealFoodSelection(input: input, food: selection.food, isSimilar: selection.isSimilar,
                        portionOverride: estimate, portionUnit: unit), remainingFoods: remaining)
            }
        ))
    }

    private func amountQuestion(_ input: MealFoodInput, selection: MealFoodSelection? = nil, items: [MealEntryItem], remaining: [MealFoodInput],
                                invalid: Bool = false, estimate: MealNutritionEstimate? = nil) -> MealEntryAnalysis {
        let unit = householdUnit(for: input, food: selection?.food)
        var answers = ["0.5\(unit)", "1\(unit)", "1.5\(unit)"]
        let name = normalized(input.name)
        if let drink = DrinkReferenceCatalog.entry(for: input.name) {
            answers += drink.containers.filter { $0.unit != unit }.prefix(1).map { "1\($0.unit)" }
        } else if unit != "국자", ["갈비", "찜", "불고기", "볶음", "국", "탕", "찌개"].contains(where: name.hasSuffix) {
            answers.append("1국자")
        } else if unit != "인분" {
            answers.append("1인분")
        }
        func choice(_ answer: String, title: String) -> MealEntryChoice {
            var continuation = input
            continuation.details = answer
            return MealEntryChoice(id: UUID().uuidString, title: title, items: items, selection: selection,
                remainingFoods: remaining, continuationInput: continuation, portionInput: input, estimate: estimate)
        }
        return .question(MealEntryQuestion(
            title: "‘\(input.name)’을 얼마나 드셨나요?",
            explanation: invalid ? "반 \(unit), 한 \(unit)처럼 양과 단위를 적어주세요. 숫자만 적으면 \(unit) 기준이에요."
                : "대략적인 양을 선택하거나 적어주세요. 음식과 그릇 크기에 따라 분량은 달라질 수 있어요.",
            choices: answers.map { choice($0, title: $0) },
            clarification: choice("", title: "확인"),
            inputPlaceholder: "ex) 반 \(unit), 한 \(unit)"
        ))
    }

    private func resolve(_ inputs: [MealFoodInput], items: [MealEntryItem]) async throws -> MealEntryAnalysis {
        var items = items
        for (index, original) in inputs.enumerated() {
            try Task.checkCancellation()
            let curryWithoutRice = original.sourceText.range(of: #"밥\s*(?:없이|빼고|제외)|소스만"#, options: .regularExpression) != nil
                || inputs.contains { MealFoodNames.canonical($0.name) == "쌀밥" }
                || items.contains { MealFoodNames.canonical($0.food.name) == "쌀밥" }
            let canonicalName = normalized(original.name) == "카레"
                ? (curryWithoutRice ? "카레소스" : "카레라이스") : MealFoodNames.canonical(original.name)
            let prefersProducts = prefersProducts(original)
            let preparedReference = prefersProducts ? nil
                : PreparedFoodReference.entry(for: canonicalName, brand: original.brand, details: original.details)
            let input = MealFoodInput(
                name: prefersProducts ? original.name : canonicalName,
                sourceText: original.sourceText, quantity: original.quantity,
                unit: original.unit == "인분" ? preparedReference?.food.servingUnit ?? original.unit : original.unit,
                brand: original.brand, details: original.details, isSideDish: original.isSideDish, hasConfirmedPortion: original.hasConfirmedPortion,
                omittedUnit: original.omittedUnit, omittedQuantity: original.omittedQuantity
            )
            let remaining = Array(inputs.dropFirst(index + 1))
            if let drink = DrinkReferenceCatalog.entry(for: input.name) {
                if let analysis = try await resolveDrink(input, drink: drink, items: items, remaining: remaining) {
                    return analysis
                }
            }
            if let reference = preparedReference {
                return try await resolveSelection(MealFoodSelection(input: input, food: reference.food), items: items, remaining: remaining)
            }
            let products = PackagedFoodCatalog.candidates(name: input.name, brand: input.brand)
            if prefersProducts, !products.isEmpty {
                return packagedQuestion(products, input: input, items: items, remaining: remaining)
            }
            if isUnspecified(input.name) {
                return try await estimatedWithoutQuestion(input, estimate: try await model("영양 추정").estimateNutrition(for: input),
                    reason: "무엇인지 정해지지 않은 반찬", items: items, remaining: remaining)
            }
            if !prefersProducts, input.details.isEmpty,
               let reference = FoodReferenceCatalog.entry(for: input.name),
               let food = try await catalog.food(id: reference.referenceID) {
                try Task.checkCancellation()
                if reference.matches(food) {
                    let food = try await preferredReferenceFood(reference, food: food)
                    if candidates(from: [food], input: input).first != nil {
                        return try await resolveSelection(MealFoodSelection(input: input, food: food, isSimilar: normalized(food.name) != normalized(input.name)), items: items, remaining: remaining)
                    }
                }
            }
            // 대표 분량표의 같은 행 이름을 같은 음식의 별칭으로 보고 자료집 지정 자료를 쓴다(2026-11-19 결정).
            // 참고표 지정 다음, 검색 앞. 참고표 이름이거나 브랜드·제품 입력·추가 설명이 있으면 쓰지 않는다.
            if !prefersProducts, input.brand.isEmpty, input.details.isEmpty,
               FoodReferenceCatalog.entry(for: input.name) == nil,
               let alias = GuideRepresentativeCatalog.entry(forName: input.name),
               let food = try await catalog.food(id: alias.foodID) {
                try Task.checkCancellation()
                // 참고표 지정과 같은 방식: 입력 이름과 DB 이름이 다르면 입력 이름으로 보여주고 근거에 DB 자료를 남긴다.
                if candidates(from: [food], input: input).first != nil {
                    return try await resolveSelection(MealFoodSelection(input: input, food: food, isSimilar: normalized(food.name) != normalized(input.name)), items: items, remaining: remaining)
                }
            }
            let foodName = input.brand.isEmpty ? input.name : input.name.replacingOccurrences(of: input.brand, with: "")
            let query = searchName(foodName)
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MealEntryError.invalidResult }
            stage = "DB 검색"
            let results = try await catalog.search(query: [input.brand, query].filter { !$0.isEmpty }.joined(separator: " "))
            try Task.checkCancellation()
            var productMatches = productCandidates(from: results, input: input)
            var compatible = candidates(from: results, input: input)
            var candidates = Array(compatible.prefix(8))

            if prefersProducts, !productMatches.isEmpty {
                return try await productQuestion(productMatches, input: input, items: items, remaining: remaining)
            }

            if normalized(input.name) == "돼지갈비", !prefersProducts {
                let preparations = [("돼지갈비구이", ["돼지갈비구이간장", "갈비구이돼지고기"]), ("돼지갈비찜", ["돼지갈비찜"])]
                let options = preparations.compactMap { title, names -> MealEntryChoice? in
                    guard let food = results.first(where: { $0.category == "음식" && $0.brand.isEmpty && $0.amountUnit == "g"
                        && FoodCatalogQuality.isUsable($0) && names.contains(normalized($0.name)) }) else { return nil }
                    let clarified = MealFoodInput(name: title, sourceText: input.sourceText, quantity: input.quantity,
                        unit: input.unit, brand: "", details: input.details, isSideDish: input.isSideDish,
                        hasConfirmedPortion: input.hasConfirmedPortion)
                    return MealEntryChoice(id: food.id, title: title, items: items,
                        selection: MealFoodSelection(input: clarified, food: food, isSimilar: true), remainingFoods: remaining)
                }
                if !options.isEmpty {
                    return .question(MealEntryQuestion(title: "어떤 돼지갈비를 드셨나요?",
                        explanation: "조리 방법을 골라주세요. 적어주신 양은 그대로 유지해요", choices: options))
                }
            }

            let needsSauce = !prefersProducts && ["스파게티", "파스타"].contains(normalized(input.name)) && input.details.isEmpty
            if !prefersProducts, input.details.isEmpty,
               let reference = FoodReferenceCatalog.entry(for: input.name),
               let referenced = compatible.first(where: reference.matches) {
                let food = try await preferredReferenceFood(reference, food: referenced)
                return try await resolveSelection(MealFoodSelection(input: input, food: food, isSimilar: normalized(food.name) != normalized(input.name)), items: items, remaining: remaining)
            }
            let exact = compatible.filter { normalized($0.name) == normalized(query) }
            if exact.isEmpty, !prefersProducts,
               let relatedQuery = MealFoodNames.relatedRamenQuery(input.name) {
                let related = try await catalog.search(query: relatedQuery)
                try Task.checkCancellation()
                let options = related.filter {
                    $0.brand.isEmpty && $0.category == "음식"
                        && ["시오라멘", "라멘시오라멘"].contains(normalized($0.name))
                        && (input.unit != "g" && input.unit != "mL" || input.unit == $0.amountUnit)
                }
                if !options.isEmpty {
                    return .question(MealEntryQuestion(
                        title: "시오라멘 기준으로 기록할까요?",
                        explanation: "정확히 일치하는 메뉴가 없어 가까운 음식을 찾았어요. 채소와 토핑에 따라 영양값은 달라질 수 있어요",
                        choices: options.prefix(3).map { food in
                            MealEntryChoice(
                                id: food.id, title: food.recordedName, items: items,
                                selection: MealFoodSelection(input: input, food: food, isSimilar: true),
                                remainingFoods: remaining
                            )
                        }
                    ))
                }
            }
            if let food = exact.first, !needsSauce, input.details.isEmpty,
               (input.brand.isEmpty ? food.brand.isEmpty && food.category != "가공식품" : true) {
                return try await resolveSelection(MealFoodSelection(input: input, food: food), items: items, remaining: remaining)
            }
            // "{분류어} {입력}" 형태의 DB 이름은 같은 음식으로 보고 비슷한 음식 질문 없이 기록한다(2026-11-24, #41 2차 D).
            // 실기기에서 "순대국밥"에 DB "국밥 순대국밥"이 비슷한 음식 질문으로 나왔다. 이름은 입력 그대로, 출처에 DB 이름을 남긴다.
            if exact.isEmpty, !needsSauce, input.brand.isEmpty, input.details.isEmpty,
               let food = compatible.first(where: { $0.brand.isEmpty && $0.category != "가공식품" && Self.isCategoryPrefixedName($0.name, of: query) }) {
                MealDebugLog.log("분류어가 붙은 같은 이름 → 비슷한 음식 질문 없이 기록: \(input.name) = \(food.id) \(food.name)")
                return try await resolveSelection(MealFoodSelection(input: input, food: food, isSimilar: true), items: items, remaining: remaining)
            }
            // 이름이 입력으로 시작하는 한 업체의 제품 묶음이 있으면 비슷한 일반 음식보다 먼저 가운데 제품을 쓴다(2026-11-24, #41 2차 E).
            // 실기기에서 "진라면"이 일반 음식 "라면"(국물 포함)으로 가서 150g 123kcal가 됐다. 같은 이름 제품이 있으면 기존 흐름을 따른다.
            if exact.isEmpty, !prefersProducts, input.brand.isEmpty, input.details.isEmpty, productMatches.isEmpty,
               let line = Self.productLine(usableCandidates(from: results, input: input), name: query) {
                var food = line.food
                food.source = "\(food.source) · \([food.brand, food.name].filter { !$0.isEmpty }.joined(separator: " ")) 영양값 기준"
                MealDebugLog.log("이름이 입력으로 시작하는 한 업체 제품 \(line.count)개 → 비슷한 음식 질문 없이 가운데 제품: \(food.id) \(food.name) · \(food.brand)")
                return try await resolveSelection(MealFoodSelection(input: input, food: food, isProductConfirmed: true),
                    items: items, remaining: remaining)
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
            if exact.isEmpty, !prefersProducts, input.details.isEmpty,
               let relatedQuery = FoodReferenceCatalog.similarDishQuery(for: input.name) {
                let related = try await catalog.search(query: relatedQuery)
                try Task.checkCancellation()
                let options = self.candidates(from: related, input: input).filter {
                    $0.category == "음식" && $0.brand.isEmpty
                        && FoodReferenceCatalog.isSimilarPreparedDish(input.name, to: $0.name)
                }
                if !options.isEmpty {
                    return similarFoodQuestion(options, input: input, items: items, remaining: remaining)
                }
            }
            // 검색에서 일반 음식 후보가 하나도 없고 같은 이름 가공식품이 있으면, 모델 검색어로 비슷한 음식을 찾기 전에
            // 제품 확인으로 간다(2026-11-23, #39). 실기기에서 "신라면"이 검색어 "라면"을 거쳐 일반 "라면"으로 기록되던 문제.
            // 일반 음식 후보가 있으면(예: 만두 → 만두 군만두) 지금처럼 그 후보를 먼저 본다.
            // 브랜드 없는 입력의 productMatches는 이름이 같은 제품만 남는다(#37 G1).
            if !prefersProducts, input.brand.isEmpty, exact.isEmpty, compatible.isEmpty, !productMatches.isEmpty {
                return try await productQuestion(productMatches, input: input, items: items, remaining: remaining)
            }
            var selected: FoodCatalogItem?
            var missingInformation = MealClarificationReason.none
            for attempt in 0..<2 {
                if attempt == 1 {
                    let terms: [String]
                    do {
                        terms = try await model("검색어").searchTerms(for: input)
                    } catch MealEntryError.generationFailed {
                        // 검색어 단계가 실패하면 검색어 없이 계속한다(#41, 작업 G).
                        MealDebugLog.log("오류 대신 계속: 검색어 단계 generationFailed → 검색어 없음: \(input.name)")
                        terms = []
                    }
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
                        productMatches += productCandidates(from: matches, input: input)
                        expanded += self.candidates(from: matches, input: input).filter { seen.insert($0.id).inserted }
                    }
                    if prefersProducts, !productMatches.isEmpty {
                        return try await productQuestion(productMatches, input: input, items: items, remaining: remaining)
                    }
                    let additions = expanded.filter { food in !compatible.contains { $0.id == food.id } }
                    guard !additions.isEmpty else { break }
                    // 같은 이름의 일반 음식이 DB에 없고, 모델 검색어로 찾은 후보 중 입력 이름과 겹치는 후보가 하나도 없으면
                    // 비슷한 음식 질문을 내지 않고 영양 추정으로 간다(2026-11-24, #41). 실기기에서 "텐동"에 검색어
                    // "떡볶이, 오징어"의 후보가 비슷한 음식으로 나왔다.
                    if exact.isEmpty, !additions.contains(where: { Self.namesOverlap(input.name, $0.name) }) {
                        MealDebugLog.log("모델 검색어 후보가 입력과 겹치지 않음 → 비슷한 음식 질문 없이 영양 추정: \(input.name), 후보 "
                            + additions.prefix(3).map(\.name).joined(separator: ", "))
                        break
                    }
                    // 이름이 입력 음식이나 모델 검색어와 정확히 같은 일반 음식을 맨 앞에(2026-11-23, #39). 후보 정렬은
                    // 분류 "음식"을 원재료보다 앞에 두어, 검색어 "우유"의 원재료 "우유"가 "우유 딸기"·"달걀찜 우유" 뒤로 밀렸다.
                    let exactNames = Set([normalized(input.name)] + terms.prefix(2).map { normalized($0) })
                    let prioritized = additions.filter { exactNames.contains(normalized($0.name)) }
                        + additions.filter { !exactNames.contains(normalized($0.name)) }
                    candidates = Array(prioritized.prefix(6)) + Array(compatible.prefix(2))
                    compatible = expanded
                }
                guard !candidates.isEmpty else { continue }
                let assessment: MealFoodAssessment
                do {
                    assessment = try await model("후보 선택").assess(input, candidates: candidates)
                } catch MealEntryError.generationFailed {
                    // 후보 선택 단계가 실패하면 첫 후보(같은 이름이 앞에 정렬됨)로 계속한다. 이름이 다르면 비슷한 음식 질문을 거친다(#41, 작업 G).
                    MealDebugLog.log("오류 대신 계속: 후보 선택 단계 generationFailed → 첫 후보 \(candidates[0].name)")
                    assessment = MealFoodAssessment(candidateIndex: 1, clarification: .none)
                }
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
                if food.category == "가공식품" || !food.brand.isEmpty {
                    return try await productQuestion([food], input: input, items: items, remaining: remaining)
                }
                if normalized(food.name) == normalized(input.name) {
                    return try await resolveSelection(MealFoodSelection(input: input, food: food), items: items, remaining: remaining)
                }
                if Self.isCategoryPrefixedName(food.name, of: input.name) {
                    MealDebugLog.log("분류어가 붙은 같은 이름 → 비슷한 음식 질문 없이 기록: \(input.name) = \(food.id) \(food.name)")
                    return try await resolveSelection(MealFoodSelection(input: input, food: food, isSimilar: true), items: items, remaining: remaining)
                }
                let reference = referenceEntry(for: input.name).flatMap { $0.matches(food) ? $0 : nil }
                return similarFoodQuestion([food], input: input, items: items, remaining: remaining,
                    explanation: reference?.displayText ?? FoodModifierCatalog.stripped(input.name)?.displayText(for: food))
            }
            if !products.isEmpty {
                return packagedQuestion(products, input: input, items: items, remaining: remaining)
            }
            if !productMatches.isEmpty {
                return try await productQuestion(productMatches, input: input, items: items, remaining: remaining)
            }
            if prefersProducts { throw MealEntryError.foodNotFound(input.name) }
            // 소스·조리법·재료를 글로 적어 달라는 질문(선택지 0개)은 내지 않는다(#41). 모델이 정보 부족이라고 해도 영양 추정으로 간다.
            if missingInformation != .none {
                MealDebugLog.log("후보 선택에서 정보 부족(\(missingInformation)) → 질문 없이 영양 추정: \(input.name)")
            }
            do {
                let estimate = try await model("영양 추정").estimateNutrition(for: input)
                try Task.checkCancellation()
                return try await estimatedWithoutQuestion(input, estimate: estimate, reason: "DB 후보 없음", items: items, remaining: remaining)
            } catch MealEntryError.portionUnknown {
                guard !input.hasConfirmedPortion else { throw MealEntryError.portionUnknown(input.name) }
                return amountQuestion(input, items: items, remaining: remaining)
            }
        }
        guard !items.isEmpty, items.allSatisfy(\.isValid) else { throw MealEntryError.invalidResult }
        return confirmingLargeItems(items)
    }

    /// 한 줄 열량 상한. 넘으면 기록을 막지 않고 양을 확인한다.
    static let lineCalorieConfirmationLimit = 1000.0

    private func confirmingLargeItems(_ items: [MealEntryItem]) -> MealEntryAnalysis {
        let large = items.indices.filter { items[$0].nutrition.calories > Self.lineCalorieConfirmationLimit }
        guard !large.isEmpty else { return .ready(items) }
        func kcal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
        var halved = items
        for index in large { halved[index].scale = items[index].scale * 0.5 }
        let lines = large.map { "‘\(items[$0].food.name)’ \(items[$0].amountDescription) 약 \(kcal(items[$0].nutrition.calories))kcal" }
        return .question(MealEntryQuestion(
            // 2026-11-24(#41): 양이 아니라 열량이 높아서 확인한다는 뜻이 드러나게 문구만 바꿨다. 기준(1,000kcal)과 선택지는 그대로다.
            title: "열량이 높게 계산됐어요",
            explanation: lines.joined(separator: ", ") + "로, 한 번에 1,000kcal가 넘어요. 먹은 양이 맞으면 그대로 기록하고, 아니면 절반으로 기록한 뒤 기록 화면에서 조절할 수 있어요",
            choices: [
                // selection 없는 선택지는 resolve(_ choice:)에서 담긴 목록 그대로 완료된다.
                MealEntryChoice(id: UUID().uuidString, title: "맞아요, 그대로 기록", items: items,
                    subtitle: large.map { "\(items[$0].amountDescription) · 약 \(kcal(items[$0].nutrition.calories))kcal" }.joined(separator: ", ")),
                MealEntryChoice(id: UUID().uuidString, title: "절반으로 기록", items: halved,
                    subtitle: large.map { "약 \(kcal(halved[$0].nutrition.calories))kcal" }.joined(separator: ", "))
            ]
        ))
    }

    private func similarFoodQuestion(_ foods: [FoodCatalogItem], input: MealFoodInput, items: [MealEntryItem], remaining: [MealFoodInput], explanation: String? = nil) -> MealEntryAnalysis {
        .question(MealEntryQuestion(
            title: "비슷한 음식 기준으로 기록할까요?",
            explanation: (explanation ?? "‘\(input.name)’과 가까운 음식을 찾았어요. 재료 비율과 조리법에 따라 영양값은 달라질 수 있어요") + ". 다르면 입력한 음식 설명을 수정해주세요",
            choices: foods.prefix(3).map { food in
                MealEntryChoice(id: food.id, title: food.recordedName, items: items,
                    selection: MealFoodSelection(input: input, food: food, isSimilar: true), remainingFoods: remaining,
                    subtitle: "유사 음식 기준 · 적어주신 양 유지")
            } + [MealEntryChoice(id: UUID().uuidString, title: Self.estimateChoiceTitle, items: items,
                    remainingFoods: remaining, subtitle: Self.estimateChoiceSubtitle, estimateInput: input)]
        ))
    }

    /// 입력 이름과 후보 이름이 겹치는지(#41). 표기 변형·기호를 맞춘 뒤 후보 이름 전체에 입력과 같은 연속 두 글자가 있거나,
    /// 후보의 주 이름(첫 쉼표 앞, 예: "오징어, 냉동" → 오징어)과 짧은 쪽 글자의 절반 이상(올림)이 같으면 겹친다고 본다.
    /// 두 글자 기준만 쓰면 "멸균유 → 우유"처럼 한 글자만 같은 짧은 이름이 빠져서(M73) 글자 비율도 본다.
    /// 비율은 주 이름으로만 봐서 "텐동"이 상태 설명 "냉동"의 '동' 한 글자로 "오징어, 냉동"과 겹치지 않게 한다(M84).
    static func namesOverlap(_ input: String, _ candidate: String) -> Bool {
        let a = Array(FoodReferenceCatalog.normalized(input)), b = FoodReferenceCatalog.normalized(candidate)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a.count >= 2, (0..<(a.count - 1)).contains(where: { b.contains(String(a[$0...($0 + 1)])) }) { return true }
        let main = FoodReferenceCatalog.normalized(String(candidate.split(separator: ",").first ?? Substring(candidate)))
        guard !main.isEmpty else { return false }
        let common = Set(a).intersection(Set(main)).count
        return common * 2 >= min(a.count, main.count)
    }

    /// DB 이름이 "{분류어} {입력}"인지(#41 2차 D): 두 단어이고, 둘째 단어가 입력 이름과 같고, 첫 단어가 입력 이름의 끝부분이다
    /// (공백·표기 변형을 맞춘 뒤). 예: 입력 "순대국밥"과 DB "국밥 순대국밥".
    static func isCategoryPrefixedName(_ name: String, of input: String) -> Bool {
        let words = name.split(whereSeparator: \.isWhitespace).map { FoodReferenceCatalog.normalized(String($0)) }
        let key = FoodReferenceCatalog.normalized(input)
        guard words.count == 2, !words[0].isEmpty, words[0] != key else { return false }
        return words[1] == key && key.hasSuffix(words[0])
    }

    /// 비슷한 음식 질문의 마지막 선택지(2026-11-23, #39). 후보가 먹은 음식과 다를 때 DB 자료 대신 모델 영양 추정으로 기록한다.
    static let estimateChoiceTitle = "목록에 없어요"
    static let estimateChoiceSubtitle = "AI가 영양값을 추정해요"

    /// "목록에 없어요"를 고른 음식을 모델 영양 추정으로 기록한다. 분량을 모르면 수량 질문으로 간다.
    /// 재료를 글로 적어 달라는 질문(선택지 0개)은 내지 않는다(#41). 추정할 수 없으면 오류로 끝난다.
    private func estimatedChoice(_ input: MealFoodInput, items: [MealEntryItem], remaining: [MealFoodInput]) async throws -> MealEntryAnalysis {
        let estimate: MealNutritionEstimate?
        do {
            estimate = try await model("영양 추정").estimateNutrition(for: input)
        } catch MealEntryError.portionUnknown {
            guard !input.hasConfirmedPortion else { throw MealEntryError.portionUnknown(input.name) }
            return amountQuestion(input, items: items, remaining: remaining)
        }
        try Task.checkCancellation()
        return try await estimatedWithoutQuestion(input, estimate: estimate, reason: "목록에 없어요 선택", items: items, remaining: remaining)
    }

    /// 모델 영양 추정으로 입력한 음식 이름 그대로 기록한다(#41). 기준 음식이 입력에 없어도(예: 텐동 → 김밥) 질문하지 않는다.
    /// 수량을 적지 않았거나 분량이 맞지 않으면 수량 선택 질문으로 가고, 추정 자체가 없으면 음식을 찾지 못했다는 오류로 끝난다.
    private func estimatedWithoutQuestion(_ input: MealFoodInput, estimate: MealNutritionEstimate?, reason: String,
                                          items: [MealEntryItem], remaining: [MealFoodInput]) async throws -> MealEntryAnalysis {
        guard let estimate else {
            MealDebugLog.log("오류: 영양 추정 추정값 없음(\(reason)) \(input.name)")
            throw MealEntryError.foodNotFound(input.name)
        }
        if try await !hasGroundedReference(estimate, input: input) {
            MealDebugLog.log("영양 추정 기준 음식 '\(estimate.referenceFood)'이 입력에 없음 → 입력 이름 '\(input.name)'으로 AI 추정 기록")
        }
        let capped = try await cappedEstimate(Self.reconciledEstimate(estimate, name: input.name), input: input)
        let item: MealEntryItem
        do {
            item = try estimatedItem(input, estimate: capped)
        } catch MealEntryError.portionUnknown {
            guard !input.hasConfirmedPortion else { throw MealEntryError.portionUnknown(input.name) }
            // 수량을 고른 뒤에는 앞의 영양 추정을 다시 쓴다(#41 2차 F). 검색·후보 선택·영양 추정을 되풀이하지 않는다.
            return amountQuestion(input, items: items, remaining: remaining, estimate: estimate)
        }
        return try await resolve(remaining, items: items + [item])
    }

    /// 모델이 돌려준 열량과 탄·단·지 열량(4·4·9kcal/g)이 추정값 검사(isValid) 허용 범위를 넘게 다르면, 열량은 그대로 두고
    /// 탄·단·지를 같은 비율로 맞춘다(2026-11-24, #41 2차 A). 실기기 "텐동" 추정이 100g당 220kcal인데 탄 40·단 5·지 15(315kcal)라
    /// 그대로면 결과 검증 오류 화면이 난다. 맞춘 뒤에도 검사를 못 넘으면 그대로 돌려준다(기존처럼 오류).
    static func reconciledEstimate(_ estimate: MealNutritionEstimate, name: String) -> MealNutritionEstimate {
        guard !estimate.isValid else { return estimate }
        let value = estimate.nutritionPer100
        let macroEnergy = value.carbohydrateGrams * 4 + value.proteinGrams * 4 + value.fatGrams * 9
        guard value.calories.isFinite, value.calories > 0, macroEnergy.isFinite, macroEnergy > 0 else { return estimate }
        let ratio = value.calories / macroEnergy
        let adjusted = MealNutritionEstimate(referenceFood: estimate.referenceFood, amountPerUnit: estimate.amountPerUnit,
            amountUnit: estimate.amountUnit,
            nutritionPer100: NutritionValues(calories: value.calories, carbohydrateGrams: value.carbohydrateGrams * ratio,
                proteinGrams: value.proteinGrams * ratio, fatGrams: value.fatGrams * ratio),
            ingredients: estimate.ingredients, portionEstimated: estimate.portionEstimated)
        guard adjusted.isValid else { return estimate }
        MealDebugLog.log("AI 영양 추정 탄단지 보정: \(name) 100\(estimate.amountUnit)당 \(amountText(value.calories))kcal는 그대로, 탄단지 열량 \(amountText(macroEnergy))kcal → 같은 비율(\(ratio.formatted(.number.precision(.fractionLength(2)))))로 맞춤")
        return adjusted
    }

    /// AI 영양 추정값 상한(2026-11-24, #41 2차 C 사용자 결정). 100g(mL)당 열량이 "같은 분류" DB 일반 음식 100당 열량 중간값의
    /// 1.5배를 넘으면 1.5배로 낮추고 탄·단·지를 같은 비율로 낮춘다. 같은 분류는 입력 이름(공백 제거)의 끝 두 글자로 이름이 끝나는
    /// 브랜드 없는 "음식" 분류 자료(#41 J와 같은 기준)이고, 3개 이상일 때만 정한다. 이 비교에서만 g과 mL를 1:1로 묶는다.
    /// 분량 근거(AI 추정)는 그대로 둔다. 음식 이름은 코드에 넣지 않는다.
    static let estimateCapRatio = 1.5

    private func cappedEstimate(_ estimate: MealNutritionEstimate, input: MealFoodInput) async throws -> MealNutritionEstimate {
        let name = normalized(input.name)
        guard name.count >= 2 else { return estimate }
        let suffix = String(name.suffix(2))
        let results = try await catalog.search(query: suffix)
        try Task.checkCancellation()
        var seen = Set<String>()
        let values = results.filter { food in
            food.brand.isEmpty && food.category == "음식" && FoodCatalogQuality.isUsable(food) && food.baseAmount > 0
                && normalized(food.name).hasSuffix(suffix) && seen.insert(food.id).inserted
        }.map { $0.nutrition.calories / $0.baseAmount * 100 }.sorted()
        guard values.count >= 3 else { return estimate }
        let middle = values.count / 2
        let median = values.count % 2 == 1 ? values[middle] : (values[middle - 1] + values[middle]) / 2
        let cap = median * Self.estimateCapRatio
        let calories = estimate.nutritionPer100.calories
        guard calories > cap, calories > 0 else { return estimate }
        MealDebugLog.log("AI 영양 추정 상한: \(input.name) 100\(estimate.amountUnit)당 \(Self.amountText(calories))kcal → \(Self.amountText(cap))kcal"
            + " (분류어 '\(suffix)', DB 일반 음식 \(values.count)개 중간값 \(Self.amountText(median))kcal의 \(Self.amountText(Self.estimateCapRatio))배)")
        return MealNutritionEstimate(referenceFood: estimate.referenceFood, amountPerUnit: estimate.amountPerUnit,
            amountUnit: estimate.amountUnit, nutritionPer100: estimate.nutritionPer100 * (cap / calories),
            ingredients: estimate.ingredients, portionEstimated: estimate.portionEstimated)
    }

    /// 수량 질문에 답한 뒤 앞의 영양 추정을 다시 쓴다(#41 2차 F). 새 단위의 1단위 분량만 모델에 묻는다(실제 해석기와 같은 방식).
    private func reusedEstimate(_ input: MealFoodInput, estimate: MealNutritionEstimate, items: [MealEntryItem], remaining: [MealFoodInput]) async throws -> MealEntryAnalysis {
        var amount = 100.0
        var portionEstimated = false
        if input.unit == "g" || input.unit == "mL" {
            guard input.unit == estimate.amountUnit else { throw MealEntryError.portionUnknown(input.name) }
            amount = 1
            portionEstimated = true
        } else {
            do {
                amount = try await model("분량 추정").portion(for: input, food: MealNutritionEstimate.portionReference(
                    name: input.name, amountUnit: estimate.amountUnit, nutrition: estimate.nutritionPer100)).amountPerUnit
                portionEstimated = true
            } catch MealEntryError.portionUnknown {
            } catch MealEntryError.generationFailed {
            }
            try Task.checkCancellation()
        }
        MealDebugLog.log("수량 선택 뒤 앞의 영양 추정 재사용(검색·후보 선택·영양 추정 다시 하지 않음): \(input.name) \(Self.amountText(input.quantity))\(input.unit)")
        return try await estimatedWithoutQuestion(input, estimate: MealNutritionEstimate(referenceFood: estimate.referenceFood,
            amountPerUnit: amount, amountUnit: estimate.amountUnit, nutritionPer100: estimate.nutritionPer100,
            ingredients: estimate.ingredients, portionEstimated: portionEstimated),
            reason: "수량 선택", items: items, remaining: remaining)
    }

    /// 용기 단위 표(DrinkReferences.json)로 술·음료를 질문 없이 기록한다. 표로 계산할 수 없으면 nil을 돌려 일반 흐름을 따른다.
    private func resolveDrink(_ input: MealFoodInput, drink: DrinkReference, items: [MealEntryItem], remaining: [MealFoodInput]) async throws -> MealEntryAnalysis? {
        let hasDegree = (input.sourceText + " " + input.details).range(of: #"\d+(?:\.\d+)?\s*(?:도|%)"#, options: .regularExpression) != nil
        // 도수를 적은 일반 술 이름은 제품명을 글로 묻지 않고(선택지 0개 질문 없음, #41) 술 표의 일반 항목으로 기록한다.
        if hasDegree, !drink.isProduct(input.name) {
            MealDebugLog.log("도수를 적은 일반 술 이름: 제품명 질문 없이 술 표 기준 \(drink.name)")
        }
        if ["인분", "개"].contains(input.unit), MealInputGrounding.hasExplicitAmount(in: input.sourceText) {
            return amountQuestion(input, items: items, remaining: remaining)
        }
        let unit = ["인분", "개"].contains(input.unit) ? drink.defaultUnit : input.unit
        guard unit == "mL" || drink.container(for: unit) != nil,
              let food = try await catalog.food(id: drink.referenceID), drink.matches(food) else { return nil }
        try Task.checkCancellation()
        let recorded = MealFoodInput(name: input.name, sourceText: input.sourceText, quantity: input.quantity, unit: unit,
            brand: input.brand, details: input.details, isSideDish: input.isSideDish, hasConfirmedPortion: input.hasConfirmedPortion)
        var item = try drinkItem(recorded, drink: drink, food: food)
        if input.omittedQuantity { item.quantityNote = MealEntryItem.assumedQuantityNote(unit: item.food.servingUnit) }
        return try await resolve(remaining, items: items + [item])
    }

    private func drinkItem(_ input: MealFoodInput, drink: DrinkReference, food: FoodCatalogItem) throws -> MealEntryItem {
        let container = drink.container(for: input.unit)
        guard input.unit == "mL" || container != nil else { throw MealEntryError.portionUnknown(input.name) }
        let amount = container?.milliliters ?? 1
        let isProduct = drink.isProduct(input.name)
        // 저장되는 출처는 사용자에게 보여도 되는 문구만 쓴다. 용기 용량의 내부 근거(DrinkReferences.json의 source)는 저장하지 않는다.
        let basis = container.map { " · 1\($0.unit) \($0.milliliters.formatted(.number.precision(.fractionLength(0...1))))mL 기준" } ?? ""
        let adjusted = FoodCatalogItem(id: food.id, name: isProduct ? food.name : input.name, servingUnit: input.unit,
            servingGrams: 0, nutrition: food.nutrition(for: amount / food.baseAmount), servingMilliliters: amount,
            brand: isProduct ? food.brand : "",
            source: "\(food.source) · \(isProduct ? food.recordedName : "\(food.recordedName) 영양값 기준")\(basis)",
            sourceDate: food.sourceDate, category: food.category)
        let item = MealEntryItem(food: adjusted, servingCount: input.quantity,
            portionBasis: input.unit == "mL" ? .entered : .representative,
            nutritionBasis: isProduct ? .database : .similarFood)
        guard item.isValid else { throw MealEntryError.invalidResult }
        return item
    }

    private func candidates(from results: [FoodCatalogItem], input: MealFoodInput) -> [FoodCatalogItem] {
        let compatible = usableCandidates(from: results, input: input)
        let filtered: [FoodCatalogItem]
        if !input.brand.isEmpty {
            filtered = compatible
        } else if prefersProducts(input) {
            filtered = compatible.filter { $0.category == "가공식품" }
        } else {
            filtered = compatible.filter { $0.brand.isEmpty && $0.category != "가공식품" }
        }
        let reference = referenceEntry(for: input.name)
        let stripped = FoodModifierCatalog.stripped(input.name)
        let ordered = filtered.sorted { left, right in
            let leftIsReference = reference?.matches(left) == true
            let rightIsReference = reference?.matches(right) == true
            if leftIsReference != rightIsReference { return leftIsReference }
            // 이름 그대로 같은 항목은 항상 먼저, 수식어를 뗀 후보는 FoodModifiers.json 규칙 순서
            let leftIsExact = normalized(left.name) == normalized(input.name)
            let rightIsExact = normalized(right.name) == normalized(input.name)
            if leftIsExact != rightIsExact { return leftIsExact }
            if let stripped, stripped.rank(left) != stripped.rank(right) {
                return stripped.rank(left) < stripped.rank(right)
            }
            if (left.category == "음식") != (right.category == "음식") { return left.category == "음식" }
            if (left.amountUnit == "g") != (right.amountUnit == "g") { return left.amountUnit == "g" }
            return false
        }
        var seen = Set<String>()
        return ordered.filter { seen.insert(normalized($0.name + $0.brand)).inserted }
            .groupedByMajorityCategory(sameNameAs: searchName(foodName(of: input)))
    }

    /// 참고표가 mL 기준 항목을 가리키고 같은 요리(어순만 다른 이름 포함)의 g 기준 항목이 있으면 g 항목을 쓴다.
    /// 대표 분량(1인분 g)은 g 항목에만 붙기 때문이다. 없으면 참고표 항목 그대로.
    private func preferredReferenceFood(_ reference: FoodReference, food: FoodCatalogItem) async throws -> FoodCatalogItem {
        try await gramFood(sameNameAs: food) ?? food
    }

    /// mL 기준 항목과 같은 요리이고 분류가 같은 브랜드 없는 g 기준 항목. 없거나 이미 g 항목이면 nil
    /// 같은 요리: 두 이름에 대표 분량 이름 규칙 1~4(FoodPortion.sameDishNames: 그대로, 순서 뒤집기, 분류어, 괄호)를
    /// 적용해 정규화한 이름이 하나라도 겹치면 같은 요리로 본다. 예: "우럭 매운탕"(mL)과 "매운탕 우럭"(g).
    /// 후보는 mL 항목 이름, 그다음 규칙 2~4 이름으로 찾은 검색 결과 순서이고, 그중 첫 항목을 쓴다.
    private func gramFood(sameNameAs food: FoodCatalogItem) async throws -> FoodCatalogItem? {
        guard food.amountUnit == "mL" else { return nil }
        let names = FoodPortion.sameDishNames(food.name)
        let keys = Set(names.map(normalized))
        var seen = Set<String>()
        for name in names {
            let results = try await catalog.search(query: name)
            try Task.checkCancellation()
            let match = results.first { candidate in
                seen.insert(candidate.id).inserted
                    && candidate.amountUnit == "g" && candidate.brand.isEmpty && candidate.category == food.category
                    && FoodCatalogQuality.isUsable(candidate)
                    && FoodPortion.sameDishNames(candidate.name).contains { keys.contains(normalized($0)) }
            }
            if let match { return match }
        }
        return nil
    }

    /// 대표 항목(FoodReferences.json). 이름 그대로 없으면 앞쪽 수식어를 뗀 이름으로 찾는다.
    private func referenceEntry(for name: String) -> FoodReference? {
        FoodReferenceCatalog.entry(for: name) ?? FoodModifierCatalog.stripped(name).flatMap { FoodReferenceCatalog.entry(for: $0.base) }
    }

    private func productCandidates(from results: [FoodCatalogItem], input: MealFoodInput) -> [FoodCatalogItem] {
        let name = searchName(foodName(of: input))
        let query = normalized(name)
        guard !query.isEmpty else { return [] }
        let products = usableCandidates(from: results, input: input).filter {
            $0.category == "가공식품" && normalized($0.name).contains(query)
        }
        // 브랜드 없는 입력은 이름이 같은 제품만 후보로 둔다(2026-11-23, #37). 이름을 포함만 하는 제품
        // (예: 와인 → 와인 숙성 명란, 텐동 → 텐동소스)은 다른 음식이라 뺀다. 제품을 가리키는 입력(봉·팩·컵라면 등)은
        // 이름이 같은 제품이 없을 때만 지금처럼 포함 일치를 쓴다. 브랜드 입력과 검색 화면은 그대로다.
        guard input.brand.isEmpty else { return products.groupedByMajorityCategory(sameNameAs: name) }
        let exact = products.filter { normalized($0.name) == query }
        return (exact.isEmpty && prefersProducts(input) ? products : exact).groupedByMajorityCategory(sameNameAs: name)
    }

    /// 입력 이름에서 브랜드를 뗀 음식 이름
    private func foodName(of input: MealFoodInput) -> String {
        input.brand.isEmpty ? input.name : input.name.replacingOccurrences(of: input.brand, with: "")
    }

    private func usableCandidates(from results: [FoodCatalogItem], input: MealFoodInput) -> [FoodCatalogItem] {
        results.filter { food in
            guard FoodCatalogQuality.isUsable(food) else { return false }
            guard food.baseAmount.isFinite, food.baseAmount > 0,
                  [food.nutrition.calories, food.nutrition.carbohydrateGrams, food.nutrition.proteinGrams, food.nutrition.fatGrams]
                    .allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
            if input.unit == "g" || input.unit == "mL", input.unit != food.amountUnit { return false }
            return input.brand.isEmpty || normalized(food.brand + food.name).contains(normalized(input.brand))
        }
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
        return candidates(from: references, input: input).contains { food in
            terms.allSatisfy { normalized(food.name).contains($0) }
        }
    }

    private func isUnspecified(_ name: String) -> Bool {
        MealInputGrounding.isUnspecifiedSide(name)
    }

    /// 수량을 적지 않은 입력도 묻지 않고 1단위(AI 분량 추정)로 기록하고 안내를 붙인다(#41 2차 B).
    /// 모델이 분량을 못 정한 추정값(portionEstimated false)은 영양 기준량(100g·mL)을 1단위로 기록하고 그 사실을 안내한다.
    private func estimatedItem(_ input: MealFoodInput, estimate: MealNutritionEstimate) throws -> MealEntryItem {
        guard estimate.isValid else { throw MealEntryError.invalidResult }
        let isMeasured = input.unit == "g" || input.unit == "mL"
        guard !isMeasured || input.unit == estimate.amountUnit else { throw MealEntryError.portionUnknown(input.name) }
        let usesBaseAmount = !isMeasured && !estimate.portionEstimated
        let portion = MealPortionEstimate(amountPerUnit: estimate.amountPerUnit, amountUnit: estimate.amountUnit)
        guard isMeasured || usesBaseAmount || portion.isPlausible(for: input.unit, foodName: input.name) else { throw MealEntryError.portionUnknown(input.name) }
        let basis = isMeasured ? 1 : estimate.amountPerUnit
        let count = input.quantity
        guard (0.1...10000).contains(basis * count) else { throw MealEntryError.portionUnknown(input.name) }
        let food = FoodCatalogItem(
            id: "estimated-\(UUID().uuidString)", name: input.name,
            servingUnit: isMeasured ? estimate.amountUnit : (input.unit == "소량" ? "접시" : input.unit),
            servingGrams: estimate.amountUnit == "g" ? basis : 0,
            nutrition: estimate.nutritionPer100 * (basis / 100),
            servingMilliliters: estimate.amountUnit == "mL" ? basis : 0,
            // 재료 설명이 영어면 화면·저장 출처에 내보내지 않는다(#41 2차 A).
            source: "AI 영양 추정" + (estimate.displayIngredients.map { " · \($0)" } ?? ""), category: "추정 음식"
        )
        var item = MealEntryItem(food: food, servingCount: count,
            portionBasis: isMeasured ? .entered : (usesBaseAmount ? .estimated : .aiEstimated), nutritionBasis: .estimated)
        guard item.isValid else { throw MealEntryError.invalidResult }
        if usesBaseAmount {
            MealDebugLog.log("영양 추정 분량 모름 → 영양 기준량 \(Self.amountText(basis))\(estimate.amountUnit)를 1\(food.servingUnit)으로 기록: \(input.name)")
            item.quantityNote = Self.baseAmountNote(base: basis, unit: estimate.amountUnit, assumedQuantity: input.omittedQuantity, servingUnit: food.servingUnit)
        } else if input.omittedQuantity, !isMeasured {
            item.quantityNote = MealEntryItem.assumedQuantityNote(unit: food.servingUnit)
        }
        return item
    }

    private func preparedItem(_ input: MealFoodInput, reference: PreparedFoodReference) throws -> MealEntryItem {
        guard input.isValid, [reference.food.servingUnit, "인분", "g"].contains(input.unit) else {
            throw MealEntryError.portionUnknown(input.name)
        }
        let usesWeight = input.unit == "g"
        let basis = usesWeight ? 1 : reference.food.servingGrams
        guard (0.1...10000).contains(basis * input.quantity) else { throw MealEntryError.invalidResult }
        let food = FoodCatalogItem(
            id: reference.food.id, name: reference.food.name,
            servingUnit: usesWeight ? "g" : reference.food.servingUnit, servingGrams: basis,
            nutrition: reference.food.nutrition * (basis / reference.food.servingGrams),
            source: reference.food.source, sourceDate: reference.food.sourceDate, category: reference.food.category
        )
        let item = MealEntryItem(food: food, servingCount: input.quantity,
            portionBasis: usesWeight ? .entered : .estimated, nutritionBasis: .estimated)
        guard item.isValid else { throw MealEntryError.invalidResult }
        return item
    }

    private func makeItem(_ selection: MealFoodSelection) async throws -> MealEntryItem {
        let food = selection.food
        // 국물·면 mL 항목에 대표 분량을 mL로 쓰기 전에, 같은 요리(어순만 다른 이름 포함)의 g 항목이 있으면 그 항목을 쓴다(g 항목 우선).
        if selection.portionOverride == nil, !["g", "mL"].contains(selection.input.unit),
           FoodPortion.representative(for: food, allowsVolumeAsWeight: true)?.isVolumeAsWeight == true,
           let gram = try await gramFood(sameNameAs: food) {
            return try await makeItem(MealFoodSelection(input: selection.input, food: gram, isSimilar: selection.isSimilar,
                isProductConfirmed: selection.isProductConfirmed))
        }
        let input = try inputWithAssumedUnit(selection)
        if let reference = PreparedFoodReference.entries.first(where: { $0.food.id == food.id }) {
            return try preparedItem(input, reference: reference)
        }
        if let drink = DrinkReferenceCatalog.entry(forFoodID: food.id), drink.matches(food),
           input.unit == "mL" || drink.container(for: input.unit) != nil {
            return try drinkItem(input, drink: drink, food: food)
        }
        if let product = PackagedFoodCatalog.entry(id: food.id) {
            guard input.isValid, input.unit == "g" || ["개", "컵", "봉", "팩", "인분"].contains(input.unit),
                  input.sourceText.range(of: #"조리\s*후|끓인|불린|물\s*포함"#, options: .regularExpression) == nil else {
                throw MealEntryError.portionUnknown(input.name)
            }
            let count = input.unit == "g" ? input.quantity / product.packageGrams : input.quantity
            let item = MealEntryItem(food: product.food, servingCount: count, portionBasis: input.unit == "g" ? .entered : .representative)
            guard item.isValid else { throw MealEntryError.invalidResult }
            return item
        }
        if food.category == "가공식품", Self.usesPackageAmount(food), Self.packageUnits.contains(input.unit),
           selection.portionOverride == nil {
            return try packageItem(selection)
        }
        guard food.category != "가공식품" || isOversizedPackage(food) || ["g", "mL"].contains(input.unit)
                || selection.portionOverride != nil else {
            throw MealEntryError.portionUnknown(input.name)
        }
        let basis: Double
        let count: Double
        let unit: String
        let origin: MealPortionBasis
        var referencePortionUnit = ""
        var volumeNote: String?

        if input.unit == "g" || input.unit == "mL" {
            guard input.unit == food.amountUnit else { throw MealEntryError.portionUnknown(input.name) }
            basis = 1
            count = input.quantity
            unit = input.unit
            origin = .entered
        } else if ["소량", "종지"].contains(input.unit), food.amountUnit == "g",
                  let smallAmount = FoodPortion.smallSideGrams(for: input.name) {
            basis = smallAmount
            count = input.quantity
            unit = input.unit == "종지" ? "종지" : "접시"
            origin = .estimated
        } else if let estimate = selection.portionOverride, let selectedUnit = selection.portionUnit {
            guard estimate.isPlausible(for: selectedUnit, foodName: input.name), estimate.amountUnit == food.amountUnit else {
                throw MealEntryError.portionUnknown(input.name)
            }
            basis = estimate.amountPerUnit
            count = input.quantity
            unit = selectedUnit
            origin = .estimated
        } else if let portion = FoodPortion.representative(for: food, allowsVolumeAsWeight: true),
                  portion.accepts(input.unit) || input.unit == "인분" {
            // mL 기준 국물·면 항목이면 대표 분량 N g을 N mL로 본다(VolumeAsWeight.json).
            basis = portion.grams
            count = input.quantity
            // 입력한 단위를 그대로 보여준다. 1인분을 대표 분량 1단위(예: 1접시)로 계산했으면 그 단위를 안내에 남긴다.
            unit = input.unit
            if input.unit != portion.unit { referencePortionUnit = portion.unit }
            if portion.isVolumeAsWeight { volumeNote = VolumeAsWeight.rule?.displayText }
            origin = .representative
        } else if isOversizedPackage(food), let portion = oversizedPackagePortion(input, food: food),
                  portion.accepts(input.unit) || input.unit == "인분" {
            // 총중량을 쓰지 않는 대용량 포장: 같은 이름 음식의 대표 분량에 제품의 100g당 영양값을 쓴다.
            basis = portion.grams
            count = input.quantity
            unit = input.unit
            if input.unit != portion.unit { referencePortionUnit = portion.unit }
            origin = .representative
        } else if input.brand.isEmpty, input.details.isEmpty,
                  let reference = referenceEntry(for: input.name),
                  let amount = reference.estimatedAmount(for: input.unit, food: food) {
            basis = amount
            count = input.quantity
            unit = input.unit
            origin = .estimated
        } else {
            guard food.category != "가공식품" || isOversizedPackage(food) else { throw MealEntryError.portionUnknown(input.name) }
            let estimate: MealPortionEstimate
            do {
                estimate = try await model("분량 추정").portion(for: input, food: food)
            } catch MealEntryError.generationFailed {
                // 분량 추정 단계 실패는 분량 모름과 같게 다뤄 대체 분량 흐름으로 보낸다(#41, 작업 G·H).
                MealDebugLog.log("분량 추정 단계 generationFailed → 분량 모름으로 처리: \(input.name)")
                throw MealEntryError.portionUnknown(input.name)
            }
            try Task.checkCancellation()
            guard estimate.isPlausible(for: input.unit, foodName: input.name),
                  estimate.amountUnit == food.amountUnit else { throw MealEntryError.portionUnknown(input.name) }
            basis = estimate.amountPerUnit
            count = input.quantity
            unit = input.unit == "소량" ? "접시" : input.unit
            origin = .aiEstimated
        }
        guard (0.1...10000).contains(basis * count) else { throw MealEntryError.portionUnknown(input.name) }
        var adjusted = FoodCatalogItem(
            id: food.id, name: selection.isSimilar ? input.name : food.name, servingUnit: unit,
            servingGrams: food.amountUnit == "g" ? basis : 0,
            nutrition: food.nutrition(for: basis / food.baseAmount),
            servingMilliliters: food.amountUnit == "mL" ? basis : 0,
            brand: selection.isSimilar ? "" : food.brand,
            // 다른 이름의 DB 자료를 쓰면 어느 자료의 영양값인지 남긴다(술 기록과 같은 형식, 2026-11-20 결정).
            // 같은 음식인지 비슷한 음식인지 판단은 기록하지 않는다. 내부 값 nutritionBasis는 그대로 similarFood다.
            source: selection.isSimilar ? "\(food.source) · \(food.recordedName) 영양값 기준" : food.source,
            sourceDate: food.sourceDate, category: food.category
        )
        adjusted.referencePortionUnit = referencePortionUnit
        var item = MealEntryItem(food: adjusted, servingCount: count, portionBasis: origin, nutritionBasis: selection.isSimilar ? .similarFood : .database)
        item.volumeNote = volumeNote
        guard item.isValid else { throw MealEntryError.invalidResult }
        return item
    }

    /// 단위나 수량을 적지 않은 입력의 단위를 정한다.
    /// - 포장제품: 개(제품 1개)
    /// - 대표 분량이 있는 음식: 대표 분량 단위(예: 김밥 → 줄, 쌀밥 → 공기)
    /// - 참고표(FoodReferences.json)의 estimatedPortions가 있는 음식: 그 단위(인분 우선)
    /// - 근거가 없으면: 수량을 적지 않은 입력은 1인분(AI 분량 추정, #41 2차 B), 개수만 적은 입력은 portionUnknown(대체 분량).
    private func inputWithAssumedUnit(_ selection: MealFoodSelection) throws -> MealFoodInput {
        var input = selection.input
        let food = selection.food
        guard input.omittedUnit || input.omittedQuantity, selection.portionOverride == nil,
              !["g", "mL"].contains(input.unit) else { return input }
        if PreparedFoodReference.entries.contains(where: { $0.food.id == food.id }) { return input }
        if DrinkReferenceCatalog.entry(forFoodID: food.id) != nil { return input }
        if isPackagedFood(food), !isOversizedPackage(food) {
            input = input.withUnit("개")
            return input
        }
        if isOversizedPackage(food) {
            // 대용량 포장은 일반 음식처럼: 대표 분량이 있으면 그 단위, 없으면 수량 질문(무게는 묻지 않음)
            if let portion = oversizedPackagePortion(input, food: food) { return input.withUnit(portion.unit) }
            if input.omittedQuantity { return input }
            throw MealEntryError.portionUnknown(input.name)
        }
        if let portion = FoodPortion.representative(for: food, allowsVolumeAsWeight: true) {
            return input.withUnit(portion.unit)
        }
        if input.brand.isEmpty, input.details.isEmpty, let reference = referenceEntry(for: input.name) {
            if reference.estimatedAmount(for: "인분", food: food) != nil { return input.withUnit("인분") }
            if let unit = reference.estimatedPortions?.keys.sorted().first(where: { reference.estimatedAmount(for: $0, food: food) != nil }) {
                return input.withUnit(unit)
            }
        }
        // 수량을 적지 않았고 대표 분량도 없으면 묻지 않고 1인분으로 가정해 AI 분량 추정으로 간다(#41 2차 B).
        // 추정이 안 되면 대체 분량(portionFallback)으로 기록한다.
        if input.omittedQuantity { return input }
        throw MealEntryError.portionUnknown(input.name)
    }

    /// 포장제품(포장제품 표, 가공식품, 브랜드 항목). 조리 음식 참고표와 술 표 항목은 제외
    private func isPackagedFood(_ food: FoodCatalogItem) -> Bool {
        !PreparedFoodReference.entries.contains(where: { $0.food.id == food.id })
            && DrinkReferenceCatalog.entry(forFoodID: food.id) == nil
            && (PackagedFoodCatalog.entry(id: food.id) != nil || food.category == "가공식품" || !food.brand.isEmpty)
    }

    /// 수량·단위를 적지 않은 포장제품은 인분이 아니라 1개(제품 총중량)로 본다(2026-11-17 결정 A).
    /// 총중량 계산, 1개 중량 질문, 기본값 안내가 모두 같은 단위를 쓰도록 항목을 고른 단계에서 단위를 정한다.
    private func selectionWithAssumedPackageUnit(_ selection: MealFoodSelection) -> MealFoodSelection {
        let input = selection.input
        guard input.omittedUnit || input.omittedQuantity, selection.portionOverride == nil,
              !["g", "mL", "개"].contains(input.unit), isPackagedFood(selection.food),
              !isOversizedPackage(selection.food) else { return selection }
        return MealFoodSelection(input: input.withUnit("개"), food: selection.food, isSimilar: selection.isSimilar,
            portionOverride: selection.portionOverride, portionUnit: selection.portionUnit,
            isProductConfirmed: selection.isProductConfirmed)
    }

    /// 제품 총중량으로 계산하는 포장 단위. 인분은 총중량으로 보지 않는다.
    static let packageUnits: Set<String> = ["개", "봉", "팩", "병", "캔"]

    /// 1개 총중량을 1회 먹은 양으로 쓰는 상한(2026-11-23, #37). 업소용·대용량 포장(예: 케이크 6,000g,
    /// 분말 2,000g)의 총중량이 1인분으로 들어가 비현실적인 열량이 기록되지 않게, 이 값 이상이면 총중량을 쓰지 않고
    /// 일반 음식과 같은 분량 흐름(대표 분량 → AI 분량 추정 → "얼마나 드셨나요?" 선택지)으로 보낸다.
    /// 2026-11-23(#39): "넘으면"에서 "이상이면"으로 바꿔 1,500mL 아이스티처럼 상한과 같은 포장도 총중량을 쓰지 않는다.
    /// 방문자에게 무게(g·mL)는 묻지 않는다. 영양값은 고른 제품의 100g(mL)당 값을 쓴다.
    static let packageAmountLimit = 1500.0   // g 또는 mL
    static let packageCalorieLimit = 1500.0  // kcal

    /// 제품 총중량을 1개 분량으로 쓸 수 있는지(총중량이 있고 상한 미만)
    static func usesPackageAmount(_ food: FoodCatalogItem) -> Bool {
        guard food.packageAmount > 0, food.baseAmount > 0 else { return false }
        let calories = food.nutrition.calories * food.packageAmount / food.baseAmount
        return food.packageAmount < packageAmountLimit && calories < packageCalorieLimit
    }

    /// 총중량이 있지만 상한을 넘어 1개로 쓰지 않는 가공식품(포장제품 표 항목은 제외)
    private func isOversizedPackage(_ food: FoodCatalogItem) -> Bool {
        food.category == "가공식품" && food.packageAmount > 0 && !Self.usesPackageAmount(food)
            && PackagedFoodCatalog.entry(id: food.id) == nil
    }

    /// 대용량 포장에 쓸 대표 분량: 입력 이름(같은 음식의 표기)으로 대표 분량표를 찾는다. g 기준 제품에만 쓴다.
    private func oversizedPackagePortion(_ input: MealFoodInput, food: FoodCatalogItem) -> FoodPortion? {
        guard food.amountUnit == "g" else { return nil }
        return FoodPortion.tablePortion(forName: input.name)
    }

    /// 원본 `식품중량`(제품 1개 총중량) × 먹은 개수
    private func packageItem(_ selection: MealFoodSelection) throws -> MealEntryItem {
        let food = selection.food
        let amount = food.packageAmount
        let packaged = FoodCatalogItem(
            id: food.id, name: food.name, servingUnit: selection.input.unit,
            servingGrams: food.amountUnit == "g" ? amount : 0,
            nutrition: food.nutrition(for: amount / food.baseAmount),
            servingMilliliters: food.amountUnit == "mL" ? amount : 0,
            brand: food.brand, source: food.source, sourceDate: food.sourceDate,
            category: food.category, packageAmount: amount
        )
        let item = MealEntryItem(food: packaged, servingCount: selection.input.quantity, portionBasis: .package)
        guard item.isValid, (0.1...10000).contains(amount * selection.input.quantity) else { throw MealEntryError.invalidResult }
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
        FoodReferenceCatalog.normalized(value)
    }
}
