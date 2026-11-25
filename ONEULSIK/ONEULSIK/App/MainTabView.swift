import SwiftData
import SwiftUI

struct MainTabView: View {
    let profile: UserProfile
    let mealRecordStore: MealRecordStore
    let onboardingStore: OnboardingStore
    let weightRecordStore: WeightRecordStore
    let onDeleteAccount: () async -> Bool
    let onLogout: () -> Void

    @State private var selectedTab = MainTab.home
    @State private var homeScrollToTopTrigger = 0
    /// 탭 위로 여는 화면(주간 리포트·운동 환산·식사 기록·나의 정보 수정·설정)의 스택
    @State private var router: AppRouter

    init(
        profile: UserProfile,
        mealRecordStore: MealRecordStore,
        onboardingStore: OnboardingStore,
        weightRecordStore: WeightRecordStore,
        onDeleteAccount: @escaping () async -> Bool,
        onLogout: @escaping () -> Void,
        router: AppRouter? = nil
    ) {
        self.profile = profile
        self.mealRecordStore = mealRecordStore
        self.onboardingStore = onboardingStore
        self.weightRecordStore = weightRecordStore
        self.onDeleteAccount = onDeleteAccount
        self.onLogout = onLogout
        // 테스트에서 스택을 들여다보려고 라우터를 넘길 수 있다(앱에서는 새로 만든다).
        _router = State(initialValue: router ?? AppRouter())
    }

    var body: some View {
        // 탭과 탭바를 통째로 NavigationStack 하나로 감싼다. push한 화면은 탭바 없이 전체 화면이고,
        // 뒤로 밀면 탭바가 있는 이전 화면이 아래에서 따라온다. 각 탭 안에는 NavigationStack을 따로 두지 않는다.
        NavigationStack(path: $router.path) {
            tabs
                .toolbar(.hidden, for: .navigationBar)
                .background { PopGestureEnabler(router: router) }
                .navigationDestination(for: AppRouteEntry.self) { entry in
                    entry.makeView()
                        .toolbar(.hidden, for: .navigationBar)
                        .environment(\.appRouteEntryID, entry.id)
                }
        }
        .environment(\.appRouter, router)
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                profile: profile,
                mealRecordStore: mealRecordStore,
                weightRecordStore: weightRecordStore,
                scrollToTopTrigger: homeScrollToTopTrigger
            )
                .tag(MainTab.home)

            RecordView(
                profile: profile,
                mealRecordStore: mealRecordStore
            )
                .tag(MainTab.record)

            ProfileView(
                profile: profile,
                onboardingStore: onboardingStore,
                weightRecordStore: weightRecordStore,
                onDeleteAccount: onDeleteAccount,
                onLogout: onLogout
            )
                .tag(MainTab.profile)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MainTabBar(selectedTab: $selectedTab) { tab in
                if tab == .home {
                    homeScrollToTopTrigger += 1
                }
            }
        }
        .onChange(of: selectedTab) { previousTab, currentTab in
            if previousTab != .home, currentTab == .home {
                homeScrollToTopTrigger += 1
            }
        }
    }
}

private enum MainTab: CaseIterable {
    case home
    case record
    case profile

    var title: String {
        switch self {
        case .home: "홈"
        case .record: "기록"
        case .profile: "내정보"
        }
    }

    var iconName: String {
        switch self {
        case .home: "tabHome"
        case .record: "tabRecord"
        case .profile: "tabProfile"
        }
    }

    var iconSize: CGSize {
        switch self {
        case .home, .record: CGSize(width: 20, height: 20)
        case .profile: CGSize(width: 17, height: 19)
        }
    }
}

private struct MainTabBar: View {
    @Binding var selectedTab: MainTab
    let onReselect: (MainTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    if selectedTab == tab {
                        onReselect(tab)
                    } else {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(tab.iconName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: tab.iconSize.width, height: tab.iconSize.height)
                            .frame(width: 24, height: 24)

                        Text(tab.title)
                            .font(.pretendardSemiBold(12))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.tabGreen : Color.gray02)
                    .frame(width: 81.25)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])

                if tab != MainTab.allCases.last {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 20)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20
            )
            .fill(Color.white)
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20
            )
            .stroke(Color(red: 221 / 255, green: 223 / 255, blue: 230 / 255), lineWidth: 1)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

#Preview {
    MainTabViewPreview()
}

private struct MainTabViewPreview: View {
    private let container: ModelContainer
    private let profile: UserProfile
    private let mealRecordStore: MealRecordStore
    private let onboardingStore: OnboardingStore
    private let weightRecordStore: WeightRecordStore

    init() {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: UserProfile.self,
            MealRecord.self,
            WeightRecord.self,
            configurations: configuration
        )
        let context = container.mainContext
        let profile = UserProfile(
            kakaoUserID: 1,
            nickname: "박정환",
            genderRawValue: Gender.male.rawValue,
            birthDate: Calendar.current.date(
                from: DateComponents(year: 1998, month: 3, day: 15)
            ),
            heightCM: 178,
            weightTenthsKG: 780,
            activityLevelRawValue: ActivityLevel.active.rawValue,
            hasCompletedOnboarding: true
        )
        context.insert(profile)
        try? context.save()

        self.container = container
        self.profile = profile
        mealRecordStore = MealRecordStore(modelContext: context)
        onboardingStore = OnboardingStore(modelContext: context)
        weightRecordStore = WeightRecordStore(modelContext: context)
    }

    var body: some View {
        MainTabView(
            profile: profile,
            mealRecordStore: mealRecordStore,
            onboardingStore: onboardingStore,
            weightRecordStore: weightRecordStore,
            onDeleteAccount: { true },
            onLogout: {}
        )
        .modelContainer(container)
    }
}
