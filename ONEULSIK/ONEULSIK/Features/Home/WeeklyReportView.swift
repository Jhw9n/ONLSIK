import SwiftUI

struct WeeklyReportView: View {
    private let report: WeeklyReportContent
    private let reportInput: AIWeeklyReportInput?
    private let detailReportService = AIWeeklyDetailReportService()
    let onBack: () -> Void

    @State private var detailReport: AIWeeklyDetailReport?
    @State private var isGeneratingDetailReport = false
    @State private var detailGenerationID: UUID?

    init(
        viewModel: HomeViewModel,
        summary: String,
        onBack: @escaping () -> Void
    ) {
        report = WeeklyReportContent(viewModel: viewModel, summary: summary)
        reportInput = viewModel.weeklyReportInput
        _detailReport = State(
            initialValue: viewModel.weeklyReportInput.flatMap {
                AIWeeklyDetailReportService().cachedReport(for: $0)
            }
        )
        self.onBack = onBack
    }

    init(preview: Bool, onBack: @escaping () -> Void) {
        report = .preview
        reportInput = nil
        _detailReport = State(initialValue: nil)
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            NoBounceScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    overviewSection
                    nutritionSection
                    patternSection
                    nextGoalSection
                    basisNotice
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .background(Color.gray01)
        .preferredColorScheme(.light)
        .task {
            await loadDetailReportIfNeeded()
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("주간 리포트")
                    .font(.pretendardSemiBold(16))
                    .foregroundStyle(Color.black01)

                Text(report.periodText)
                    .font(.pretendardMedium(12))
                    .foregroundStyle(Color("gray05"))
            }

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color("black02"))
                        .frame(width: 24, height: 24)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("뒤로가기")

                Spacer()
            }
            .padding(.leading, 4)
        }
        .frame(height: 56)
        .background(Color.gray01)
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("이번 주 한눈에")
                .font(.pretendardSemiBold(16))
                .foregroundStyle(Color.black01)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("주간 섭취 칼로리")
                            .font(.pretendardSemiBold(12))
                            .foregroundStyle(Color.green03)

                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(report.totalCalories.formatted(.number))
                                .font(.pretendardBold(34))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("kcal")
                                .font(.pretendardBold(16))
                        }
                        .foregroundStyle(Color.green03)

                        Text("하루 평균 \(report.averageCalories.formatted(.number)) kcal")
                            .font(.pretendardMedium(12))
                            .foregroundStyle(Color.gray04)

                        Text("최근 7일 중 \(report.recordedDayCount)일 기록했어요.")
                            .font(.pretendardMedium(11))
                            .foregroundStyle(Color.gray04)
                    }

                    Spacer(minLength: 0)

                    WeeklyReportBarChart(days: report.days)
                        .frame(width: 124, height: 100)
                }

                HStack(spacing: 12) {
                    VStack(spacing: 0) {
                        Image("healthFeedbackCharacter")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 42, height: 42)

                        Text("AI")
                            .font(.pretendardSemiBold(9))
                            .foregroundStyle(Color.gray04)
                    }

                    HStack(spacing: 9) {
                        if isGeneratingDetailReport {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.green03)
                        }

                        Text(summaryText)
                            .font(.pretendardSemiBold(13))
                            .foregroundStyle(Color.black01)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
            .background(Color.green01, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("영양 상태")
                .font(.pretendardSemiBold(16))
                .foregroundStyle(Color.black01)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(report.nutrients) { nutrient in
                    nutrientCard(nutrient)
                }
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func nutrientCard(_ nutrient: WeeklyReportNutrient) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: nutrient.symbolName)
                    .font(.system(
                        size: nutrient.title == "단백질" ? 15 : 17,
                        weight: .semibold
                    ))
                    .foregroundStyle(nutrient.level.foregroundColor)
                    .frame(width: 38, height: 38)
                    .background(
                        nutrient.level.foregroundColor.opacity(0.12),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(nutrient.title)
                        .font(.pretendardSemiBold(13))
                        .foregroundStyle(Color.black01)

                    Text(nutrient.level.title)
                        .font(.pretendardBold(18))
                        .foregroundStyle(nutrient.level.foregroundColor)
                }
            }

            Text(nutrient.description)
                .font(.pretendardMedium(11))
                .foregroundStyle(Color.gray04)
                .lineSpacing(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
        .background(
            nutrient.level.backgroundColor,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var patternSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Text("AI가 발견한 패턴")
                    .font(.pretendardSemiBold(16))
                    .foregroundStyle(Color.black01)

                Text("AI")
                    .font(.pretendardBold(9))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Color.green03, in: Capsule())
            }

            VStack(spacing: 10) {
                ForEach(patterns) { pattern in
                    HStack(spacing: 12) {
                        Image(systemName: pattern.symbolName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.green03)
                            .frame(width: 40, height: 40)
                            .background(Color.green01, in: Circle())

                        VStack(alignment: .leading, spacing: 6) {
                            Text(pattern.title)
                                .font(.pretendardSemiBold(14))
                                .foregroundStyle(Color.black01)

                            Text(pattern.description)
                                .font(.pretendardMedium(12))
                                .foregroundStyle(Color.gray04)
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private var nextGoalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("다음 주 목표")
                .font(.pretendardSemiBold(15))

            HStack(spacing: 12) {
                Image("reportGoalCheck")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 19)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(goalTitle)
                        .font(.pretendardBold(16))

                    Text(goalDescription)
                        .font(.pretendardMedium(12))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.green03, Color.tabGreen],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var basisNotice: some View {
        Text("공공 영양 기준과 기록된 식단을 바탕으로 분석했어요")
            .font(.pretendardMedium(10))
            .foregroundStyle(Color.gray04)
            .frame(maxWidth: .infinity)
    }

    private var summaryText: String {
        if isGeneratingDetailReport {
            return "이번 주 식단의 흐름을 자세히 분석하고 있어요."
        }
        return detailReport?.summary ?? report.summary
    }

    private var patterns: [WeeklyReportPattern] {
        guard let detailReport else { return report.patterns }
        let symbols = ["chart.line.uptrend.xyaxis", "fork.knife"]
        return detailReport.patterns.enumerated().map { index, pattern in
            WeeklyReportPattern(
                title: pattern.title,
                description: pattern.description,
                symbolName: symbols[min(index, symbols.count - 1)]
            )
        }
    }

    private var goalTitle: String {
        detailReport?.goalTitle ?? report.goalTitle
    }

    private var goalDescription: String {
        detailReport?.goalDescription ?? report.goalDescription
    }

    @MainActor
    private func loadDetailReportIfNeeded() async {
        guard detailReport == nil, let reportInput else { return }

        let generationID = UUID()
        detailGenerationID = generationID
        isGeneratingDetailReport = true
        Task {
            try? await Task.sleep(for: .seconds(30))
            guard detailGenerationID == generationID else { return }
            detailGenerationID = nil
            isGeneratingDetailReport = false
        }

        do {
            let generatedReport = try await detailReportService.generateReport(
                for: reportInput
            )
            guard
                !Task.isCancelled,
                detailGenerationID == generationID
            else {
                return
            }
            detailGenerationID = nil
            isGeneratingDetailReport = false
            withAnimation(.easeInOut(duration: 0.2)) {
                detailReport = generatedReport
            }
        } catch {
            guard detailGenerationID == generationID else { return }
            detailGenerationID = nil
            isGeneratingDetailReport = false
            #if DEBUG
            print("AI weekly detail report failed: \(error.localizedDescription)")
            #endif
        }
    }
}

private struct WeeklyReportBarChart: View {
    let days: [WeeklyReportDay]

    private var maximumCalories: Double {
        max(days.map(\.calories).max() ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(days) { day in
                VStack(spacing: 5) {
                    Spacer(minLength: 0)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(day.calories > 0 ? Color.green03 : Color.gray02)
                        .frame(
                            height: day.calories > 0
                                ? max(8, 68 * day.calories / maximumCalories)
                                : 6
                        )

                    Text(day.weekday)
                        .font(.pretendardMedium(9))
                        .foregroundStyle(Color.gray04)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct WeeklyReportContent {
    let periodText: String
    let totalCalories: Int
    let averageCalories: Int
    let recordedDayCount: Int
    let days: [WeeklyReportDay]
    let summary: String
    let nutrients: [WeeklyReportNutrient]
    let patterns: [WeeklyReportPattern]
    let goalTitle: String
    let goalDescription: String

    var recordingMessage: String {
        switch recordedDayCount {
        case 0...2:
            "조금 더 기록하면 식사 흐름을 자세히 분석할 수 있어요."
        case 3...5:
            "꾸준히 기록하는 습관이 잘 만들어지고 있어요."
        default:
            "한 주의 식단을 빠짐없이 기록한 점이 좋아요."
        }
    }

    var positiveTitle: String {
        let adequateTitles = nutrients
            .filter { $0.level == .adequate }
            .map(\.title)

        if adequateTitles.count >= 2 {
            return "\(adequateTitles[0])과 \(adequateTitles[1])의 균형이 잘 맞았어요."
        }
        if let adequateTitle = adequateTitles.first {
            return "\(adequateTitle)을 권장 범위에 가깝게 챙겼어요."
        }
        return "이번 주 식단을 꾸준히 기록했어요."
    }

    var positiveDescription: String {
        nutrients.contains(where: { $0.level == .adequate })
            ? "현재의 좋은 흐름을 다음 주에도 이어가보세요."
            : "기록을 이어가며 식사 균형을 천천히 맞춰보세요."
    }

    init(viewModel: HomeViewModel, summary: String) {
        let visibleDays = Array(viewModel.dailyCaloriePoints.suffix(7))
        let reportInput = viewModel.weeklyReportInput
        let recordedDays = reportInput?.recordedDays ?? []
        let recordedDayCount = recordedDays.count
        let divisor = Double(max(recordedDayCount, 1))
        let totalNutrition = recordedDays.reduce(NutritionValues.zero) {
            $0 + $1.nutrition
        }
        let averageNutrition = NutritionValues(
            calories: totalNutrition.calories / divisor,
            carbohydrateGrams: totalNutrition.carbohydrateGrams / divisor,
            proteinGrams: totalNutrition.proteinGrams / divisor,
            fatGrams: totalNutrition.fatGrams / divisor
        )
        let recommendation = reportInput?.recommendation ?? viewModel.recommendation

        periodText = Self.periodText(for: visibleDays.map(\.date))
        totalCalories = Int(totalNutrition.calories.rounded())
        averageCalories = Int(averageNutrition.calories.rounded())
        self.recordedDayCount = recordedDayCount
        days = visibleDays.map { WeeklyReportDay(point: $0) }
        self.summary = summary
        nutrients = Self.nutrientItems(
            average: averageNutrition,
            recommendation: recommendation
        )
        patterns = Self.patternItems(
            recordedDays: recordedDays,
            recommendation: recommendation
        )
        let goal = Self.goal(for: nutrients)
        goalTitle = goal.title
        goalDescription = goal.description
    }

    private init(
        periodText: String,
        totalCalories: Int,
        averageCalories: Int,
        recordedDayCount: Int,
        days: [WeeklyReportDay],
        summary: String,
        nutrients: [WeeklyReportNutrient],
        patterns: [WeeklyReportPattern],
        goalTitle: String,
        goalDescription: String
    ) {
        self.periodText = periodText
        self.totalCalories = totalCalories
        self.averageCalories = averageCalories
        self.recordedDayCount = recordedDayCount
        self.days = days
        self.summary = summary
        self.nutrients = nutrients
        self.patterns = patterns
        self.goalTitle = goalTitle
        self.goalDescription = goalDescription
    }

    static let preview = WeeklyReportContent(
        periodText: "9월 23일 - 9월 29일",
        totalCalories: 8_472,
        averageCalories: 1_694,
        recordedDayCount: 5,
        days: zip(
            ["월", "화", "수", "목", "금", "토", "일"],
            [2_120, 2_480, 0, 2_220, 2_710, 2_950, 0]
        ).enumerated().map { index, value in
            WeeklyReportDay(
                id: index,
                weekday: value.0,
                calories: Double(value.1)
            )
        },
        summary: "기록한 날에는 열량 섭취가 조금 높았어요. 다음 주에는 한 끼 양을 가볍게 조절해보세요.",
        nutrients: [
            WeeklyReportNutrient(
                title: "열량",
                symbolName: "flame.fill",
                description: "권장 기준보다 조금 많이 섭취했어요.",
                progress: 1,
                level: .high
            ),
            WeeklyReportNutrient(
                title: "탄수화물",
                symbolName: "leaf.fill",
                description: "권장 범위에 가깝게 섭취했어요.",
                progress: 0.84,
                level: .adequate
            ),
            WeeklyReportNutrient(
                title: "단백질",
                symbolName: "fish.fill",
                description: "권장 기준보다 조금 부족했어요.",
                progress: 0.69,
                level: .low
            ),
            WeeklyReportNutrient(
                title: "지방",
                symbolName: "drop.fill",
                description: "권장 범위에 가깝게 섭취했어요.",
                progress: 0.86,
                level: .adequate
            )
        ],
        patterns: [
            WeeklyReportPattern(
                title: "기록한 날에는 열량이 높았어요",
                description: "5일 중 3일은 하루 권장 기준보다 높게 기록됐어요.",
                symbolName: "chart.line.uptrend.xyaxis"
            ),
            WeeklyReportPattern(
                title: "단백질이 자주 부족했어요",
                description: "다음 주에는 점심에 단백질 반찬을 더해보세요.",
                symbolName: "fork.knife"
            )
        ],
        goalTitle: "점심에 단백질 반찬 3회 추가하기",
        goalDescription: "작은 목표 하나부터 실천하며 식사 균형을 맞춰보세요."
    )

    private static func periodText(for dates: [Date]) -> String {
        guard let firstDate = dates.first, let lastDate = dates.last else {
            return "최근 7일"
        }
        return "\(dateText(firstDate)) - \(dateText(lastDate))"
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(Locale(identifier: "ko_KR"))
                .month(.defaultDigits)
                .day(.defaultDigits)
        )
    }

    private static func nutrientItems(
        average: NutritionValues,
        recommendation: NutritionRecommendation
    ) -> [WeeklyReportNutrient] {
        [
            nutrient(
                title: "열량",
                symbolName: "flame.fill",
                value: average.calories,
                recommendation: recommendation.calories
            ),
            nutrient(
                title: "탄수화물",
                symbolName: "leaf.fill",
                value: average.carbohydrateGrams,
                recommendation: recommendation.carbohydrateGrams
            ),
            nutrient(
                title: "단백질",
                symbolName: "fish.fill",
                value: average.proteinGrams,
                recommendation: recommendation.proteinGrams
            ),
            nutrient(
                title: "지방",
                symbolName: "drop.fill",
                value: average.fatGrams,
                recommendation: recommendation.fatGrams
            )
        ]
    }

    private static func nutrient(
        title: String,
        symbolName: String,
        value: Double,
        recommendation: Double
    ) -> WeeklyReportNutrient {
        let ratio = recommendation > 0 ? value / recommendation : 0
        return WeeklyReportNutrient(
            title: title,
            symbolName: symbolName,
            description: levelDescription(for: WeeklyReportLevel(ratio: ratio)),
            progress: min(max(ratio, 0), 1),
            level: WeeklyReportLevel(ratio: ratio)
        )
    }

    private static func levelDescription(for level: WeeklyReportLevel) -> String {
        switch level {
        case .low:
            "권장 기준보다 조금 부족했어요."
        case .adequate:
            "권장 범위에 가깝게 섭취했어요."
        case .high:
            "권장 기준보다 조금 많이 섭취했어요."
        }
    }

    private static func patternItems(
        recordedDays: [AIWeeklyNutritionDay],
        recommendation: NutritionRecommendation
    ) -> [WeeklyReportPattern] {
        guard !recordedDays.isEmpty else {
            return [
                WeeklyReportPattern(
                    title: "아직 분석할 기록이 부족해요",
                    description: "식단을 기록하면 반복되는 패턴을 찾아드릴게요.",
                    symbolName: "calendar.badge.plus"
                )
            ]
        }

        let highCalorieDayCount = recordedDays.filter {
            $0.nutrition.calories > recommendation.calories * 1.2
        }.count
        let lowProteinDayCount = recordedDays.filter {
            $0.nutrition.proteinGrams < recommendation.proteinGrams * 0.8
        }.count

        let caloriePattern: WeeklyReportPattern
        if highCalorieDayCount > 0 {
            caloriePattern = WeeklyReportPattern(
                title: "열량이 높은 날이 있었어요",
                description: "기록한 \(recordedDays.count)일 중 \(highCalorieDayCount)일은 하루 기준보다 높았어요.",
                symbolName: "chart.line.uptrend.xyaxis"
            )
        } else {
            caloriePattern = WeeklyReportPattern(
                title: "열량 흐름이 비교적 안정적이었어요",
                description: "기록한 날에는 큰 변화 없이 비슷한 흐름을 보였어요.",
                symbolName: "chart.line.flattrend.xyaxis"
            )
        }

        let proteinPattern: WeeklyReportPattern
        if lowProteinDayCount > 0 {
            proteinPattern = WeeklyReportPattern(
                title: "단백질이 부족한 날이 반복됐어요",
                description: "기록한 \(recordedDays.count)일 중 \(lowProteinDayCount)일은 단백질이 부족했어요.",
                symbolName: "fork.knife"
            )
        } else {
            proteinPattern = WeeklyReportPattern(
                title: "단백질을 꾸준히 챙겼어요",
                description: "기록한 날에는 단백질 섭취가 대체로 안정적이었어요.",
                symbolName: "fork.knife"
            )
        }

        return [caloriePattern, proteinPattern]
    }

    private static func goal(
        for nutrients: [WeeklyReportNutrient]
    ) -> (title: String, description: String) {
        if let lowNutrient = nutrients.first(where: { $0.level == .low }) {
            let title = switch lowNutrient.title {
            case "단백질": "점심에 단백질 반찬 3회 추가하기"
            case "탄수화물": "끼니에 곡류를 적당히 더하기"
            case "지방": "견과류나 식물성 지방을 더해보기"
            default: "빠뜨린 끼니 없이 식사 기록하기"
            }
            return (title, "부족했던 영양을 한 번에 바꾸기보다 작은 습관부터 시작해보세요.")
        }

        if nutrients.contains(where: { $0.level == .high }) {
            return (
                "하루 한 끼의 양을 가볍게 조절하기",
                "자주 먹는 식사의 양부터 조금씩 점검해보세요."
            )
        }

        return (
            "이번 주 식사 균형 이어가기",
            "현재의 균형을 유지하며 식단 기록을 계속해보세요."
        )
    }
}

private struct WeeklyReportDay: Identifiable {
    let id: Int
    let weekday: String
    let calories: Double

    init(point: DailyCaloriePoint) {
        id = Int(point.date.timeIntervalSince1970)
        weekday = point.date.formatted(
            .dateTime.weekday(.narrow).locale(Locale(identifier: "ko_KR"))
        )
        calories = point.calories
    }

    init(id: Int, weekday: String, calories: Double) {
        self.id = id
        self.weekday = weekday
        self.calories = calories
    }
}

private struct WeeklyReportNutrient: Identifiable {
    let title: String
    let symbolName: String
    let description: String
    let progress: Double
    let level: WeeklyReportLevel

    var id: String { title }
}

private struct WeeklyReportPattern: Identifiable {
    let title: String
    let description: String
    let symbolName: String

    var id: String { title }
}

private enum WeeklyReportLevel: Equatable {
    case low
    case adequate
    case high

    init(ratio: Double) {
        if ratio < 0.8 {
            self = .low
        } else if ratio > 1.2 {
            self = .high
        } else {
            self = .adequate
        }
    }

    var title: String {
        switch self {
        case .low: "부족"
        case .adequate: "적정"
        case .high: "많음"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .low: Color.blue02
        case .adequate: Color.green03
        case .high: Color.red02
        }
    }

    var backgroundColor: Color {
        switch self {
        case .low: Color.blue01
        case .adequate: Color.green01
        case .high: Color.red01
        }
    }
}

#Preview {
    WeeklyReportView(preview: true, onBack: {})
}
