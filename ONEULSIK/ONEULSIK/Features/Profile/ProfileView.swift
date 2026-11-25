import SwiftData
import SwiftUI

struct ProfileView: View {
    @State private var viewModel: ProfileViewModel

    private let onboardingStore: OnboardingStore
    private let onDeleteAccount: () async -> Bool
    private let onLogout: () -> Void
    @Environment(\.appRouter) private var router

    init(
        profile: UserProfile,
        onboardingStore: OnboardingStore,
        weightRecordStore: WeightRecordStore,
        onDeleteAccount: @escaping () async -> Bool,
        onLogout: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: ProfileViewModel(
                profile: profile,
                weightRecordStore: weightRecordStore
            )
        )
        self.onboardingStore = onboardingStore
        self.onDeleteAccount = onDeleteAccount
        self.onLogout = onLogout
    }

    var body: some View {
        GeometryReader { geometry in
            let topSpacing = additionalTopSpacing(for: geometry)
            let chartHeight = max(158, geometry.size.height - 527 - topSpacing)

            NoBounceScrollView {
                VStack(spacing: 0) {
                    header
                    greeting
                        .padding(.top, -16 + topSpacing)

                    profileInformationCard
                        .padding(.top, 21)

                    weightFeedbackCard
                        .padding(.top, 16)

                    weightChartSection(chartHeight: chartHeight)
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                }
            }
        }
        .background(Color.gray01)
        .onAppear {
            viewModel.reload()
        }
    }

    /// 설정을 push한다. 로그아웃은 스택을 비우고 지금처럼 로그인 화면으로 간다.
    private func openSettings() {
        let router = self.router
        router.push(.settings) { [onLogout, onDeleteAccount] in
            SettingsView(
                onBack: { router.pop(.settings) },
                onLogout: {
                    router.popToRoot()
                    onLogout()
                },
                onDeleteAccount: onDeleteAccount
            )
        }
    }

    /// 나의 정보 수정 항목 화면을 push한다. 저장·뒤로가기 모두 pop, 저장하면 값을 다시 읽는다.
    private func openEditor(_ field: ProfileField) {
        router.push(.profileEdit(field.rawValue)) {
            editView(for: field)
        }
    }

    private func additionalTopSpacing(for geometry: GeometryProxy) -> CGFloat {
        min(max(geometry.safeAreaInsets.top - 44, 0), 12)
    }

    private var header: some View {
        HStack {
            Spacer()

            Button {
                openSettings()
            } label: {
                Image("profileSetting")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("설정")
        }
        .frame(height: 56)
        .padding(.trailing, 4)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Text(viewModel.profile.nickname)
                    .foregroundStyle(Color.green03)

                Text("님")
                    .foregroundStyle(Color(red: 70 / 255, green: 70 / 255, blue: 86 / 255))
            }

            Text("오늘도 건강하세요!")
                .foregroundStyle(Color(red: 70 / 255, green: 70 / 255, blue: 86 / 255))
        }
        .font(.pretendardSemiBold(24))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private var profileInformationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("나의 정보")
                .font(.pretendardBold(14))
                .foregroundStyle(Color.black01)
                .frame(height: 34, alignment: .bottomLeading)
                .padding(.bottom, 6)

            profileRow(.gender, value: viewModel.genderText)
            profileRow(.birthday, value: viewModel.birthDateText)
            profileRow(.height, value: viewModel.heightText)
            profileRow(.weight, value: viewModel.weightText, isHighlighted: true)
            profileRow(.activity, value: viewModel.activityText)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 209, alignment: .top)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func profileRow(
        _ field: ProfileField,
        value: String,
        isHighlighted: Bool = false
    ) -> some View {
        Button {
            openEditor(field)
        } label: {
            HStack(spacing: 10) {
                Text(field.title)
                    .foregroundStyle(Color.black01)

                Spacer()

                Text(value)
                    .font(isHighlighted ? .pretendardSemiBold(14) : .pretendardMedium(14))
                    .foregroundStyle(isHighlighted ? Color.green03 : Color.black01)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.gray02)
            }
            .font(.pretendardMedium(14))
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("\(field.title) 수정")
    }

    private var weightFeedbackCard: some View {
        HStack(spacing: 16) {
            Image("healthFeedbackCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)

            Text(viewModel.feedbackMessage)
                .font(.pretendardSemiBold(14))
                .foregroundStyle(Color.white)
                .lineSpacing(4)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .background(Color.green03, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func weightChartSection(chartHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("체중 변화")
                .font(.pretendardSemiBold(16))
                .foregroundStyle(Color.black01)

            WeightChangeChart(
                points: viewModel.weeklyWeightPoints,
                height: chartHeight
            )
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func editView(for field: ProfileField) -> some View {
        switch field {
        case .gender:
            GenderOnboardingView(
                profile: viewModel.profile,
                onboardingStore: onboardingStore,
                primaryButtonTitle: "저장",
                onBack: closeEditor,
                onNext: finishEditing
            )

        case .birthday:
            BirthdayOnboardingView(
                profile: viewModel.profile,
                onboardingStore: onboardingStore,
                primaryButtonTitle: "저장",
                onBack: closeEditor,
                onNext: finishEditing
            )

        case .height:
            HeightOnboardingView(
                profile: viewModel.profile,
                onboardingStore: onboardingStore,
                primaryButtonTitle: "저장",
                onBack: closeEditor,
                onNext: finishEditing
            )

        case .weight:
            WeightOnboardingView(
                profile: viewModel.profile,
                onboardingStore: onboardingStore,
                primaryButtonTitle: "저장",
                onBack: closeEditor,
                onNext: finishEditing
            )

        case .activity:
            ActivityOnboardingView(
                profile: viewModel.profile,
                onboardingStore: onboardingStore,
                primaryButtonTitle: "저장",
                onBack: closeEditor,
                onComplete: finishEditing
            )
        }
    }

    private func closeEditor() {
        popEditor()
    }

    private func finishEditing() {
        viewModel.reload()
        popEditor()
    }

    /// 맨 위가 항목 화면이면 내린다.
    private func popEditor() {
        if case .profileEdit = router.path.last?.route { router.pop() }
    }
}

private enum ProfileField: String, Identifiable {
    case gender
    case birthday
    case height
    case weight
    case activity

    var id: Self { self }

    var title: String {
        switch self {
        case .gender: "성별"
        case .birthday: "생년월일"
        case .height: "키"
        case .weight: "몸무게"
        case .activity: "활동수준"
        }
    }
}

#Preview {
    ProfileViewPreview()
}

private struct ProfileViewPreview: View {
    private let container: ModelContainer
    private let profile: UserProfile
    private let onboardingStore: OnboardingStore
    private let weightRecordStore: WeightRecordStore

    init() {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: UserProfile.self,
            WeightRecord.self,
            configurations: configuration
        )
        let calendar = Calendar.current
        let context = container.mainContext
        let profile = UserProfile(
            kakaoUserID: 1,
            nickname: "박정환",
            genderRawValue: Gender.male.rawValue,
            birthDate: calendar.date(from: DateComponents(year: 2007, month: 9, day: 12)),
            heightCM: 178,
            weightTenthsKG: 741,
            activityLevelRawValue: ActivityLevel.moderate.rawValue,
            hasCompletedOnboarding: true,
            createdAt: calendar.date(byAdding: .weekOfYear, value: -5, to: .now) ?? .now
        )
        context.insert(profile)

        let weights = [756, 744, 752, 752, 740, 741]
        for (index, weight) in weights.enumerated() {
            let weekOffset = index - 5
            let date = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: .now) ?? .now
            context.insert(
                WeightRecord(
                    kakaoUserID: profile.kakaoUserID,
                    recordedAt: date,
                    weightTenthsKG: weight
                )
            )
        }
        try? context.save()

        self.container = container
        self.profile = profile
        onboardingStore = OnboardingStore(modelContext: context)
        weightRecordStore = WeightRecordStore(modelContext: context)
    }

    var body: some View {
        ProfileView(
            profile: profile,
            onboardingStore: onboardingStore,
            weightRecordStore: weightRecordStore,
            onDeleteAccount: { true },
            onLogout: {}
        )
        .modelContainer(container)
    }
}
