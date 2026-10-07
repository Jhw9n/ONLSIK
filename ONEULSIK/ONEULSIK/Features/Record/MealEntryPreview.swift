#if DEBUG
import SwiftUI

private struct PreviewMealEntryAnalyzer: MealEntryAnalyzing {
    func analyze(_ text: String) async throws -> MealEntryAnalysis {
        try await Task.sleep(for: .milliseconds(700))
        if text.contains("스파게티") || text.contains("파스타") {
            if text.contains("크림") { return .ready([MealEntryPreviewData.pasta("크림")]) }
            if text.contains("토마토") { return .ready([MealEntryPreviewData.pasta("토마토")]) }
            if text.contains("오일") { return .ready([MealEntryPreviewData.pasta("오일")]) }
            return .question(MealEntryPreviewData.sauceQuestion)
        }
        if text.contains("김밥") {
            return .ready(text.contains("라면") ? MealEntryPreviewData.gimbapAndRamen : [MealEntryPreviewData.gimbapAndRamen[0]])
        }
        throw MealEntryError.invalidResult
    }
}

private enum MealEntryPreviewData {
    static func item(_ name: String, unit: String, grams: Double, calories: Double) -> MealEntryItem {
        MealEntryItem(
            food: FoodCatalogItem(
                id: "preview-\(name)", name: name, servingUnit: unit, servingGrams: grams,
                nutrition: NutritionValues(calories: calories, carbohydrateGrams: 70, proteinGrams: 15, fatGrams: 12)
            ),
            servingCount: 1
        )
    }

    static let gimbapAndRamen = [
        item("김밥", unit: "줄", grams: 200, calories: 320),
        item("라면", unit: "그릇", grams: 500, calories: 500)
    ]

    static func pasta(_ sauce: String) -> MealEntryItem {
        item("\(sauce) 스파게티", unit: "인분", grams: 400, calories: 600)
    }

    static var sauceQuestion: MealEntryQuestion {
        MealEntryQuestion(
            title: "어떤 소스였나요?",
            explanation: "가까운 종류 하나만 골라주세요",
            choices: ["토마토", "크림", "오일"].map {
                MealEntryChoice(id: $0, title: $0, items: [pasta($0)])
            }
        )
    }

    static var recents: [RecentMealEntry] {
        [
            RecentMealEntry(items: gimbapAndRamen),
            RecentMealEntry(items: [item("짜장면", unit: "그릇", grams: 650, calories: 800)]),
            RecentMealEntry(items: [item("쌀밥 · 된장찌개", unit: "인분", grams: 600, calories: 520)])
        ]
    }

    static func model(text: String = "", phase: MealEntryViewModel.Phase = .idle, empty: Bool = false) -> MealEntryViewModel {
        let model = MealEntryViewModel(mealType: .lunch, analyzer: PreviewMealEntryAnalyzer())
        model.configurePreview(text: text, phase: phase, recentMeals: empty ? [] : recents, items: gimbapAndRamen)
        return model
    }
}

#Preview("식사 입력 · 기본") {
    MealEntryView(previewModel: MealEntryPreviewData.model())
}

#Preview("식사 입력 · 활성") {
    MealEntryView(previewModel: MealEntryPreviewData.model(text: "밥"))
}

#Preview("식사 입력 · 여러 줄") {
    MealEntryView(previewModel: MealEntryPreviewData.model(text: "점심에 김밥 한 줄이랑 라면을 먹었어요.\n라면 국물은 조금만 먹었고\n간식으로 사과 반 개도 먹었어요."))
}

#Preview("식사 입력 · 분석 중") {
    MealEntryView(previewModel: MealEntryPreviewData.model(text: "김밥 한 줄이랑 라면", phase: .analyzing))
}

#Preview("식사 입력 · 추가 선택") {
    MealEntryView(previewModel: MealEntryPreviewData.model(text: "스파게티", phase: .question(MealEntryPreviewData.sauceQuestion)))
}

#Preview("식사 입력 · 확인") {
    MealEntryView(previewModel: MealEntryPreviewData.model(text: "김밥 한 줄이랑 라면", phase: .ready))
}

#Preview("식사 입력 · 첫 기록") {
    MealEntryView(previewModel: MealEntryPreviewData.model(empty: true))
}

#Preview("식사 입력 · 연결 전") {
    MealEntryView(previewModel: MealEntryPreviewData.model(text: "김밥", phase: .failed(MealEntryError.notConnected.localizedDescription)))
}
#endif
