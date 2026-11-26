import SwiftUI

struct SettingsView: View {
    @AppStorage("isNotificationEnabled") private var isNotificationEnabled = true

    let onBack: () -> Void
    let onLogout: () -> Void
    let onDeleteAccount: () async -> Bool

    @State private var confirmation: AccountConfirmation?
    @State private var unavailableItem: SettingsItem?
    @State private var isDeletingAccount = false
    @State private var isShowingDeletionError = false
    @Environment(\.appRouter) private var router

    var body: some View {
        VStack(spacing: 0) {
            header

            NoBounceScrollView {
                VStack(spacing: 16) {
                    notificationSection
                    divider
                    accountSection
                    divider
                    informationSection
                    divider
                    searchLogSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .background(Color.gray01)
        .preferredColorScheme(.light)
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: confirmationBinding,
            titleVisibility: .visible,
            presenting: confirmation
        ) { confirmation in
            switch confirmation {
            case .logout:
                Button("로그아웃", role: .destructive, action: onLogout)
            case .deleteAccount:
                Button("회원 탈퇴", role: .destructive) {
                    deleteAccount()
                }
            }

            Button("취소", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
        .alert(
            "준비 중이에요",
            isPresented: unavailableItemBinding,
            presenting: unavailableItem
        ) { _ in
            Button("확인", role: .cancel) {}
        } message: { item in
            Text("\(item.title) 화면은 준비 중이에요.")
        }
        .alert("회원 탈퇴에 실패했어요", isPresented: $isShowingDeletionError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("네트워크 상태를 확인한 후 다시 시도해 주세요.")
        }
        .overlay {
            if isDeletingAccount {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()

                ProgressView()
                    .tint(Color.green03)
            }
        }
        // 탈퇴 처리 중에는 스와이프 뒤로가기를 막는다(그때는 뒤로가기 버튼도 가려진다).
        .popGestureDisabled(isDeletingAccount)
    }

    private var header: some View {
        ZStack {
            Text("설정")
                .font(.pretendardSemiBold(16))
                .foregroundStyle(Color.black01)

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.black01)
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

    private var notificationSection: some View {
        HStack {
            Text("알림 설정")
                .font(.pretendardSemiBold(16))
                .foregroundStyle(Color.black01)

            Spacer()

            Toggle("", isOn: $isNotificationEnabled)
                .labelsHidden()
                .toggleStyle(SettingsToggleStyle())
        }
        .frame(height: 30)
    }

    private var accountSection: some View {
        settingsSection(title: "내 계정") {
            settingsRow(title: "로그아웃") {
                confirmation = .logout
            }

            settingsRow(title: "회원 탈퇴하기") {
                confirmation = .deleteAccount
            }
        }
    }

    private var informationSection: some View {
        settingsSection(title: "기타") {
            settingsRow(title: SettingsItem.terms.title) {
                unavailableItem = .terms
            }

            settingsRow(title: SettingsItem.privacy.title) {
                unavailableItem = .privacy
            }

            HStack {
                Text("앱 정보")
                    .font(.pretendardMedium(14))
                    .foregroundStyle(Color.black01)

                Spacer()

                Text(appVersion)
                    .font(.pretendardRegular(14))
                    .foregroundStyle(Color.gray03)
            }
            .frame(height: 30)
        }
    }

    /// 전시용 검색 개선 기록(#51). 기기 안 기록만 보고·복사·지운다(식사 기록과 따로).
    private var searchLogSection: some View {
        // 설정 내용은 NoBounceScrollView 안이라, 라우터를 화면을 그릴 때 꺼내 둔다.
        let router = self.router
        return settingsSection(title: "전시") {
            settingsRow(title: "검색 개선 기록") {
                router.push(.searchImprovementLog) {
                    SearchImprovementLogView(onBack: { router.pop(.searchImprovementLog) })
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.gray02)
            .frame(height: 1)
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.pretendardSemiBold(16))
                .foregroundStyle(Color.black01)
                .frame(height: 30)

            VStack(spacing: 14) {
                content()
            }
        }
    }

    private func settingsRow(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.pretendardMedium(14))
                    .foregroundStyle(Color.black01)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.gray03)
                    .frame(width: 16, height: 32)
            }
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { confirmation != nil },
            set: { isPresented in
                if !isPresented {
                    confirmation = nil
                }
            }
        )
    }

    private var unavailableItemBinding: Binding<Bool> {
        Binding(
            get: { unavailableItem != nil },
            set: { isPresented in
                if !isPresented {
                    unavailableItem = nil
                }
            }
        )
    }

    private func deleteAccount() {
        guard !isDeletingAccount else { return }

        isDeletingAccount = true
        Task {
            let didDelete = await onDeleteAccount()
            isDeletingAccount = false
            if !didDelete {
                isShowingDeletionError = true
            }
        }
    }
}

private enum AccountConfirmation: Identifiable {
    case logout
    case deleteAccount

    var id: Self { self }

    var title: String {
        switch self {
        case .logout: "로그아웃하시겠어요?"
        case .deleteAccount: "정말 탈퇴하시겠어요?"
        }
    }

    var message: String {
        switch self {
        case .logout:
            "다시 로그인하면 기존 기록을 이어서 사용할 수 있어요."
        case .deleteAccount:
            "모든 식단 및 체중 기록이 삭제되며 복구할 수 없어요."
        }
    }
}

private enum SettingsItem: Identifiable {
    case terms
    case privacy

    var id: Self { self }

    var title: String {
        switch self {
        case .terms: "서비스 약관 및 정책"
        case .privacy: "개인정보 처리방침"
        }
    }
}

private struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color.green03 : Color.gray02)
                .frame(width: 50, height: 26)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "켬" : "끔")
    }
}

#Preview {
    SettingsView(
        onBack: {},
        onLogout: {},
        onDeleteAccount: { true }
    )
}
