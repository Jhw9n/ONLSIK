import SwiftUI

struct MealEntryView: View {
    let profile: UserProfile
    let recordedAt: Date
    let mealRecordStore: MealRecordStore
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MealEntryViewModel
    @State private var showsFoodSearch = false
    @State private var savedThroughSearch = false
    @FocusState private var isInputFocused: Bool
    private let isPreview: Bool

    init(
        profile: UserProfile,
        mealType: MealType,
        recordedAt: Date,
        mealRecordStore: MealRecordStore,
        onSaved: @escaping () -> Void
    ) {
        self.profile = profile
        self.recordedAt = recordedAt
        self.mealRecordStore = mealRecordStore
        self.onSaved = onSaved
        isPreview = false
        _viewModel = State(initialValue: MealEntryViewModel(mealType: mealType))
    }

    #if DEBUG
    init(previewModel: MealEntryViewModel) {
        profile = UserProfile(kakaoUserID: 0, nickname: "미리보기")
        recordedAt = .now
        mealRecordStore = .preview
        onSaved = {}
        isPreview = true
        _viewModel = State(initialValue: previewModel)
    }
    #endif

    private var isInputActive: Bool { isInputFocused || !viewModel.text.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    mealSelector
                    introduction
                        .padding(.top, 24)
                    inputCard
                        .padding(.top, 16)
                    resultSection
                        .padding(.top, 30)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .background(Color.gray01.ignoresSafeArea())
        .foregroundStyle(Color.black01)
        .preferredColorScheme(.light)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            recordingFooter
        }
        .task {
            guard !isPreview else { return }
            loadRecentMeals()
        }
        .onDisappear { viewModel.cancelAnalysis() }
        .fullScreenCover(isPresented: $showsFoodSearch, onDismiss: finishFoodSearch) {
            FoodSearchView(
                profile: profile,
                mealType: viewModel.mealType,
                recordedAt: recordedAt,
                mealRecordStore: mealRecordStore,
                onSaved: { savedThroughSearch = true }
            )
        }
        .alert("저장 안내", isPresented: Binding(
            get: { viewModel.saveError != nil },
            set: { if !$0 { viewModel.saveError = nil } }
        )) {
            Button("확인", role: .cancel) { viewModel.saveError = nil }
        } message: {
            Text(viewModel.saveError ?? "")
        }
    }

    private var header: some View {
        ZStack {
            Text("식사 기록")
                .font(.pretendardSemiBold(16))
                .foregroundStyle(Color("black02"))
            HStack {
                Button {
                    viewModel.cancelAnalysis()
                    dismiss()
                } label: {
                    Image("mealEntryBack")
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
    }

    private var recordingFooter: some View {
        VStack(spacing: 0) {
            if case .ready = viewModel.phase, !viewModel.items.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("예상 열량")
                        .font(.pretendardSemiBold(16))
                    Spacer()
                    Text(viewModel.invalidQuantityIDs.isEmpty
                         ? "약 \(viewModel.totalCalories.formatted(.number.precision(.fractionLength(0)))) kcal"
                         : "— kcal")
                        .font(.pretendardSemiBold(16))
                        .foregroundStyle(Color.black01)
                        .monospacedDigit()
                }
                .padding(.horizontal, 4)
                .padding(.top, 11)
                Text(isPreview ? "화면 확인용 예시이며 실제 기록에 저장되지 않아요" : "음식과 실제 분량에 따라 영양정보는 달라질 수 있어요")
                    .font(.pretendardMedium(12))
                    .foregroundStyle(Color.gray04)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                    .padding(.bottom, 16)
            }
            OnboardingBottomButton(
                title: "기록하기",
                isEnabled: viewModel.canSave,
                action: save,
                disabledForegroundColor: Color.gray02
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color.gray01)
    }

    private var mealSelector: some View {
        HStack(spacing: 0) {
            ForEach(MealType.allCases) { meal in
                Button {
                    viewModel.mealType = meal
                } label: {
                    Text(meal.title)
                        .font(.pretendardSemiBold(14))
                        .foregroundStyle(viewModel.mealType == meal ? Color.white : Color.black01)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if viewModel.mealType == meal {
                                RoundedRectangle(cornerRadius: 12).fill(Color.green03)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(viewModel.mealType == meal ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("무엇을 드셨나요?")
                .font(.pretendardBold(24))
                .tracking(-0.48)
                .frame(minHeight: 36)
            Text("먹은 음식과 양을 편하게 적어주세요")
                .font(.pretendardMedium(14))
                .foregroundStyle(Color.gray04)
                .frame(minHeight: 21)
        }
        .padding(.horizontal, 4)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI 식사 입력")
                .font(.pretendardSemiBold(12))
                .foregroundStyle(Color.green03)
                .frame(height: 22)

            TextField(
                "",
                text: Binding(get: { viewModel.text }, set: { viewModel.updateText($0) }),
                prompt: Text("ex) 김밥 한 줄이랑 라면").foregroundStyle(Color.gray04),
                axis: .vertical
            )
            .font(.pretendardMedium(14))
            .lineLimit(1...6)
            .frame(minHeight: 21)
            .focused($isInputFocused)
            .tint(Color.green03)
            .accessibilityLabel("먹은 음식과 양")
            .accessibilityIdentifier("mealEntryInput")

            HStack {
                Spacer()
                Button {
                    isInputFocused = false
                    viewModel.submit()
                } label: {
                    Image(viewModel.canSubmit ? "mealEntrySend" : "mealEntrySendDisabled")
                        .renderingMode(.original)
                        .frame(width: 40, height: 40)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSubmit)
                .accessibilityLabel("식사 분석하기")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .onTapGesture { isInputFocused = true }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isInputActive ? Color.green03 : Color.clear, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .compositingGroup()
        .shadow(color: Color.green03.opacity(isInputActive ? 0.12 : 0), radius: 12, y: 4)
        .animation(.easeOut(duration: 0.2), value: isInputActive)
    }

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.phase {
        case .idle:
            recentMealsSection
        case .analyzing:
            HStack(spacing: 12) {
                ProgressView().tint(Color.green03)
                Text("먹은 식사를 확인하고 있어요")
                    .font(.pretendardMedium(14))
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .accessibilityElement(children: .combine)
        case .question(let question):
            questionCard(question)
        case .ready:
            confirmationSection
        case .failed(let message):
            VStack(alignment: .leading, spacing: 16) {
                Text(message)
                    .font(.pretendardMedium(14))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 20) {
                    Button("다시 시도") { viewModel.submit() }
                    if !isPreview {
                        Button("음식 직접 검색") {
                            isInputFocused = false
                            showsFoodSearch = true
                        }
                    }
                }
                .font(.pretendardSemiBold(14))
                .foregroundStyle(Color.green03)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var recentMealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("최근 먹은 식사", subtitle: "다시 먹었다면 바로 선택하세요")
            if viewModel.recentMeals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.recentMealsFailed ? "최근 식사를 불러오지 못했어요" : "아직 기록한 식사가 없어요")
                        .font(.pretendardSemiBold(14))
                    Text("식사를 기록하면 여기에 모아둘게요")
                        .font(.pretendardMedium(12))
                        .foregroundStyle(Color.gray04)
                    if viewModel.recentMealsFailed {
                        Button("다시 불러오기", action: loadRecentMeals)
                            .font(.pretendardSemiBold(14))
                            .foregroundStyle(Color.green03)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            } else {
                List {
                    ForEach(viewModel.recentMeals) { meal in
                        Button {
                            isInputFocused = false
                            viewModel.selectRecent(meal)
                        } label: {
                            HStack(spacing: 12) {
                                Text(meal.title)
                                    .font(.pretendardSemiBold(14))
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                                Image("mealEntryPlus")
                                    .frame(width: 12, height: 12)
                                    .frame(width: 20, height: 20)
                                    .background(Color.gray02, in: Circle())
                                    .shadow(color: .black.opacity(0.05), radius: 2, y: 2)
                            }
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(meal.title) 다시 기록하기")
                        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                        .listRowBackground(Color.white)
                        .listRowSeparatorTint(Color.gray02.opacity(0.7))
                        .listRowSeparator(meal.id == viewModel.recentMeals.last?.id ? .hidden : .visible, edges: .bottom)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 61)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(viewModel.recentMeals.count) * 61)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.pretendardBold(16))
                .frame(minHeight: 24)
            Text(subtitle)
                .font(.pretendardMedium(14))
                .foregroundStyle(Color.gray04)
                .frame(minHeight: 21)
        }
        .padding(.horizontal, 4)
    }

    private func questionCard(_ question: MealEntryQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(question.title, subtitle: question.explanation)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(question.choices) { choice in
                    Button(choice.title) { viewModel.select(choice) }
                        .font(.pretendardSemiBold(14))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var confirmationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("이렇게 기록할까요?", subtitle: "먹은 양이 다르면 여기서 바꿔주세요")
            ForEach(viewModel.items) { item in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.food.name)
                                .font(.pretendardSemiBold(16))
                                .frame(minHeight: 24)
                            Text(item.amountDescription)
                                .font(.pretendardMedium(14))
                                .foregroundStyle(Color.gray04)
                        }
                        Spacer()
                        Button {
                            viewModel.remove(item.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.gray04)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(height: 24)
                        .accessibilityLabel("\(item.food.name) 제외")
                    }
                    MealEntryQuantityControl(item: item) { quantity in
                        viewModel.setQuantity(quantity, for: item.id)
                    }
                }
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func loadRecentMeals() {
        viewModel.loadRecentMeals(store: mealRecordStore, userID: profile.kakaoUserID, date: recordedAt)
    }

    private func save() {
        guard !isPreview else {
            viewModel.updateText("")
            return
        }
        if viewModel.save(store: mealRecordStore, userID: profile.kakaoUserID, date: recordedAt) {
            onSaved()
            dismiss()
        }
    }

    private func finishFoodSearch() {
        guard savedThroughSearch else { return }
        onSaved()
        dismiss()
    }
}
