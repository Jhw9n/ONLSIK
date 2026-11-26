import SwiftUI

struct MealEntryView: View {
    let profile: UserProfile
    let recordedAt: Date
    let mealRecordStore: MealRecordStore
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appRouter) private var router
    @State private var viewModel: MealEntryViewModel
    @State private var savedThroughSearch = false
    @State private var footerHeight: CGFloat = 0
    @FocusState private var focusedRowID: UUID?
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

    private var isInputActive: Bool { focusedRowID != nil || !viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack(alignment: .bottom) {
            mealContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: footerHeight)
                }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                recordingFooter
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        footerHeight = height
                    }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .background(Color.gray01.ignoresSafeArea())
        .dismissMealEntryKeyboardOnOutsideTap()
        .foregroundStyle(Color.black01)
        .preferredColorScheme(.light)
        .task {
            guard !isPreview else { return }
            loadRecentMeals()
        }
        .onDisappear {
            viewModel.cancelAnalysis()
            // 보여 준 질문에 답하지 않고 화면을 닫았으면 검색 개선 기록에 "응답 없음"으로 남긴다(#51)
            viewModel.flushPendingSearchLog()
        }
        // 저장 중·AI 분석 중에는 스와이프 뒤로가기를 막는다(뒤로가기 버튼은 지금처럼 분석을 취소하고 닫는다).
        .popGestureDisabled(!canSwipeBack)
        .alert("안내", isPresented: Binding(
            get: { viewModel.saveError != nil },
            set: { if !$0 { viewModel.saveError = nil } }
        )) {
            Button("확인", role: .cancel) { viewModel.saveError = nil }
        } message: {
            Text(viewModel.saveError ?? "")
        }
    }

    private var mealContent: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
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
                .onChange(of: focusedRowID) { _, rowID in
                    guard let rowID else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(rowID, anchor: .center) }
                }
                .onChange(of: viewModel.failedRowID) { _, rowID in
                    guard let rowID else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(rowID, anchor: .center) }
                }
            }
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
                         ? MealEntryViewModel.calorieText(viewModel.displayedTotalCalories)
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
            Text("한 줄에 음식 하나와 대략적인 양을 꼭 입력해주세요")
                .font(.pretendardMedium(14))
                .foregroundStyle(Color.gray04)
                .frame(minHeight: 21)
        }
        .padding(.horizontal, 4)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Text("AI 식사 입력")
                    .font(.pretendardSemiBold(12))
                Spacer()
                Text("\(viewModel.inputRows.count)/8")
                    .font(.pretendardMedium(11))
                    .foregroundStyle(Color.gray04)
                    .monospacedDigit()
                    .accessibilityLabel("입력칸 \(viewModel.inputRows.count)개, 최대 8개")
            }
            .foregroundStyle(Color.green03)
            .padding(.bottom, 10)

            ForEach(Array(viewModel.inputRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Color.gray02.opacity(0.6))
                        .frame(height: 1)
                        .padding(.leading, 36)
                }
                inputRow(row, index: index)
                    .id(row.id)
            }

            HStack(spacing: 12) {
                Button {
                    if let rowID = viewModel.addRow() { focusedRowID = rowID }
                } label: {
                    Label("음식 추가", systemImage: "plus")
                        .font(.pretendardSemiBold(13))
                        .foregroundStyle(viewModel.canAddRow ? Color.green03 : Color.gray04)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canAddRow)
                .accessibilityIdentifier("mealEntryAddRow")
                Spacer(minLength: 4)
                Button {
                    focusedRowID = nil
                    viewModel.submit()
                } label: {
                    HStack(spacing: 6) {
                        Text("분석하기")
                            .font(.pretendardSemiBold(13))
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(viewModel.canSubmit ? Color.white : Color.gray04)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(viewModel.canSubmit ? Color.green03 : Color.gray01, in: Capsule())
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSubmit)
                .accessibilityLabel("식사 분석하기")
            }
            .padding(.top, 10)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isInputActive ? Color.green03 : Color.clear, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .compositingGroup()
        .shadow(color: Color.green03.opacity(isInputActive ? 0.12 : 0), radius: 12, y: 4)
        .animation(.easeOut(duration: 0.2), value: isInputActive)
        .mealEntryInputRegion()
    }

    private func inputRow(_ row: MealEntryViewModel.InputRow, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Group {
                    if viewModel.isRowComplete(row.id) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                    } else {
                        Text("\(index + 1)")
                            .font(.pretendardSemiBold(12))
                    }
                }
                .foregroundStyle(focusedRowID == row.id || viewModel.isRowComplete(row.id) ? Color.white : Color.gray05)
                .frame(width: 26, height: 26)
                .background(focusedRowID == row.id || viewModel.isRowComplete(row.id) ? Color.green03 : Color.gray02.opacity(0.4), in: Circle())
                .accessibilityLabel(viewModel.isRowComplete(row.id) ? "분석 완료" : "\(index + 1)번째 음식")

                TextField("", text: Binding(
                    get: { viewModel.inputRows.first(where: { $0.id == row.id })?.text ?? "" },
                    set: { value in
                        if let nextID = viewModel.updateRow(row.id, text: value) { focusedRowID = nextID }
                    }
                ), prompt: Text(inputPlaceholder(at: index)).foregroundStyle(Color.gray04))
                .font(.pretendardMedium(14))
                .tint(Color.green03)
                .focused($focusedRowID, equals: row.id)
                .submitLabel(.next)
                .onSubmit {
                    if let nextID = viewModel.addRow(after: row.id) { focusedRowID = nextID }
                }
                .accessibilityLabel("\(index + 1)번째 먹은 음식과 양")
                .accessibilityIdentifier("mealEntryInput_\(index)")

                if viewModel.inputRows.count > 1 || !row.text.isEmpty {
                    Button {
                        let wasFocused = focusedRowID == row.id
                        let nextID = viewModel.removeRow(row.id)
                        if wasFocused { focusedRowID = nextID }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.gray04)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(index + 1)번째 음식 입력 삭제")
                }
            }
            .frame(minHeight: 54)

            if viewModel.failedRowID == row.id, case .failed(let message) = viewModel.phase {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.red02)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message)
                        if viewModel.showsSplitHint {
                            Text("여러 음식을 적었다면 한 줄씩 나눠주세요.")
                        }
                    }
                }
                .font(.pretendardMedium(13))
                .foregroundStyle(Color.black02)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red01, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 12)
            }
        }
    }

    private func inputPlaceholder(at index: Int) -> String {
        let examples = ["ex) 김밥 반 줄", "ex) 밥 한 공기", "ex) 계란 두 개"]
        return examples[index % examples.count]
    }

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.phase {
        case .idle:
            if viewModel.items.isEmpty {
                recentMealsSection
            } else {
                confirmationSection
            }
        case .analyzing:
            HStack(spacing: 12) {
                ProgressView().tint(Color.green03)
                Text("\(activeRowNumber.map { "\($0)번째 음식을" } ?? "먹은 식사를") 확인하고 있어요")
                    .font(.pretendardMedium(14))
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .accessibilityElement(children: .combine)
        case .question(let question):
            VStack(alignment: .leading, spacing: 10) {
                if let number = activeRowNumber {
                    Text("\(number)번째 음식 확인")
                        .font(.pretendardSemiBold(12))
                        .foregroundStyle(Color.green03)
                        .padding(.horizontal, 4)
                }
                questionCard(question)
            }
        case .ready:
            confirmationSection
        case .failed(let message):
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.failedRowID == nil {
                    Text(message)
                        .font(.pretendardMedium(14))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 20) {
                    Button("다시 시도") { viewModel.retry() }
                    if !isPreview {
                        Button("음식 직접 검색") {
                            focusedRowID = nil
                            openFoodSearch()
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
                            focusedRowID = nil
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

    private var activeRowNumber: Int? {
        viewModel.inputRows.firstIndex(where: { $0.id == viewModel.activeRowID }).map { $0 + 1 }
    }

    private func questionCard(_ question: MealEntryQuestion) -> some View {
        let fullWidth = question.choices.count == 1 || question.choices.contains { $0.subtitle != nil }
        let householdPortion = question.clarification?.portionInput != nil
        let columns = Array(repeating: GridItem(.flexible()), count: fullWidth ? 1 : 2)
        return VStack(alignment: .leading, spacing: 16) {
            sectionHeading(question.title, subtitle: question.explanation)
            if question.clarification != nil && !householdPortion {
                MealEntryClarificationInput(placeholder: question.inputPlaceholder, onSubmit: viewModel.answer)
                    .id(question.id)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(question.choices) { choice in
                    Button { viewModel.select(choice) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: fullWidth ? .leading : .center, spacing: 6) {
                                Text(choice.title)
                                    .font(.pretendardSemiBold(fullWidth ? 16 : 14))
                                    .fixedSize(horizontal: false, vertical: true)
                                if let subtitle = choice.subtitle {
                                    Text(subtitle)
                                        .font(.pretendardMedium(13))
                                        .foregroundStyle(Color.gray04)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: fullWidth ? .leading : .center)
                            if fullWidth {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.gray04)
                            }
                        }
                        .multilineTextAlignment(fullWidth ? .leading : .center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, fullWidth ? 18 : 12)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            if householdPortion {
                MealEntryClarificationInput(placeholder: question.inputPlaceholder, onSubmit: viewModel.answer)
                    .id(question.id)
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
                            HStack(spacing: 6) {
                                Text(item.amountDescription)
                                    .foregroundStyle(Color.gray04)
                                Text(viewModel.invalidQuantityIDs.contains(item.id)
                                     ? "— kcal" : MealEntryViewModel.calorieText(item.displayedCalories))
                                    .foregroundStyle(Color.black01)
                                    .monospacedDigit()
                                    .accessibilityLabel(viewModel.invalidQuantityIDs.contains(item.id)
                                        ? "열량 계산 불가" : "\(item.food.name) 열량 \(MealEntryViewModel.calorieText(item.displayedCalories))")
                            }
                            .font(.pretendardMedium(14))
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

    private var canSwipeBack: Bool {
        if viewModel.isSaving { return false }
        if case .analyzing = viewModel.phase { return false }
        return true
    }

    /// 음식 검색을 push한다. 검색에서 저장한 뒤 검색이 빠지면 식사 기록도 닫는다(전의 onDismiss: finishFoodSearch).
    private func openFoodSearch() {
        router.push(.foodSearch, onPop: { finishFoodSearch() }) { [profile, recordedAt, mealRecordStore, mealType = viewModel.mealType] in
            FoodSearchView(
                profile: profile,
                mealType: mealType,
                recordedAt: recordedAt,
                mealRecordStore: mealRecordStore,
                onSaved: { savedThroughSearch = true }
            )
        }
    }

    private func finishFoodSearch() {
        guard savedThroughSearch else { return }
        onSaved()
        dismiss()
    }
}

private struct MealEntryClarificationInput: View {
    let placeholder: String
    let onSubmit: (String) -> Void
    @State private var details = ""
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && details.count <= 200
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(placeholder, text: $details, axis: .vertical)
                .font(.pretendardMedium(14))
                .lineLimit(1...3)
                .focused($isFocused)
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("음식 추가 설명")
                .mealEntryInputRegion()
            if details.count > 200 {
                Text("200자 이내로 적어주세요")
                    .font(.pretendardMedium(12))
                    .foregroundStyle(Color.red01)
            }
            Button {
                isFocused = false
                onSubmit(details)
            } label: {
                Text("확인")
                    .font(.pretendardSemiBold(14))
                    .foregroundStyle(canSubmit ? Color.white : Color.gray04)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(canSubmit ? Color.green03 : Color.gray02, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
    }
}
