import SwiftData
import SwiftUI

struct RecordView: View {
    @State private var viewModel: RecordViewModel
    @State private var detailMealType: MealType?
    @State private var searchMealType: MealType?

    private let mealRecordStore: MealRecordStore

    init(profile: UserProfile, mealRecordStore: MealRecordStore) {
        self.mealRecordStore = mealRecordStore
        _viewModel = State(
            initialValue: RecordViewModel(
                profile: profile,
                mealRecordStore: mealRecordStore
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            NoBounceScrollView {
                VStack(spacing: 0) {
                    calendarHeader

                    RecordDateSelector(viewModel: viewModel)
                        .padding(.top, 8)

                    nutritionSummary
                        .padding(.top, 20)

                    mealList(height: max(286, geometry.size.height - 397))
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                }
            }
        }
        .background(Color.gray01)
        .onAppear {
            viewModel.reload()
        }
        .sheet(item: $detailMealType) { mealType in
            MealDetailView(
                mealType: mealType,
                dateText: viewModel.dateText(viewModel.selectedDate),
                records: viewModel.records(for: mealType),
                onClose: { detailMealType = nil },
                onDelete: viewModel.delete
            )
            .presentationDetents([.fraction(0.86)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(20)
        }
        .fullScreenCover(item: $searchMealType, onDismiss: viewModel.reload) { mealType in
            MealEntryPresentation(
                profile: viewModel.profile,
                mealType: mealType,
                recordedAt: viewModel.selectedDate,
                mealRecordStore: mealRecordStore,
                onSaved: viewModel.reload
            )
        }
    }

    private var calendarHeader: some View {
        HStack {
            monthButton(systemName: "chevron.left", offset: -1)

            Spacer()

            Text(viewModel.monthTitle)
                .font(.pretendardMedium(16))
                .foregroundStyle(Color(red: 33 / 255, green: 33 / 255, blue: 47 / 255))

            Spacer()

            monthButton(systemName: "chevron.right", offset: 1)
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    private func monthButton(systemName: String, offset: Int) -> some View {
        let isEnabled = offset < 0 || viewModel.canMoveForward

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                viewModel.moveMonth(by: offset)
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.gray03)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var nutritionSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(viewModel.totalNutrition.calories, format: .number.precision(.fractionLength(0)))
                    .font(.pretendardSemiBold(36))

                Text("kcal")
                    .font(.pretendardSemiBold(24))
            }

            Text("권장 섭취량 : \(formatted(viewModel.recommendation.calories)) kcal")
                .font(.pretendardBold(14))
                .padding(.top, 4)

            RecordProgressBar(
                progress: viewModel.calorieProgress,
                foregroundColor: .green02,
                backgroundColor: .white,
                height: 10
            )
            .padding(.top, 8)

            HStack(spacing: 8) {
                nutrientCard(
                    title: "탄수화물",
                    consumed: viewModel.totalNutrition.carbohydrateGrams,
                    recommended: viewModel.recommendation.carbohydrateGrams
                )
                nutrientCard(
                    title: "단백질",
                    consumed: viewModel.totalNutrition.proteinGrams,
                    recommended: viewModel.recommendation.proteinGrams
                )
                nutrientCard(
                    title: "지방",
                    consumed: viewModel.totalNutrition.fatGrams,
                    recommended: viewModel.recommendation.fatGrams
                )
            }
            .padding(.top, 14)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(height: 219, alignment: .top)
        .background(Color.green03, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func nutrientCard(
        title: String,
        consumed: Double,
        recommended: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.pretendardSemiBold(14))

            HStack(spacing: 2) {
                Text(formatted(consumed))
                    .foregroundStyle(Color.black01)
                Text("/")
                    .foregroundStyle(Color.black01)
                Text("\(formatted(recommended))g")
                    .foregroundStyle(Color.gray03)
            }
            .font(.pretendardBold(13))
            .padding(.top, 4)

            Spacer(minLength: 5)

            RecordProgressBar(
                progress: viewModel.progress(consumed: consumed, recommended: recommended),
                foregroundColor: .green03,
                backgroundColor: Color(red: 232 / 255, green: 233 / 255, blue: 236 / 255)
            )
        }
        .foregroundStyle(Color.black01)
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func mealList(height: CGFloat) -> some View {
        let rowHeight = (height - CGFloat(MealType.allCases.count - 1))
            / CGFloat(MealType.allCases.count)

        return VStack(spacing: 0) {
            ForEach(MealType.allCases) { mealType in
                mealRow(mealType, height: rowHeight)

                if mealType != MealType.allCases.last {
                    Rectangle()
                        .fill(Color.gray02.opacity(0.65))
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                }
            }
        }
        .frame(height: height)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func mealRow(_ mealType: MealType, height: CGFloat) -> some View {
        let nutrition = viewModel.nutrition(for: mealType)
        let targetCalories = viewModel.targetCalories(for: mealType)

        return HStack(spacing: 0) {
            Button {
                detailMealType = mealType
            } label: {
                HStack(spacing: 14) {
                    mealProgressIcon(
                        mealType: mealType,
                        progress: viewModel.progress(
                            consumed: nutrition.calories,
                            recommended: targetCalories
                        )
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(mealType.title)
                            .font(.pretendardSemiBold(14))

                        HStack(spacing: 2) {
                            Text(formatted(nutrition.calories))
                                .foregroundStyle(Color.black01)
                            Text("/")
                                .foregroundStyle(Color.black01)
                            Text("\(formatted(targetCalories))kcal")
                                .foregroundStyle(Color.gray03)
                        }
                        .font(.pretendardBold(13))
                    }

                    Spacer()
                }
                .foregroundStyle(Color.black01)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity)
                .frame(height: height)
            }
            .buttonStyle(.plain)
            .accessibilityHint("\(mealType.title) 기록 상세 보기")

            Button {
                searchMealType = mealType
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 20, height: 20)
                    .background(Color.green03, in: Circle())
                    .frame(width: 44, height: height)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(mealType.title) 음식 추가")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: height)
    }

    private func mealProgressIcon(mealType: MealType, progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(
                    Color(red: 232 / 255, green: 233 / 255, blue: 236 / 255),
                    lineWidth: 5
                )

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.green03, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(mealType.iconAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: mealType.iconSize.width, height: mealType.iconSize.height)
        }
        .frame(width: 48, height: 48)
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

private struct RecordDateSelector: View {
    let viewModel: RecordViewModel

    @State private var contentOffset: CGFloat = 0
    @State private var requestedDayOffset = 0
    @State private var appliedDayOffset = 0
    @State private var isAnimatingDateSelection = false

    private let horizontalPadding: CGFloat = 16
    private let daySpacing: CGFloat = 8
    private let minimumDayItemWidth: CGFloat = 42

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - horizontalPadding * 2)
            let dayItemWidth = max(
                minimumDayItemWidth,
                (contentWidth - daySpacing * 6) / 7
            )
            let dayWidth = dayItemWidth + daySpacing

            ZStack {
                dateButtons(dayItemWidth: dayItemWidth, dayWidth: dayWidth)
                    .offset(x: contentOffset)

                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.green03)
                    .frame(width: dayItemWidth, height: 58)
                    .allowsHitTesting(false)

                dateTexts(
                    weekdayColor: .white,
                    dayColor: .white,
                    dayItemWidth: dayItemWidth
                )
                .offset(x: contentOffset)
                .mask {
                    RoundedRectangle(cornerRadius: 16)
                        .frame(width: dayItemWidth, height: 58)
                }
                .allowsHitTesting(false)
            }
            .frame(width: contentWidth, height: 58)
            .clipped()
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(dateDragGesture(dayWidth: dayWidth))
        }
        .frame(height: 58)
        .sensoryFeedback(.selection, trigger: viewModel.selectedDate)
    }

    private func dateButtons(dayItemWidth: CGFloat, dayWidth: CGFloat) -> some View {
        HStack(spacing: daySpacing) {
            ForEach(Array(viewModel.visibleDates.enumerated()), id: \.offset) { index, date in
                let offset = index - viewModel.visibleDates.count / 2
                let isSelectable = viewModel.isSelectable(date)

                Button {
                    guard offset != 0 else { return }
                    moveSelectedDate(by: offset, dayWidth: dayWidth)
                } label: {
                    dateText(
                        for: date,
                        weekdayColor: Color.gray03,
                        dayColor: isSelectable ? Color.black01 : Color.black01.opacity(0.6)
                    )
                    .frame(width: dayItemWidth, height: 58)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(!isSelectable || isAnimatingDateSelection)
            }
        }
    }

    private func dateTexts(
        weekdayColor: Color,
        dayColor: Color,
        dayItemWidth: CGFloat
    ) -> some View {
        HStack(spacing: daySpacing) {
            ForEach(Array(viewModel.visibleDates.enumerated()), id: \.offset) { _, date in
                dateText(for: date, weekdayColor: weekdayColor, dayColor: dayColor)
                    .frame(width: dayItemWidth, height: 58)
            }
        }
    }

    private func dateText(
        for date: Date,
        weekdayColor: Color,
        dayColor: Color
    ) -> some View {
        VStack(spacing: 3) {
            Text(viewModel.weekday(for: date))
                .font(.pretendardMedium(12))
                .foregroundStyle(weekdayColor)

            Text(viewModel.day(for: date))
                .font(.pretendardSemiBold(14))
                .foregroundStyle(dayColor)
        }
    }

    private func dateDragGesture(dayWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !isAnimatingDateSelection else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                updateDrag(translation: value.translation.width, dayWidth: dayWidth)
            }
            .onEnded { _ in
                guard !isAnimatingDateSelection else { return }
                resetDrag()
            }
    }

    private func updateDrag(translation: CGFloat, dayWidth: CGFloat) {
        let nextRequestedOffset = Int((-translation / dayWidth).rounded())

        if nextRequestedOffset != requestedDayOffset {
            requestedDayOffset = nextRequestedOffset
            let remainingOffset = nextRequestedOffset - appliedDayOffset
            appliedDayOffset += viewModel.moveDay(by: remainingOffset)
        }

        let proposedOffset = translation + CGFloat(appliedDayOffset) * dayWidth
        contentOffset = nextRequestedOffset > appliedDayOffset
            ? max(proposedOffset, -4)
            : proposedOffset
    }

    private func moveSelectedDate(by value: Int, dayWidth: CGFloat) {
        guard value != 0, !isAnimatingDateSelection else { return }

        isAnimatingDateSelection = true

        withAnimation(.smooth(duration: 0.28)) {
            contentOffset = CGFloat(-value) * dayWidth
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                viewModel.moveDay(by: value)
                contentOffset = 0
                requestedDayOffset = 0
                appliedDayOffset = 0
                isAnimatingDateSelection = false
            }
        }
    }

    private func resetDrag() {
        withAnimation(.smooth(duration: 0.25)) {
            contentOffset = 0
        }
        requestedDayOffset = 0
        appliedDayOffset = 0
    }
}

private struct RecordProgressBar: View {
    let progress: Double
    let foregroundColor: Color
    let backgroundColor: Color
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(backgroundColor)

                RoundedRectangle(cornerRadius: 3)
                    .fill(foregroundColor)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: height)
    }
}

#Preview {
    RecordViewPreview()
}

private struct RecordViewPreview: View {
    private let container: ModelContainer
    private let profile: UserProfile
    private let mealRecordStore: MealRecordStore

    init() {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: UserProfile.self,
            MealRecord.self,
            configurations: configuration
        )
        let context = container.mainContext
        let profile = UserProfile(
            kakaoUserID: 1,
            nickname: "박정환",
            genderRawValue: Gender.male.rawValue,
            birthDate: Calendar.current.date(from: DateComponents(year: 1998, month: 3, day: 15)),
            heightCM: 178,
            weightTenthsKG: 741,
            activityLevelRawValue: ActivityLevel.moderate.rawValue,
            hasCompletedOnboarding: true
        )
        context.insert(profile)

        let store = MealRecordStore(modelContext: context)
        let food = FoodCatalogService.previewFood
        try? store.insert(
            food: food,
            servingCount: 1,
            mealType: .breakfast,
            recordedAt: .now,
            kakaoUserID: profile.kakaoUserID
        )

        self.container = container
        self.profile = profile
        mealRecordStore = store
    }

    var body: some View {
        RecordView(profile: profile, mealRecordStore: mealRecordStore)
            .modelContainer(container)
    }
}
