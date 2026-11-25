import Foundation
import SwiftData

@Model
final class MealRecord {
    var kakaoUserID: Int64
    var recordedAt: Date
    var mealTypeRawValue: String = MealType.snack.rawValue
    var foodID: String = ""
    var foodName: String = "식사"
    var servingUnit: String = "인분"
    var servingGrams: Double = 0
    var servingMilliliters: Double = 0
    var servingCount: Double = 1
    var portionBasisRawValue: String = ""
    var nutritionSource: String = ""
    var nutritionBasisRawValue: String = ""
    var calories: Double
    var carbohydrateGrams: Double
    var proteinGrams: Double
    var fatGrams: Double

    init(
        kakaoUserID: Int64,
        recordedAt: Date,
        mealTypeRawValue: String = MealType.snack.rawValue,
        foodID: String = "",
        foodName: String = "식사",
        servingUnit: String = "인분",
        servingGrams: Double = 0,
        servingMilliliters: Double = 0,
        servingCount: Double = 1,
        calories: Double,
        carbohydrateGrams: Double,
        proteinGrams: Double,
        fatGrams: Double
    ) {
        self.kakaoUserID = kakaoUserID
        self.recordedAt = recordedAt
        self.mealTypeRawValue = mealTypeRawValue
        self.foodID = foodID
        self.foodName = foodName
        self.servingUnit = servingUnit
        self.servingGrams = servingGrams
        self.servingMilliliters = servingMilliliters
        self.servingCount = servingCount
        self.calories = calories
        self.carbohydrateGrams = carbohydrateGrams
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
    }
}

nonisolated struct NutritionValues: Equatable, Hashable, Sendable {
    var calories: Double
    var carbohydrateGrams: Double
    var proteinGrams: Double
    var fatGrams: Double

    static let zero = NutritionValues(
        calories: 0,
        carbohydrateGrams: 0,
        proteinGrams: 0,
        fatGrams: 0
    )

    static func + (lhs: NutritionValues, rhs: NutritionValues) -> NutritionValues {
        NutritionValues(
            calories: lhs.calories + rhs.calories,
            carbohydrateGrams: lhs.carbohydrateGrams + rhs.carbohydrateGrams,
            proteinGrams: lhs.proteinGrams + rhs.proteinGrams,
            fatGrams: lhs.fatGrams + rhs.fatGrams
        )
    }

    static func * (lhs: NutritionValues, rhs: Double) -> NutritionValues {
        NutritionValues(
            calories: lhs.calories * rhs,
            carbohydrateGrams: lhs.carbohydrateGrams * rhs,
            proteinGrams: lhs.proteinGrams * rhs,
            fatGrams: lhs.fatGrams * rhs
        )
    }
}

extension MealRecord {
    var mealType: MealType {
        MealType(rawValue: mealTypeRawValue) ?? .snack
    }

    var servingDescription: String {
        let count = servingCount.formatted(
            .number.precision(.fractionLength(0...2))
        )
        let amount = ((servingMilliliters > 0 ? servingMilliliters : servingGrams) * servingCount).formatted(
            .number.precision(.fractionLength(0...2))
        )
        guard servingGrams > 0 || servingMilliliters > 0 else { return "\(count)\(servingUnit)" }
        let unit = servingMilliliters > 0 ? "mL" : "g"
        if servingUnit == unit { return "\(amount)\(unit)" }
        // 음식 DB mL 자료의 고체 음식은 숫자를 숨기고 국물·면은 g으로 보인다(표시만, MealAmountDisplay, #43).
        if servingMilliliters > 0 {
            let style = MealAmountDisplay.style(foodID: foodID, name: foodName, servingUnit: servingUnit, usesMilliliters: true,
                                                isEntered: portionBasisRawValue == MealPortionBasis.entered.rawValue)
            switch style {
            case .hidden: return "\(count)\(servingUnit)"
            case .grams: return "\(count)\(servingUnit) (\(amount)g)"
            case .asIs: break
            }
        }
        return "\(count)\(servingUnit) (\(amount)\(unit))"
    }

    var nutritionValues: NutritionValues {
        NutritionValues(
            calories: calories,
            carbohydrateGrams: carbohydrateGrams,
            proteinGrams: proteinGrams,
            fatGrams: fatGrams
        )
    }
}
