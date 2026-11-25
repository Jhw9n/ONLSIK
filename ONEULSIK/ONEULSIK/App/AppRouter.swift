import SwiftUI
import UIKit

/// 메인 화면(MainTabView)의 NavigationStack 하나로 여는 화면들. 탭바 위에 push되어 전체 화면이 되고,
/// iOS 기본 슬라이드와 왼쪽 가장자리 스와이프 뒤로가기(이전 화면이 아래에서 따라옴)를 쓴다.
enum AppRoute: Hashable {
    case weeklyReport
    case exerciseGame
    case mealEntry
    case foodSearch
    case foodQuantity
    case profileEdit(String)
    case settings
}

/// 스택에 올린 화면 하나. 화면은 연 곳에서 만들어 넘기고(그 화면의 값·콜백을 그대로 쓰기 위해),
/// 버튼이든 스와이프든 이 화면이 스택에서 빠지면 onPop을 부른다(전의 fullScreenCover onDismiss 자리).
struct AppRouteEntry: Hashable, Identifiable {
    let id = UUID()
    let route: AppRoute
    let makeView: () -> AnyView
    let onPop: (() -> Void)?

    static func == (lhs: AppRouteEntry, rhs: AppRouteEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 화면 이동을 모으는 작은 라우터. MainTabView가 하나 만들어 environment(\.appRouter)로 내려 준다.
@Observable
@MainActor
final class AppRouter {
    /// NavigationStack(path:)에 묶는 스택. 스와이프로 빠지면 SwiftUI가 줄인다.
    var path: [AppRouteEntry] = [] {
        didSet { notifyRemoved(from: oldValue) }
    }
    /// 스와이프 뒤로가기를 막은 화면(entry id)
    private(set) var popGestureDisabledIDs: Set<UUID> = []

    nonisolated init() {}

    var routes: [AppRoute] { path.map(\.route) }

    func contains(_ route: AppRoute) -> Bool { path.contains { $0.route == route } }

    /// 화면을 올린다. iOS 기본 슬라이드로 들어온다.
    func push<V: View>(_ route: AppRoute, onPop: (() -> Void)? = nil, @ViewBuilder _ view: @escaping () -> V) {
        path.append(AppRouteEntry(route: route, makeView: { AnyView(view()) }, onPop: onPop))
    }

    /// 맨 위 화면 하나를 내린다(뒤로가기 버튼).
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// 이 화면부터 위를 모두 내린다.
    func pop(_ route: AppRoute) {
        guard let index = path.lastIndex(where: { $0.route == route }) else { return }
        path.removeSubrange(index...)
    }

    func popToRoot() { path.removeAll() }

    /// 맨 위 화면이 스와이프 뒤로가기를 허용하는지
    var isTopPopGestureEnabled: Bool {
        guard let top = path.last else { return false }
        return !popGestureDisabledIDs.contains(top.id)
    }

    func setPopGestureDisabled(_ disabled: Bool, for id: UUID) {
        if disabled { popGestureDisabledIDs.insert(id) } else { popGestureDisabledIDs.remove(id) }
    }

    /// 빠진 화면의 onPop을 위에서부터 부른다. path를 바꾸는 중이라 다음 차례에 부른다(onPop 안에서 또 pop해도 된다).
    private func notifyRemoved(from oldValue: [AppRouteEntry]) {
        let remaining = Set(path.map(\.id))
        let removed = oldValue.filter { !remaining.contains($0.id) }
        guard !removed.isEmpty else { return }
        for entry in removed { popGestureDisabledIDs.remove(entry.id) }
        let callbacks = removed.reversed().compactMap(\.onPop)
        guard !callbacks.isEmpty else { return }
        Task { @MainActor in callbacks.forEach { $0() } }
    }
}

private struct AppRouterKey: EnvironmentKey {
    /// 스택 밖(미리보기·테스트에서 화면만 띄울 때)에서 쓰는 라우터. push해도 보이는 곳이 없다.
    static let defaultValue = AppRouter()
}

private struct AppRouteEntryIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var appRouter: AppRouter {
        get { self[AppRouterKey.self] }
        set { self[AppRouterKey.self] = newValue }
    }

    /// 스택에 올린 화면 안에서 자기 entry id(스와이프 막기에 쓴다)
    var appRouteEntryID: UUID? {
        get { self[AppRouteEntryIDKey.self] }
        set { self[AppRouteEntryIDKey.self] = newValue }
    }
}

extension View {
    /// 이 화면에서 왼쪽 가장자리 스와이프 뒤로가기를 막는다(조건이 참인 동안). 스택에 올린 화면 안에서만 효과가 있다.
    func popGestureDisabled(_ disabled: Bool) -> some View {
        modifier(PopGestureDisabledModifier(disabled: disabled))
    }
}

private struct PopGestureDisabledModifier: ViewModifier {
    let disabled: Bool
    @Environment(\.appRouter) private var router
    @Environment(\.appRouteEntryID) private var entryID

    func body(content: Content) -> some View {
        content
            .onAppear { apply(disabled) }
            .onChange(of: disabled) { _, newValue in apply(newValue) }
    }

    private func apply(_ value: Bool) {
        guard let entryID else { return }
        router.setPopGestureDisabled(value, for: entryID)
    }
}

/// 기본 내비게이션 바를 숨기면 꺼지는 스와이프 뒤로가기를 이 NavigationStack에만 다시 켠다.
/// 스택 안의 빈 뷰에서 UINavigationController를 찾아 interactivePopGestureRecognizer의 delegate를 바꾼다.
struct PopGestureEnabler: UIViewRepresentable {
    let router: AppRouter

    func makeCoordinator() -> Coordinator { Coordinator(router: router) }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.router = router
        view.coordinator = context.coordinator
        view.install()
    }

    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            install()
        }

        func install() {
            guard window != nil else { return }
            coordinator?.install(on: navigationController())
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.coordinator?.install(on: self.navigationController())
            }
        }

        private func navigationController() -> UINavigationController? {
            var responder: UIResponder? = next
            while let current = responder {
                if let controller = current as? UIViewController {
                    if let navigation = controller as? UINavigationController { return navigation }
                    if let navigation = controller.navigationController { return navigation }
                }
                responder = current.next
            }
            return nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var router: AppRouter
        private weak var navigationController: UINavigationController?

        init(router: AppRouter) { self.router = router }

        func install(on navigationController: UINavigationController?) {
            guard let navigationController, let gesture = navigationController.interactivePopGestureRecognizer else { return }
            if gesture.delegate !== self { gesture.delegate = self }
            gesture.isEnabled = true
            self.navigationController = navigationController
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigationController, navigationController.viewControllers.count > 1,
                  navigationController.transitionCoordinator == nil else { return false }
            let allowed = MainActor.assumeIsolated { router.isTopPopGestureEnabled }
            if allowed {
                // 키보드가 떠 있으면 미는 순간 내린다.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            return allowed
        }

    }
}
