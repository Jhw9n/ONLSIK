import SwiftUI

struct MealEntryPresentation: View {
    let profile: UserProfile
    let mealType: MealType
    let recordedAt: Date
    let mealRecordStore: MealRecordStore
    let onSaved: () -> Void

    @State private var unavailableReason = AppleMealFoodInterpreter.unavailabilityReason

    var body: some View {
        Group {
            if let unavailableReason {
                FoodSearchView(
                    profile: profile,
                    mealType: mealType,
                    recordedAt: recordedAt,
                    mealRecordStore: mealRecordStore,
                    onSaved: onSaved,
                    availabilityMessage: unavailableReason
                )
            } else {
                MealEntryView(
                    profile: profile,
                    mealType: mealType,
                    recordedAt: recordedAt,
                    mealRecordStore: mealRecordStore,
                    onSaved: onSaved
                )
            }
        }
    }
}
