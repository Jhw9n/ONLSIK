import SwiftUI
import UIKit

/// 운동 환산 화면(#49)을 켜고 끄는 곳. 전시 뒤 배너를 숨기려면 false로 바꾼다.
enum ExerciseGameFeature {
    static let isBannerEnabled = true
}

/// 홈의 "먹고 싶은 음식 담아보기" 배너(343×96, Figma "개발" 페이지 0 · 홈 배너 2314:609). 누르면 운동 환산 화면을 연다.
/// 미니 그릇 위에 김(Mini Steam 36×21, 배너 기준 x 28, y 17)이 올라온다. 김 아래 끝은 국물 타원 윗면(배너 y 33)에서 시작한다. 김은 overlay라 배너 높이·글자 위치에 영향이 없고,
/// 배너가 화면에 안 보이거나 운동 환산 화면이 떠 있거나 앱이 활성 상태가 아니면 멈춘다(동작 줄이기면 움직이지 않는 김).
struct ExerciseGameBanner: View {
    /// 운동 환산 화면(fullScreenCover)이 떠 있는지. 떠 있으면 김을 멈춘다.
    var isCovered: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 홈 스크롤 안에서 배너가 화면에 보이는지(UIKit 스크롤이라 UIView로 잰다)
    @State private var isOnScreen = false
    /// 앱이 활성 상태인지. 홈 내용은 NoBounceScrollView 안의 별도 UIHostingController라 scenePhase가 전달되지 않을 수 있어
    /// UIKit 알림(UIApplication)으로 잰다.
    @State private var isAppActive = true

    /// 김을 멈출지(동작 줄이기와 별개로 TimelineView를 멈추는 조건)
    var isSteamPaused: Bool { Self.isSteamPaused(isOnScreen: isOnScreen, isCovered: isCovered, isActive: isAppActive) }

    static func isSteamPaused(isOnScreen: Bool, isCovered: Bool, isActive: Bool) -> Bool {
        !isOnScreen || isCovered || !isActive
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ExerciseBowlBadge()
                VStack(alignment: .leading, spacing: 8) {
                    Text("먹고 싶은 음식 담아보기")
                        .font(.pretendardBold(16))
                        .foregroundStyle(Color.white)
                    Text("운동으로 얼마나 빼야 할지 알려드려요")
                        .font(.pretendardSemiBold(12))
                        .foregroundStyle(Color.exerciseLightGreen)
                }
                Spacer(minLength: 0)
                BannerChevron()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .overlay(alignment: .topLeading) {
                BowlSteamView(reduceMotion: reduceMotion, isPaused: isSteamPaused, style: .mini)
                    .frame(width: 36, height: 21)
                    .offset(x: 28, y: 17)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background(
                LinearGradient(colors: [Color(hex: 0x1E2A44), Color(hex: 0x18191F)], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background { VisibilityProbe { isOnScreen = $0 } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in isAppActive = true }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in isAppActive = false }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("먹고 싶은 음식 담아보기. 운동으로 얼마나 빼야 할지 알려드려요")
        .accessibilityAddTraits(.isButton)
    }
}

/// Figma icon/chevron-right(20×20 안에 5×10, 흰색 선 1.8pt)
private struct BannerChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - 2.5, y: rect.midY - 5))
        path.addLine(to: CGPoint(x: rect.midX + 2.5, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX - 2.5, y: rect.midY + 5))
        return path
    }
}

/// 배너가 창 안에서 보이는지 알려 주는 빈 UIView. 홈 스크롤(NoBounceScrollView)이 UIKit UIScrollView라
/// SwiftUI의 onAppear로는 스크롤로 가려지는 것을 알 수 없어, 가장 가까운 UIScrollView의 contentOffset을 지켜본다.
private struct VisibilityProbe: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: ((Bool) -> Void)?
        private var observation: NSKeyValueObservation?
        private var lastValue: Bool?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observation = nil
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            if let scrollView = ancestor as? UIScrollView {
                observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.report() }
                }
            }
            report()
            // 창에 붙는 순간에는 크기가 0일 수 있어 배치가 끝난 뒤 한 번 더 본다.
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        // SwiftUI가 frame·bounds 중 무엇으로 크기를 정하든 알아차리도록 둘 다 본다.
        override var frame: CGRect {
            didSet { if frame != oldValue { report() } }
        }

        override var bounds: CGRect {
            didSet { if bounds.size != oldValue.size { report() } }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            let visible: Bool
            if let window, !isHidden, bounds.width > 0 {
                visible = convert(bounds, to: window).intersects(window.bounds)
            } else {
                visible = false
            }
            guard visible != lastValue else { return }
            lastValue = visible
            let onChange = self.onChange
            DispatchQueue.main.async { onChange?(visible) }
        }
    }
}
