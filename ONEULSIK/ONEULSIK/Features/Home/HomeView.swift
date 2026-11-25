import SwiftData
import SwiftUI

struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var isShowingNotificationNotice = false
    @State private var reportDismissScrollToTopTrigger = 0
    @State private var aiReportState: AIWeeklyReportState
    @State private var reportGenerationTask: Task<Void, Never>?
    @State private var reportGenerationID: UUID?

    private let profile: UserProfile
    private let weightRecordStore: WeightRecordStore?
    private let scrollToTopTrigger: Int
    private let usesAutomaticAIAvailability: Bool
    private let aiReportAvailabilityService = AIWeeklyReportAvailabilityService()
    private let aiWeeklyReportService = AIWeeklyReportService()
    @Environment(\.appRouter) private var router

    init(
        profile: UserProfile,
        mealRecordStore: MealRecordStore,
        weightRecordStore: WeightRecordStore? = nil,
        scrollToTopTrigger: Int = 0,
        aiReportState: AIWeeklyReportState? = nil
    ) {
        self.profile = profile
        self.weightRecordStore = weightRecordStore
        self.scrollToTopTrigger = scrollToTopTrigger
        usesAutomaticAIAvailability = aiReportState == nil
        _aiReportState = State(
            initialValue: aiReportState
                ?? AIWeeklyReportAvailabilityService().currentState()
        )
        _viewModel = State(
            initialValue: HomeViewModel(
                profile: profile,
                mealRecordStore: mealRecordStore
            )
        )
    }

    var body: some View {
        // 홈 내용은 NoBounceScrollView 안의 별도 UIHostingController라, 라우터를 여기서 꺼내 넘긴다.
        let router = self.router
        return GeometryReader { geometry in
            NoBounceScrollView(
                scrollToTopTrigger: scrollToTopTrigger,
                immediateScrollToTopTrigger: reportDismissScrollToTopTrigger
            ) {
                LazyVStack(spacing: 0) {
                    HomeSummaryView(
                        viewModel: viewModel,
                        topInset: geometry.safeAreaInsets.top
                    ) {
                        isShowingNotificationNotice = true
                    }

                    if ExerciseGameFeature.isBannerEnabled {
                        // 운동 환산 화면이 스택에 있는 동안 배너 김을 멈춘다.
                        ExerciseGameBanner(isCovered: router.contains(.exerciseGame)) {
                            openExerciseGame(router)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 30)
                    }

                    reportSection(router)
                    .padding(.top, 30)

                    HomeSection(title: "주간 그래프") {
                        WeeklyCalorieChart(viewModel: viewModel)
                    }
                    .padding(.top, 31)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.gray01)
            .ignoresSafeArea(edges: .top)
        }
        .onAppear {
            viewModel.reload()
            refreshAIReportState()
        }
        .onChange(of: scrollToTopTrigger) {
            viewModel.reload()
            refreshAIReportState()
        }
        .alert("알림", isPresented: $isShowingNotificationNotice) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("알림 기능은 준비 중이에요.")
        }
    }

    /// 주간 리포트를 push한다. 버튼이든 스와이프든 빠지면 홈을 맨 위로 스크롤한다(reportDismissScrollToTopTrigger).
    private func openWeeklyReport(_ router: AppRouter) {
        router.push(.weeklyReport, onPop: { reportDismissScrollToTopTrigger += 1 }) { [viewModel, summary = weeklyReportSummary] in
            WeeklyReportView(viewModel: viewModel, summary: summary, onBack: { router.pop(.weeklyReport) })
        }
    }

    /// 운동 환산을 push한다. 체중은 여는 순간 값을 넘기고, 결과는 저장하지 않는다.
    private func openExerciseGame(_ router: AppRouter) {
        let weight = exerciseWeight
        router.push(.exerciseGame) {
            ExerciseGameView(
                weightKG: weight.kg,
                usesFallbackWeight: weight.isFallback,
                analyzer: ExerciseGameAnalyzer(),
                onClose: { router.pop(.exerciseGame) }
            )
        }
    }

    /// 운동 환산에 쓸 체중: 가장 최근 체중 기록 → 프로필 체중 → 65kg(#49). 읽기만 하고 기록을 만들지 않는다.
    private var exerciseWeight: (kg: Double, isFallback: Bool) {
        let latest = (try? weightRecordStore?.records(for: profile.kakaoUserID))?.last?.weightTenthsKG
        return ExerciseEquivalentCatalog.weight(latestRecordTenthsKG: latest, profileTenthsKG: profile.weightTenthsKG)
    }

    @ViewBuilder
    private func reportSection(_ router: AppRouter) -> some View {
        switch aiReportState {
        case .available(let message):
            HomeSection(
                title: "AI 건강 피드백",
                actionTitle: "주간 리포트",
                action: {
                    openWeeklyReport(router)
                }
            ) {
                AIWeeklyReportCard(message: message)
            }

        case .loading:
            HomeSection(
                title: "AI 건강 피드백",
                actionTitle: "주간 리포트",
                isActionDisabled: true,
                action: {}
            ) {
                AIWeeklyReportCard(
                    message: "이번 주 식단을 분석하고 있어요.",
                    isLoading: true
                )
            }

        case .unavailable:
            HomeSection(title: "건강 피드백") {
                HealthFeedbackCard(message: viewModel.feedbackMessage)
            }
        }
    }

    private func refreshAIReportState() {
        guard usesAutomaticAIAvailability else { return }
        guard aiReportAvailabilityService.currentState() != .unavailable else {
            cancelAIReportGeneration()
            aiReportState = .unavailable
            return
        }
        guard let input = viewModel.weeklyReportInput else {
            cancelAIReportGeneration()
            aiReportState = .noData
            return
        }

        if let cachedReport = aiWeeklyReportService.cachedReport(for: input) {
            cancelAIReportGeneration()
            aiReportState = .available(message: cachedReport)
        } else {
            generateAIWeeklyReport(for: input)
        }
    }

    private func generateAIWeeklyReport(for input: AIWeeklyReportInput) {
        reportGenerationTask?.cancel()
        let generationID = UUID()
        reportGenerationID = generationID
        withAnimation(.easeInOut(duration: 0.2)) {
            aiReportState = .loading
        }

        Task {
            try? await Task.sleep(for: .seconds(30))
            guard reportGenerationID == generationID else { return }

            reportGenerationTask?.cancel()
            reportGenerationID = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                aiReportState = .generationFailed
            }
        }

        reportGenerationTask = Task {
            do {
                let message = try await aiWeeklyReportService.generateReport(for: input)
                guard !Task.isCancelled, reportGenerationID == generationID else { return }
                reportGenerationID = nil
                reportGenerationTask = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    aiReportState = .available(message: message)
                }
            } catch {
                guard !Task.isCancelled, reportGenerationID == generationID else { return }
                reportGenerationID = nil
                reportGenerationTask = nil
                #if DEBUG
                print("AI weekly report failed: \(error.localizedDescription)")
                #endif
                withAnimation(.easeInOut(duration: 0.2)) {
                    aiReportState = .generationFailed
                }
            }
        }
    }

    private func cancelAIReportGeneration() {
        reportGenerationTask?.cancel()
        reportGenerationTask = nil
        reportGenerationID = nil
    }

    private var weeklyReportSummary: String {
        guard case .available(let message) = aiReportState else {
            return "식단 기록이 쌓이면 이번 주의 영양 흐름을 자세히 알려드릴게요."
        }
        return message
    }

}

/// 홈 섹션 오른쪽 캡슐 버튼(주간 리포트) 크기. Figma 개발 페이지 '홈'(2002:432) 기준.
private enum HomeSectionActionMetrics {
    static let size = CGSize(width: 96, height: 30)
    static let titleFontSize: CGFloat = 12
    static let iconSize: CGFloat = 12
    static let spacing: CGFloat = 4
    /// 버튼이 커져도 섹션 제목 줄 높이는 전 버튼 높이(26) 그대로 둬, 제목과 아래 카드 사이 간격(14)이 바뀌지 않게 한다.
    static let rowHeight: CGFloat = 26
}

private struct HomeSection<Content: View>: View {
    let title: String
    let actionTitle: String?
    let isActionLoading: Bool
    let isActionDisabled: Bool
    let action: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        title: String,
        actionTitle: String? = nil,
        isActionLoading: Bool = false,
        isActionDisabled: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.isActionLoading = isActionLoading
        self.isActionDisabled = isActionDisabled
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.pretendardSemiBold(16))
                    .foregroundStyle(Color.black01)

                Spacer()

                if let actionTitle, let action {
                    Button(action: action) {
                        HStack(spacing: HomeSectionActionMetrics.spacing) {
                            if isActionLoading {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(Color.black01)
                                    .frame(width: HomeSectionActionMetrics.iconSize, height: HomeSectionActionMetrics.iconSize)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: HomeSectionActionMetrics.iconSize, weight: .semibold))
                            }

                            Text(actionTitle)
                                .font(.pretendardBold(HomeSectionActionMetrics.titleFontSize))
                        }
                        .foregroundStyle(Color.black01)
                        .frame(width: HomeSectionActionMetrics.size.width, height: HomeSectionActionMetrics.size.height)
                        .background(Color.white, in: Capsule())
                        .overlay {
                            MeshGradient(
                                width: 3,
                                height: 3,
                                points: [
                                    [0, 0], [0.5, 0], [1, 0],
                                    [0, 0.5], [0.5, 0.5], [1, 0.5],
                                    [0, 1], [0.5, 1], [1, 1]
                                ],
                                colors: [
                                    Color(red: 1, green: 0.88, blue: 0.48),
                                    Color(red: 1, green: 0.63, blue: 0.18),
                                    Color(red: 1, green: 0.20, blue: 0.37),
                                    Color(red: 0.78, green: 0.93, blue: 0.88),
                                    Color(red: 0.83, green: 0.76, blue: 0.89),
                                    Color(red: 0.76, green: 0.31, blue: 0.86),
                                    Color(red: 0.40, green: 0.78, blue: 0.96),
                                    Color(red: 0.21, green: 0.53, blue: 1),
                                    Color(red: 0.55, green: 0.31, blue: 0.92)
                                ]
                            )
                            .mask {
                                Capsule()
                                    .strokeBorder(lineWidth: 3)
                            }
                        }
                        .overlay {
                            if isActionLoading || isActionDisabled {
                                Capsule()
                                    .fill(Color.gray03.opacity(0.65))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isActionLoading || isActionDisabled)
                    // 그려지는 크기는 30이지만 줄 높이는 26으로 두고 위아래 2씩 넘치게 해 제목·카드 위치를 그대로 둔다.
                    .padding(.vertical, (HomeSectionActionMetrics.rowHeight - HomeSectionActionMetrics.size.height) / 2)
                }
            }

            content
        }
        .padding(.horizontal, 16)
    }
}

#Preview("AI 지원") {
    HomeViewPreview(aiReportState: .mockAvailable)
}

#Preview("AI 생성 중") {
    HomeViewPreview(aiReportState: .loading)
}

#Preview("AI 미지원") {
    HomeViewPreview(aiReportState: .unavailable)
}

private struct HomeViewPreview: View {
    private let container: ModelContainer
    private let profile: UserProfile
    private let mealRecordStore: MealRecordStore
    private let aiReportState: AIWeeklyReportState

    init(aiReportState: AIWeeklyReportState) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: UserProfile.self,
            MealRecord.self,
            configurations: configuration
        )
        let calendar = Calendar.current
        let context = container.mainContext
        let profile = UserProfile(
            kakaoUserID: 1,
            nickname: "박정환",
            genderRawValue: Gender.male.rawValue,
            birthDate: calendar.date(from: DateComponents(year: 1998, month: 3, day: 15)),
            heightCM: 178,
            weightTenthsKG: 780,
            activityLevelRawValue: ActivityLevel.active.rawValue,
            hasCompletedOnboarding: true,
            createdAt: calendar.date(byAdding: .day, value: -12, to: .now) ?? .now
        )
        context.insert(profile)

        let calorieSamples = [4_800, 3_900, 2_200, 3_100, 900, 3_900, 4_600]
        for (index, calories) in calorieSamples.enumerated() {
            let dayOffset = index - 6
            let date = calendar.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
            let calorieValue = Double(calories)
            context.insert(
                MealRecord(
                    kakaoUserID: profile.kakaoUserID,
                    recordedAt: date,
                    calories: calorieValue,
                    carbohydrateGrams: calorieValue * 0.55 / 4,
                    proteinGrams: calorieValue * 0.175 / 4,
                    fatGrams: calorieValue * 0.275 / 9
                )
            )
        }
        try? context.save()

        self.container = container
        self.profile = profile
        self.aiReportState = aiReportState
        mealRecordStore = MealRecordStore(modelContext: context)
    }

    var body: some View {
        HomeView(
            profile: profile,
            mealRecordStore: mealRecordStore,
            aiReportState: aiReportState
        )
        .modelContainer(container)
    }
}
