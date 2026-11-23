import Foundation

enum MealPortionBasis: String {
    case recorded
    case representative
    case estimated
    case entered
    /// 가공식품 원본의 제품 총중량(식품중량) × 개수
    case package
    /// 온디바이스 모델이 추정한 분량(근거 데이터 없음)
    case aiEstimated

    var label: String? {
        switch self {
        case .package: "제품 총중량 기준"
        case .aiEstimated: "AI 추정"
        default: nil
        }
    }
}

enum MealNutritionBasis: String {
    case database
    case similarFood
    case estimated
}

struct MealEntryItem: Identifiable {
    let id: UUID
    let food: FoodCatalogItem
    let servingCount: Double
    var scale: Double = 1
    let portionBasis: MealPortionBasis
    let nutritionBasis: MealNutritionBasis
    /// 수량을 적지 않아 기본값으로 가정했을 때 카드에 보여줄 안내(화면 문구). 기록에는 저장하지 않는다.
    var quantityNote: String?
    /// mL 기준 국물·면 항목에 g 대표 분량을 같은 숫자의 mL로 계산했을 때의 안내(VolumeAsWeight.json displayText). 기록에는 저장하지 않는다.
    var volumeNote: String?

    init(id: UUID = UUID(), food: FoodCatalogItem, servingCount: Double, portionBasis: MealPortionBasis = .recorded, nutritionBasis: MealNutritionBasis = .database) {
        self.id = id
        self.food = food
        self.servingCount = servingCount
        self.portionBasis = portionBasis
        self.nutritionBasis = nutritionBasis
    }

    var count: Double { servingCount * scale }
    var nutrition: NutritionValues { food.nutrition(for: count) }
    /// 화면에 보이는 음식별 열량(정수 반올림). 합계도 이 값을 더해 보여준다.
    var displayedCalories: Int { Int(nutrition.calories.rounded()) }
    var usesWeight: Bool { food.servingUnit == "g" || food.servingUnit == "mL" }
    var quantityUnit: String { usesWeight ? food.amountUnit : food.servingUnit }
    var quantity: Double { usesWeight ? food.baseAmount * count : count }
    var quantityStep: Double { usesWeight ? 10 : 0.5 }
    var basisDescription: String? {
        guard food.baseAmount > 0, !usesWeight else { return nil }
        let amount = "약 \((food.baseAmount * count).formatted(.number.precision(.fractionLength(0...1))))\(food.amountUnit)"
        let reference = portionBasis == .representative && !food.referencePortionUnit.isEmpty
            && food.referencePortionUnit != food.servingUnit ? "대표 분량 1\(food.referencePortionUnit) 기준" : nil
        // 기본값 안내는 처음 가정한 수량 그대로일 때만 보여준다(± 버튼으로 바꾸면 숨김).
        let note = abs(scale - 1) < 0.000_001 ? quantityNote : nil
        return [amount, reference, portionBasis.label, volumeNote, note].compactMap { $0 }.joined(separator: " · ")
    }

    /// 수량을 적지 않아 1단위로 가정했을 때의 화면 문구. 예: "수량이 없어서 1인분으로 가정했어요"
    static func assumedQuantityNote(unit: String) -> String {
        let particle: String
        if let last = unit.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) {
            let final = (last.value - 0xAC00) % 28
            particle = final == 0 || final == 8 ? "로" : "으로"   // 받침 없음 또는 ㄹ 받침
        } else {
            particle = "로"
        }
        return "수량이 없어서 1\(unit)\(particle) 가정했어요"
    }
    var amountDescription: String {
        if food.servingUnit == "g" || food.servingUnit == "mL" {
            return "\((food.baseAmount * count).formatted(.number.precision(.fractionLength(0...1))))\(food.amountUnit)"
        }
        return "\(count.formatted(.number.precision(.fractionLength(0...2))))\(food.servingUnit)"
    }

    var isValid: Bool {
        !food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && count.isFinite && count > 0 && count <= 10000
            && food.servingGrams.isFinite && food.servingGrams >= 0
            && food.servingMilliliters.isFinite && food.servingMilliliters >= 0
            && (!usesWeight || food.baseAmount > 0)
            && [nutrition.calories, nutrition.carbohydrateGrams, nutrition.proteinGrams, nutrition.fatGrams]
                .allSatisfy { $0.isFinite && $0 >= 0 }
    }

    init?(record: MealRecord) {
        guard record.servingCount.isFinite, record.servingCount > 0 else { return nil }
        self.init(
            food: FoodCatalogItem(
                id: record.foodID,
                name: record.foodName,
                servingUnit: record.servingUnit,
                servingGrams: record.servingGrams,
                nutrition: record.nutritionValues * (1 / record.servingCount),
                servingMilliliters: record.servingMilliliters,
                source: record.nutritionSource
            ),
            servingCount: record.servingCount,
            portionBasis: MealPortionBasis(rawValue: record.portionBasisRawValue) ?? .recorded,
            nutritionBasis: MealNutritionBasis(rawValue: record.nutritionBasisRawValue) ?? .database
        )
        guard isValid else { return nil }
    }
}

struct RecentMealEntry: Identifiable {
    let id: UUID = UUID()
    let items: [MealEntryItem]
    var title: String { items.map(\.food.name).joined(separator: " · ") }

    static func grouped(from records: [MealRecord], calendar: Calendar = .current) -> [RecentMealEntry] {
        struct MealKey: Hashable {
            let day: Date
            let mealType: String
        }

        let groups = Dictionary(grouping: records) {
            MealKey(day: calendar.startOfDay(for: $0.recordedAt), mealType: $0.mealTypeRawValue)
        }
        let sortedGroups = groups.sorted { left, right in
            if left.key.day != right.key.day { return left.key.day > right.key.day }
            return left.key.mealType < right.key.mealType
        }
        var signatures = Set<[String]>()
        return sortedGroups.compactMap { _, group -> RecentMealEntry? in
            let items = group.sorted { $0.foodName < $1.foodName }.compactMap { MealEntryItem(record: $0) }
            guard !items.isEmpty, items.count == group.count else { return nil }
            let signature = items.map {
                "\($0.food.id)|\($0.food.name)|\($0.food.servingUnit)|\($0.food.baseAmount)|\($0.servingCount)|\($0.food.nutrition)"
            }
            guard signatures.insert(signature).inserted else { return nil }
            return RecentMealEntry(items: items)
        }.prefix(3).map { $0 }
    }
}

struct MealEntryChoice: Identifiable {
    let id: String
    let title: String
    let items: [MealEntryItem]
    var selection: MealFoodSelection? = nil
    var remainingFoods: [MealFoodInput] = []
    var continuationInput: MealFoodInput? = nil
    var portionInput: MealFoodInput? = nil
    var correctedText: String? = nil
    var requiresPackageCount = false
    var requiresUnitAmount = false
    var subtitle: String? = nil
    /// "목록에 없어요"를 고르면 DB 자료 대신 모델 영양 추정으로 기록할 음식(#39)
    var estimateInput: MealFoodInput? = nil
}

struct MealEntryQuestion {
    let id = UUID()
    let title: String
    let explanation: String
    let choices: [MealEntryChoice]
    var clarification: MealEntryChoice? = nil
    var inputPlaceholder = "재료나 조리 방법을 짧게 적어주세요"
}

enum MealEntryAnalysis {
    case question(MealEntryQuestion)
    case ready([MealEntryItem])
}

@MainActor
protocol MealEntryAnalyzing {
    func analyze(_ text: String) async throws -> MealEntryAnalysis
    func resolve(_ choice: MealEntryChoice) async throws -> MealEntryAnalysis
}

extension MealEntryAnalyzing {
    func resolve(_ choice: MealEntryChoice) async throws -> MealEntryAnalysis {
        .ready(choice.items)
    }
}

enum MealEntryError: LocalizedError {
    case unavailable(String)
    case invalidResult
    case inputTooLong
    case timedOut
    case foodNotFound(String)
    case portionUnknown(String)
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            message
        case .invalidResult:
            "식사 정보를 확인하지 못했어요. 음식과 양을 다시 적어주세요."
        case .inputTooLong:
            "한 번에 음식 8개까지, 500자 이내로 적어주세요."
        case .timedOut:
            "분석이 오래 걸리고 있어요. 다시 시도하거나 음식을 나누어 입력해주세요."
        case .foodNotFound(let name):
            "‘\(name)’의 영양정보를 찾지 못했어요. 음식 이름을 구체적으로 적거나 직접 검색해주세요."
        case .portionUnknown(let name):
            "‘\(name)’의 분량을 아직 계산하지 못했어요. 반 인분, 한 그릇처럼 다른 표현으로 적거나 음식 종류를 더 알려주세요."
        case .generationFailed:
            "식사를 분석하지 못했어요. 음식과 먹은 양을 간단히 적고 다시 시도해주세요."
        }
    }
}
