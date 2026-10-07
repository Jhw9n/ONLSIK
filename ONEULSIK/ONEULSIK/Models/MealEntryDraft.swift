import Foundation

struct MealEntryItem: Identifiable {
    let id: UUID
    let food: FoodCatalogItem
    let servingCount: Double
    var scale: Double = 1

    init(id: UUID = UUID(), food: FoodCatalogItem, servingCount: Double) {
        self.id = id
        self.food = food
        self.servingCount = servingCount
    }

    var count: Double { servingCount * scale }
    var nutrition: NutritionValues { food.nutrition(for: count) }
    var usesWeight: Bool { food.servingUnit == "g" || food.servingUnit == "mL" }
    var quantityUnit: String { usesWeight ? food.amountUnit : food.servingUnit }
    var quantity: Double { usesWeight ? food.baseAmount * count : count }
    var quantityStep: Double { usesWeight ? 10 : 0.5 }
    var basisDescription: String? {
        guard food.baseAmount > 0, !usesWeight else { return nil }
        return "약 \((food.baseAmount * count).formatted(.number.precision(.fractionLength(0...1))))\(food.amountUnit) · 기록 분량 기준"
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
                servingMilliliters: record.servingMilliliters
            ),
            servingCount: record.servingCount
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
}

struct MealEntryQuestion {
    let title: String
    let explanation: String
    let choices: [MealEntryChoice]
}

enum MealEntryAnalysis {
    case question(MealEntryQuestion)
    case ready([MealEntryItem])
}

@MainActor
protocol MealEntryAnalyzing {
    func analyze(_ text: String) async throws -> MealEntryAnalysis
}

struct UnconnectedMealEntryAnalyzer: MealEntryAnalyzing {
    func analyze(_ text: String) async throws -> MealEntryAnalysis {
        throw MealEntryError.notConnected
    }
}

enum MealEntryError: LocalizedError {
    case notConnected
    case invalidResult

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "AI 식사 분석은 아직 연결 전이에요. 기존 음식 검색으로 기록할 수 있어요."
        case .invalidResult:
            "식사 정보를 확인하지 못했어요. 음식과 양을 다시 적어주세요."
        }
    }
}
