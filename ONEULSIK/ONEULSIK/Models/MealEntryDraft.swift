import Foundation

enum MealPortionBasis: String {
    case recorded
    case representative
    case estimated
    case entered
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

    init(id: UUID = UUID(), food: FoodCatalogItem, servingCount: Double, portionBasis: MealPortionBasis = .recorded, nutritionBasis: MealNutritionBasis = .database) {
        self.id = id
        self.food = food
        self.servingCount = servingCount
        self.portionBasis = portionBasis
        self.nutritionBasis = nutritionBasis
    }

    var count: Double { servingCount * scale }
    var nutrition: NutritionValues { food.nutrition(for: count) }
    var usesWeight: Bool { food.servingUnit == "g" || food.servingUnit == "mL" }
    var quantityUnit: String { usesWeight ? food.amountUnit : food.servingUnit }
    var quantity: Double { usesWeight ? food.baseAmount * count : count }
    var quantityStep: Double { usesWeight ? 10 : 0.5 }
    var basisDescription: String? {
        guard food.baseAmount > 0, !usesWeight else { return nil }
        return "약 \((food.baseAmount * count).formatted(.number.precision(.fractionLength(0...1))))\(food.amountUnit)"
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
            "‘\(name)’의 양을 가늠하기 어려워요. g 또는 mL를 함께 적어주세요."
        case .generationFailed:
            "식사를 분석하지 못했어요. 음식과 먹은 양을 간단히 적고 다시 시도해주세요."
        }
    }
}
