import SwiftUI
import UIKit

/// 홈 배너에서 여는 "먹고 싶은 음식 → 운동 시간" 화면(#49). Figma "개발" 페이지 섹션 2312:534(1·2·3 화면) 기준.
/// - 담기(A) → 담기는 연출(B) → 결과(C). 결과는 식사 기록으로 저장하지 않는다.
/// - 분석은 기존 식사 입력 분석 서비스(ExerciseGameAnalyzer → AIMealEntryService)의 열량만 쓴다.
/// - 배치: 화면 전체를 한 배율로 키우지 않는다. 글자·입력칸·카드·그릇은 Figma pt 값 그대로이고, 세로는 안전 영역 윗변이 0이다(Metrics).
///   작은 화면에서는 그릇·카드 위 간격을 먼저 줄이고, 그래도 부족하면 그릇을 줄이거나(최소 0.8배) 카드 간격을 14 → 10으로 줄인다.
/// - 키보드: 하단 버튼은 키보드를 따라 올라가지 않는다(키보드 안전 영역 무시). 입력칸이 키보드에 가려질 때만 내용을 올린다.
struct ExerciseGameView: View {
    let weightKG: Double
    let usesFallbackWeight: Bool
    let analyzer: ExerciseGameAnalyzer
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isInputFocused: Bool

    @State private var text = ""
    @State private var stage = Stage.input
    /// 입력칸이 키보드에 가려질 때 내용을 올리는 양
    @State private var contentLift: CGFloat = 0
    /// 입력칸·그릇의 실제 위치(이 화면 좌표, 안전 영역 위가 0). 연출 좌표는 이 값으로 계산한다.
    @State private var inputFrame = CGRect.zero
    @State private var inputScreenFrame = CGRect.zero
    @State private var bowlFrame = CGRect.zero

    // 담기 연출 상태
    @State private var isInputCollapsed = false
    @State private var chipVisible = false
    @State private var chipText = ""
    @State private var chipOffset = CGSize.zero
    @State private var chipScale: CGFloat = 1
    @State private var chipRotation: Double = 0
    @State private var chipOpacity: Double = 1
    @State private var trailVisible = false
    @State private var chipMasked = false
    @State private var titleDimmed = false
    @State private var bowlSquash: CGFloat = 1
    @State private var rippleScale: CGFloat = 0.3
    @State private var rippleOpacity: Double = 0
    @State private var fillProgress: Double = 0
    @State private var glowOpacity: Double = 0.28
    @State private var showsSteam = false
    @State private var showsWaiting = false
    @State private var showsFailure = false
    /// 실패한 입력. 입력을 바꾸면 실패 안내를 숨긴다.
    @State private var failedText = ""
    @State private var analysisTask: Task<ExerciseGameResult, Error>?
    /// 담기 연출(runSequence) 작업. 다시 담기에서 취소한다.
    @State private var sequenceTask: Task<Void, Never>?
    @State private var analysisFinished = false

    // 결과 상태
    @State private var result: ExerciseGameResult?
    @State private var showsResult = false
    @State private var countedKcal: Double = 0
    @State private var cardProgress: [Double] = [0, 0, 0]
    @State private var cardVisible: [Bool] = [false, false, false]

    private enum Stage { case input, dropping, result }

    private let exercises = ExerciseEquivalentCatalog.exercises
    private let snapshot: ExerciseGameSnapshot?
    @State private var trailLag = CGSize.zero

    private static let space = "exerciseGame"

    init(weightKG: Double, usesFallbackWeight: Bool, analyzer: ExerciseGameAnalyzer,
         snapshot: ExerciseGameSnapshot? = nil, onClose: @escaping () -> Void) {
        self.weightKG = weightKG
        self.usesFallbackWeight = usesFallbackWeight
        self.analyzer = analyzer
        self.snapshot = snapshot
        self.onClose = onClose
    }

    /// Figma "개발" 페이지 섹션 2312:534 값(pt). 세로 위치는 안전 영역 윗변이 0(Figma y에서 상태바 50을 뺀 값).
    private enum Metrics {
        /// 뒤로가기 헤더(header-page-iOS) 높이. 입력 상태에서만 버튼이 보이고 자리는 늘 유지한다.
        static let headerHeight: CGFloat = 56
        /// 제목 첫 줄 윗변(헤더 아래 30). 결과 화면 제목(음식 이름 줄)도 같은 값
        static let titleTop: CGFloat = 86
        /// 1·2번 제목 한 줄 높이(30pt × 130%)와 두 줄 사이 간격: 첫 줄 86, 둘째 줄 127
        static let titleLineHeight: CGFloat = 39
        static let titleLineGap: CGFloat = 2
        /// 부제 윗변(둘째 줄 아래 166 + 8)
        static let subtitleTop: CGFloat = 174
        /// 입력칸(Bowl Input 243×52, 가로 가운데, 375 기준 x 66) 윗변. 모서리 반지름은 높이의 절반
        static let inputTop: CGFloat = 298
        static let inputSize = CGSize(width: 243, height: 52)
        /// 그릇 묶음 윗변
        static let bowlTop: CGFloat = 386
        /// 그릇 기본 배율: ExerciseBowlView 기준 320×230 → 297.92×214.13. 그릇 안 모든 도형·김·물결·입구가 같은 비율로 줄어든다.
        static let bowlBaseScale: CGFloat = 0.931
        /// 작은 화면에서 그릇 위 간격(입력칸 아래에서)을 줄일 때 최소값
        static let bowlMinGap: CGFloat = 8
        /// 그릇 아래 "계산하고 있어요" 자리
        static let bowlLabelSpace: CGFloat = 26
        /// 기본 크기 그릇 묶음 높이(214.13 + 26)
        static var bowlBlockHeight: CGFloat { ExerciseBowlView.size.height * bowlBaseScale + bowlLabelSpace }
        /// 작은 화면에서 더 줄일 때 최소 배율. 기본 크기(297.92×214.13)에 곱한다(원래 320×230 기준으로는 0.745).
        static let bowlMinScale: CGFloat = 0.8
        /// 결과: "927"(48 Bold) 윗변 129, "kcal"(24 Bold)은 같은 기준선
        static let resultKcalTop: CGFloat = 129
        /// 결과: 카드 묶음 윗변
        static let resultCardsTop: CGFloat = 231
        /// 결과: kcal 줄 아래(191)에서 8 띄운 카드 최소 위치(작은 화면에서 줄일 때)
        static let resultMinCardsTop: CGFloat = 199
        static let cardHeight: CGFloat = 98
        static let cardSpacing: CGFloat = 14
        static let cardMinSpacing: CGFloat = 10
        static let buttonHeight: CGFloat = 52
        /// 하단 버튼 아래 여백. OnboardingScaffold·기록 화면처럼 안전 영역 안에서 4(Figma 버튼 y 722 = 안전 영역 아래 4)
        static let buttonBottomPadding: CGFloat = 4
        /// 내용과 하단 버튼 사이 최소 간격
        static let contentBottomGap: CGFloat = 16
        /// 결과 안내 문구(12pt 한 줄)와 버튼 사이
        static let noteGap: CGFloat = 16
        static let noteHeight: CGFloat = 15
    }

    /// 하단 버튼 묶음이 차지하는 높이(안전 영역 아래쪽에서)
    private func bottomBlockHeight(result: Bool) -> CGFloat {
        Metrics.buttonHeight + Metrics.buttonBottomPadding + Metrics.contentBottomGap
            + (result ? Metrics.noteGap + Metrics.noteHeight : 0)
    }

    /// 기본 크기 그릇 묶음이 하단 버튼 위 공간에 들어가도록 더 줄이는 배율(0.8...1). 기본 배율 0.95에 곱한다.
    static func bowlFitScale(contentHeight: CGFloat, bowlTop: CGFloat) -> CGFloat {
        min(1, max(Metrics.bowlMinScale, (contentHeight - bowlTop) / Metrics.bowlBlockHeight))
    }

    var body: some View {
        GeometryReader { proxy in
            // 안전 영역 안 크기. 키보드 안전 영역은 무시해서 키보드가 올라와도 버튼·배치가 움직이지 않는다.
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isInputFocused = false }

                bubbles(size)

                Group {
                    if showsResult, let result {
                        resultContent(result, size: size)
                            .transition(.opacity)
                    } else {
                        inputContent(size)
                            .transition(.opacity)
                    }
                }
                .offset(y: -contentLift)

                header
                    .offset(y: -contentLift)

                chipLayer(size)

                bottomArea(size)
            }
            .frame(width: size.width, height: size.height)
            .coordinateSpace(.named(Self.space))
        }
        .background { background }
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            updateLift(keyboardTop: frame.minY < UIScreen.main.bounds.height ? frame.minY : nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            updateLift(keyboardTop: nil)
        }
        .onAppear { applySnapshot() }
        .onDisappear { analysisTask?.cancel() }
    }

    /// 뒤로가기를 보일지: 입력 상태에서만. 칩이 떨어지는 연출·분석 중과 결과 화면에서는 숨기고 막는다
    /// (결과 화면에서는 하단 "다시 담기"만 누를 수 있다).
    static func showsBackButton(isInputStage: Bool, showsResult: Bool) -> Bool {
        isInputStage && !showsResult
    }

    private var backButtonVisible: Bool {
        Self.showsBackButton(isInputStage: stage == .input, showsResult: showsResult)
    }

    /// 뒤로가기 헤더(높이 56). 버튼 모양은 WeeklyReportView 헤더와 같고, 어두운 배경이라 아이콘은 Figma 2313:534의 흰색(#FFFFFF).
    /// 입력 상태에서만 버튼이 보이고(연출·결과에서는 숨김) 자리는 늘 유지해 제목·결과 배치가 위아래로 움직이지 않는다.
    private var header: some View {
        HStack {
            // 화면 전체에 키보드를 내리는 배경 탭(onTapGesture)이 깔려 있어, contentShape가 없으면 아이콘 위를 눌러도
            // 배경 탭이 먼저 잡아 닫히지 않았다(실기기 증상). 48×48 전체를 누르는 영역으로 둔다.
            Button {
                isInputFocused = false
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("뒤로가기")
            .opacity(backButtonVisible ? 1 : 0)
            .allowsHitTesting(backButtonVisible)
            .accessibilityHidden(!backButtonVisible)

            Spacer()
        }
        .padding(.leading, 4)
        .frame(height: Metrics.headerHeight)
    }

    /// 입력칸이 키보드에 가려지면 가려지지 않을 만큼만 올린다. 이미 키보드보다 위에 있으면 올리지 않는다.
    private func updateLift(keyboardTop: CGFloat?) {
        let lift: CGFloat
        if let keyboardTop, !showsResult {
            // 지금 올라가 있는 양을 빼서 원래 위치로 계산한다.
            let inputBottom = inputScreenFrame.maxY + contentLift
            lift = max(0, inputBottom + 16 - keyboardTop)
        } else {
            lift = 0
        }
        guard lift != contentLift else { return }
        withAnimation(.easeOut(duration: 0.25)) { contentLift = lift }
    }

    // MARK: - 배경·장식

    private var background: some View {
        LinearGradient(stops: [
            .init(color: Color(hex: 0x1E2A44), location: 0),
            .init(color: Color(hex: 0x18191F), location: 0.55),
            .init(color: Color(hex: 0x141519), location: 1)
        ], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
    }

    /// 비눗방울(Figma 2313:534): 54pt (20, 188), 22pt (318, 210), 40pt (306, 594). 가로는 폭 375 기준 비율.
    /// 결과 화면(2314:554)에는 비눗방울이 없어 숨긴다.
    private func bubbles(_ size: CGSize) -> some View {
        let sx = size.width / 375
        return TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                bubble(size: 54, tint: Color.exerciseLightGreen, time: time, period: 4.6, phase: 0)
                    .position(x: (20 + 27) * sx, y: 188 + 27)
                bubble(size: 40, tint: Color(hex: 0x3FC6A8), time: time, period: 5.4, phase: 1.7)
                    .position(x: (306 + 20) * sx, y: 594 + 20)
                bubble(size: 22, tint: .white, time: time, period: 3.9, phase: 3.1)
                    .position(x: (318 + 11) * sx, y: 210 + 11)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .opacity(showsResult ? 0 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bubble(size: CGFloat, tint: Color, time: TimeInterval, period: Double, phase: Double) -> some View {
        let offset = reduceMotion ? 0 : sin(time / period * 2 * .pi + phase) * 6
        return Circle()
            .fill(RadialGradient(stops: [
                .init(color: tint.opacity(0), location: 0),
                .init(color: tint.opacity(0.18), location: 0.7),
                .init(color: Color.white.opacity(0.55), location: 1)
            ], center: .center, startRadius: 0, endRadius: size / 2))
            .overlay { Circle().stroke(Color.white.opacity(0.25), lineWidth: 1) }
            .frame(width: size, height: size)
            .offset(y: offset)
    }

    // MARK: - 화면 A·B

    /// 헤더(56) → 제목 86·127, 부제 174 → 입력칸 298(243×52) → 그릇 386(297.92×214.13).
    /// 작은 화면에서 그릇 묶음이 하단 버튼에 닿으면 먼저 그릇 위 간격을 줄이고(최소 8), 그래도 부족하면 그릇을 줄인다(기본 크기의 최소 0.8배).
    private func inputContent(_ size: CGSize) -> some View {
        let contentHeight = size.height - bottomBlockHeight(result: false)
        let inputBottom = Metrics.inputTop + Metrics.inputSize.height
        let minBowlTop = inputBottom + Metrics.bowlMinGap
        let bowlTop = max(minBowlTop, min(Metrics.bowlTop, contentHeight - Metrics.bowlBlockHeight))
        let bowlScale = Metrics.bowlBaseScale * Self.bowlFitScale(contentHeight: contentHeight, bowlTop: bowlTop)
        let bowlSize = CGSize(width: ExerciseBowlView.size.width * bowlScale, height: ExerciseBowlView.size.height * bowlScale)

        return ZStack(alignment: .top) {
            Group {
                // 두 줄을 줄 높이 39·간격 2로 따로 놓아 Figma 위치(72, 113)에 맞춘다. VoiceOver는 전처럼 한 제목으로 읽는다.
                VStack(spacing: Metrics.titleLineGap) {
                    ForEach(["먹고 싶은 음식을", "그릇에 담아보세요"], id: \.self) { line in
                        Text(line)
                            .font(.pretendardBold(30))
                            .foregroundStyle(Color.exerciseGreen)
                            .frame(height: Metrics.titleLineHeight)
                    }
                }
                .padding(.top, Metrics.titleTop)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("먹고 싶은 음식을 그릇에 담아보세요")
                Text("운동으로 얼마나 빼야 하는지 알려드려요")
                    .font(.pretendardMedium(15))
                    .foregroundStyle(Color(hex: 0xA3A8B3))
                    .padding(.top, Metrics.subtitleTop)
            }
            .opacity(titleDimmed ? 0.35 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ExerciseBowlView(fillProgress: fillProgress, glowOpacity: glowOpacity, showsSteam: showsSteam, reduceMotion: reduceMotion)
                .overlay(alignment: .topLeading) { ripple }
                .scaleEffect(x: 1, y: bowlSquash, anchor: .bottom)
                .scaleEffect(bowlScale, anchor: .topLeading)
                .frame(width: bowlSize.width, height: bowlSize.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { isInputFocused = false }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { bowlFrame = $0 }
                .padding(.top, bowlTop)

            if showsWaiting {
                WaitingLabel(reduceMotion: reduceMotion)
                    .padding(.top, bowlTop + bowlSize.height + 10)
                    .transition(.opacity)
            }

            inputField
                .frame(width: min(Metrics.inputSize.width, size.width - 32), height: Metrics.inputSize.height)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { inputFrame = $0 }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { inputScreenFrame = $0 }
                .scaleEffect(x: isInputCollapsed ? 0.4 : 1, y: isInputCollapsed ? 0.75 : 1)
                .opacity(isInputCollapsed ? 0 : 1)
                .allowsHitTesting(stage == .input)
                .padding(.top, Metrics.inputTop)

            if showsFailure {
                Text("그 음식은 아직 몰라요. 다른 음식을 담아 볼까요?")
                    .font(.pretendardMedium(13))
                    .foregroundStyle(Color(hex: 0xA3A8B3))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, inputBottom + 8)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: contentHeight, alignment: .top)
    }

    private var ripple: some View {
        Ellipse()
            .stroke(Color.exerciseLightGreen.opacity(0.9), lineWidth: 2)
            .frame(width: ExerciseBowlView.innerSize.width * rippleScale, height: ExerciseBowlView.innerSize.height * rippleScale)
            .opacity(rippleOpacity)
            .frame(width: ExerciseBowlView.innerSize.width, height: ExerciseBowlView.innerSize.height)
            .clipShape(Ellipse())
            .position(ExerciseBowlView.mouthCenter)
            .allowsHitTesting(false)
    }

    /// 안내 문구를 보일지: 글자가 비었고 포커스가 없을 때만. 눌러서 포커스가 잡히면 바로 숨기고 빈 칸 가운데에 커서만 둔다.
    static func showsInputPlaceholder(text: String, isFocused: Bool) -> Bool {
        text.isEmpty && !isFocused
    }

    /// 입력칸(글자만 받는다). 키보드 완료 키는 키보드만 내리고 분석은 하단 "담기"를 눌러야 시작한다(글자는 남음).
    /// 안내 문구·입력 글자·커서 모두 가로 가운데(좌우 안쪽 여백 22로 같게).
    /// 안내 문구는 TextField prompt가 아니라 overlay다(prompt는 포커스가 잡혀도 글자를 칠 때까지 남는다). 바뀔 때 애니메이션 없음.
    private var inputField: some View {
        TextField("", text: $text)
            .font(.pretendardSemiBold(16))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color(hex: 0x1D1D1D))
            .tint(Color.exerciseGreen)
            .submitLabel(.done)
            .focused($isInputFocused)
            .onSubmit(submitFromKeyboard)
            .onChange(of: text) { _, newValue in
                if showsFailure, newValue != failedText { withAnimation(.easeOut(duration: 0.2)) { showsFailure = false } }
            }
            .padding(.horizontal, 22)
            .frame(maxHeight: .infinity)
            .overlay {
                let showsPlaceholder = Self.showsInputPlaceholder(text: text, isFocused: isInputFocused)
                Text("음식을 적어주세요")
                    .font(.pretendardSemiBold(16))
                    .foregroundStyle(Color(hex: 0x9AA0AB))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .padding(.horizontal, 22)
                    .opacity(showsPlaceholder ? 1 : 0)
                    .animation(nil, value: showsPlaceholder)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: Metrics.inputSize.height / 2, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.inputSize.height / 2))
            .onTapGesture { isInputFocused = true }
            .accessibilityLabel("먹고 싶은 음식")
            .accessibilityHint("음식 이름을 적고 아래 담기 버튼을 누르세요. 운동 시간으로 알려드려요")
    }

    private var bowlScaleNow: CGFloat {
        bowlFrame.width > 0 ? bowlFrame.width / ExerciseBowlView.size.width : 1
    }

    /// 그릇 입구 가운데(이 화면 좌표)
    private var mouth: CGPoint {
        CGPoint(x: bowlFrame.midX, y: bowlFrame.minY + ExerciseBowlView.mouthCenter.y * bowlScaleNow)
    }

    /// 칩 시작점(입력칸 가운데)
    private var chipStart: CGPoint { CGPoint(x: inputFrame.midX, y: inputFrame.midY) }

    /// 음식 이름 칩과 잔상. 그릇 입구보다 아래로 내려가면 입구 안쪽 타원 밖은 가려져 그릇 속으로 들어가 보인다.
    private func chipLayer(_ size: CGSize) -> some View {
        let start = chipStart
        let mouth = self.mouth
        let scale = bowlScaleNow
        return ZStack(alignment: .topLeading) {
            if chipVisible {
                if trailVisible && !reduceMotion {
                    chip.opacity(0.12)
                        .modifier(ChipMotion(offset: chipOffset - trailLag * 2, scale: chipScale, rotation: chipRotation, center: start))
                        .animation(.easeIn(duration: 0.45).delay(0.08), value: chipOffset)
                    chip.opacity(0.3)
                        .modifier(ChipMotion(offset: chipOffset - trailLag, scale: chipScale, rotation: chipRotation, center: start))
                        .animation(.easeIn(duration: 0.45).delay(0.04), value: chipOffset)
                }
                chip
                    .opacity(chipOpacity)
                    .modifier(ChipMotion(offset: chipOffset, scale: chipScale, rotation: chipRotation, center: start))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .mask {
            if chipMasked {
                ZStack(alignment: .topLeading) {
                    Rectangle().frame(width: size.width, height: max(0, mouth.y))
                    Ellipse()
                        .frame(width: ExerciseBowlView.innerSize.width * scale, height: ExerciseBowlView.innerSize.height * scale)
                        .position(mouth)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            } else {
                Rectangle()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var chip: some View {
        Text(chipText)
            .font(.pretendardBold(14))
            .foregroundStyle(Color(hex: 0x1D1D1D))
            .lineLimit(1)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
            .fixedSize()
    }

    // MARK: - 화면 C

    /// 제목 86, "927 kcal" 129, 카드 묶음 231(Figma 2314:554). 카드 폭은 좌우 16 여백 안을 채운다.
    /// 작은 화면에서 카드 묶음이 안내 문구·버튼에 닿으면 카드 위 간격을 줄이고(최소 199), 그래도 부족하면 카드 간격을 14 → 10.
    private func resultContent(_ result: ExerciseGameResult, size: CGSize) -> some View {
        let contentHeight = size.height - bottomBlockHeight(result: true)
        let cardCount = CGFloat(exercises.count)
        let stack = { (spacing: CGFloat) in Metrics.cardHeight * cardCount + spacing * max(0, cardCount - 1) }
        let cardsTop = max(Metrics.resultMinCardsTop, min(Metrics.resultCardsTop, contentHeight - stack(Metrics.cardSpacing)))
        let spacing = cardsTop + stack(Metrics.cardSpacing) <= contentHeight ? Metrics.cardSpacing : Metrics.cardMinSpacing
        let cardWidth = size.width - 32
        return ZStack(alignment: .top) {
            Group {
                Text(result.title)
                    .font(.pretendardBold(30))
                    .foregroundStyle(Color.exerciseGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 16)
                    .padding(.top, Metrics.titleTop)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    CountingText(value: countedKcal) { "\(Int($0.rounded()))" }
                        .font(.pretendardBold(48))
                    Text("kcal")
                        .font(.pretendardBold(24))
                }
                .foregroundStyle(Color.exerciseGreen)
                .monospacedDigit()
                .padding(.top, Metrics.resultKcalTop)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(result.title) \(Int(result.kcal.rounded()))킬로칼로리")
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: spacing) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    exerciseCard(exercise, result: result, progress: cardProgress[safe: index] ?? 1)
                        .frame(width: cardWidth)
                        .opacity((cardVisible[safe: index] ?? true) ? 1 : 0)
                        .offset(y: (cardVisible[safe: index] ?? true) ? 0 : 16)
                }
            }
            .padding(.top, cardsTop)
        }
        .frame(width: size.width, height: contentHeight, alignment: .top)
    }

    private func exerciseCard(_ exercise: ExerciseEquivalent, result: ExerciseGameResult, progress: Double) -> some View {
        let color = Color(hex: UInt32(exercise.colorHex, radix: 16) ?? 0xFFFFFF)
        let minutes = exercise.minutes(kcal: result.kcal, weightKG: weightKG)
        return HStack(spacing: 14) {
            Image(systemName: exercise.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.pretendardBold(15))
                    .foregroundStyle(Color.white)
                Text(exercise.detail(kcal: result.kcal, weightKG: weightKG))
                    .font(.pretendardMedium(12))
                    .foregroundStyle(Color(hex: 0xA3A8B3))
            }
            Spacer(minLength: 8)
            CountingText(value: Double(minutes) * progress) { ExerciseEquivalent.durationText(minutes: Int($0.rounded())) }
                .font(.pretendardSemiBold(22))
                .foregroundStyle(Color.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 24)
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .frame(height: Metrics.cardHeight)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name) \(ExerciseEquivalent.durationText(minutes: minutes)), \(exercise.spokenDetail(kcal: result.kcal, weightKG: weightKG))")
    }

    // MARK: - 하단

    /// 하단 버튼: 다른 화면(OnboardingScaffold·기록 화면)처럼 안전 영역 안 아래 4, 좌우 16. 키보드를 따라 올라가지 않는다.
    private func bottomArea(_ size: CGSize) -> some View {
        VStack(spacing: Metrics.noteGap) {
            if showsResult {
                Text(usesFallbackWeight
                     ? "체중 \(Int(weightKG.rounded()))kg 기준 대략적인 시간이에요"
                     : "내 체중으로 계산한 대략적인 시간이에요")
                    .font(.pretendardMedium(12))
                    .foregroundStyle(Color(hex: 0x8A8F9A))
                    .transition(.opacity)
            }
            // 결과 화면은 "다시 담기": 게임을 닫지 않고 처음 연 것과 같은 입력 상태로 돌아간다(결과 화면에서는 뒤로가기를 숨긴다).
            OnboardingBottomButton(
                title: showsResult ? "다시 담기" : "담기",
                isEnabled: showsResult || canStart,
                action: { if showsResult { resetToStart() } else { start() } },
                disabledForegroundColor: Color.gray02
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, Metrics.buttonBottomPadding)
        .frame(width: size.width, height: size.height, alignment: .bottom)
    }

    private var canStart: Bool {
        stage == .input && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 연출

    /// 키보드 완료 키: 키보드만 내린다. 분석은 시작하지 않고 글자도 그대로 둔다(하단 "담기"는 글자가 있으면 활성).
    private func submitFromKeyboard() {
        isInputFocused = false
    }

    private func start() {
        guard canStart else { return }
        let food = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stage = .dropping
        showsFailure = false
        chipText = food
        // 분석은 탭한 순간 바로 시작한다.
        let analyzer = self.analyzer
        analysisFinished = false
        let task = Task { try await analyzer.analyze(food) }
        analysisTask = task
        Task {
            _ = try? await task.value
            analysisFinished = true
        }
        sequenceTask = Task { await runSequence(task) }
    }

    /// 다시 담기: 화면을 처음 연 것과 같은 입력 상태로 되돌린다(글자·그릇·칩·결과·실패 안내, 진행 중인 분석·연출 취소).
    /// 체중은 처음 받은 값 그대로, 저장은 하지 않는다. 결과가 나타날 때처럼 짧은 투명도 전환(동작 줄이기면 바로).
    private func resetToStart() {
        analysisTask?.cancel()
        sequenceTask?.cancel()
        analysisTask = nil
        sequenceTask = nil
        analysisFinished = false
        isInputFocused = false
        var transaction = Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.3))
        transaction.disablesAnimations = reduceMotion
        withTransaction(transaction) {
            text = ""
            stage = .input
            contentLift = 0
            isInputCollapsed = false
            chipVisible = false
            chipText = ""
            resetChip()
            trailLag = .zero
            titleDimmed = false
            bowlSquash = 1
            rippleScale = 0.3
            rippleOpacity = 0
            fillProgress = 0
            glowOpacity = 0.28
            showsSteam = false
            showsWaiting = false
            showsFailure = false
            failedText = ""
            result = nil
            showsResult = false
            countedKcal = 0
            cardProgress = Array(repeating: 0, count: exercises.count)
            cardVisible = Array(repeating: false, count: exercises.count)
        }
    }

    private func runSequence(_ task: Task<ExerciseGameResult, Error>) async {
        // ① 키보드 내림, 입력칸 → 칩
        isInputFocused = false
        resetChip()
        trailLag = .zero
        chipVisible = true
        chipScale = 0.85
        chipOpacity = 0
        Haptics.impact(.light)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.25, bounce: 0.25)) {
            isInputCollapsed = true
            chipScale = 1
            chipOpacity = 1
            titleDimmed = true
        }
        await pause(0.25)

        if reduceMotion {
            await reducedMotionSequence(task)
            return
        }

        // ② 들어 올림
        withAnimation(.easeOut(duration: 0.15)) {
            chipScale = 1.05
            chipOffset = CGSize(width: -22, height: -12)
            chipRotation = -8
        }
        await pause(0.15)

        // 분석이 벌써 실패했으면 그릇 가장자리에 부딪혀 튕겨 나온다.
        if isFinished(task), (try? await task.value) == nil {
            await bounceOffRim(task)
            return
        }

        // ③ 떨어짐: 작은 호(가로 ease-out, 세로 ease-in), 회전 -8°→0°, 크기 1→0.6, 잔상 2개
        let target = fallTarget
        chipMasked = true
        trailVisible = true
        withAnimation(.easeOut(duration: 0.45)) {
            chipOffset.width = target.width
        }
        withAnimation(.easeIn(duration: 0.45)) {
            chipOffset.height = target.height
            chipRotation = 0
            chipScale = 0.6
        }
        await pause(0.45)

        // ④ 닿음: 진동, 그릇 눌림, 물결
        trailVisible = false
        chipVisible = false
        Haptics.impact(.medium)
        bowlSquash = 0.96
        withAnimation(.spring(duration: 0.25, bounce: 0.45)) { bowlSquash = 1 }
        rippleScale = 0.3
        rippleOpacity = 0.9
        withAnimation(.easeOut(duration: 0.4)) {
            rippleScale = 1.05
            rippleOpacity = 0
        }

        // ⑤ 채워짐, 초록 빛 한 번 밝아졌다 가라앉음, 김
        withAnimation(.easeInOut(duration: 0.4)) { fillProgress = 1 }
        withAnimation(.easeOut(duration: 0.15)) { glowOpacity = 0.75 }
        withAnimation(.easeInOut(duration: 0.3)) { showsSteam = true }
        await pause(0.15)
        withAnimation(.easeInOut(duration: 0.45)) { glowOpacity = 0.45 }
        await pause(0.25)

        await finish(task)
    }

    /// 동작 줄이기: 떨어짐·튕김·숫자 올라감 없이 서서히 바뀐다.
    private func reducedMotionSequence(_ task: Task<ExerciseGameResult, Error>) async {
        withAnimation(.easeInOut(duration: 0.3)) {
            chipOpacity = 0
            fillProgress = 1
            glowOpacity = 0.45
            showsSteam = true
        }
        await pause(0.3)
        chipVisible = false
        await finish(task)
    }

    private func finish(_ task: Task<ExerciseGameResult, Error>) async {
        // ⑥ 기다림
        if !isFinished(task) {
            withAnimation(.easeIn(duration: 0.2)) { showsWaiting = true }
        }
        let outcome: ExerciseGameResult?
        do { outcome = try await task.value } catch { outcome = nil }
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) { showsWaiting = false }

        guard let outcome else {
            await rejectFromBowl()
            return
        }
        await showResult(outcome)
    }

    /// ⑦ 결과 전환: 그릇·제목이 흐려지며 결과로(0.3초), kcal 0→값(0.6초), 카드 0.08초 간격, 성공 진동
    private func showResult(_ outcome: ExerciseGameResult) async {
        result = outcome
        countedKcal = reduceMotion ? outcome.kcal : 0
        cardProgress = Array(repeating: reduceMotion ? 1 : 0, count: exercises.count)
        cardVisible = Array(repeating: false, count: exercises.count)
        withAnimation(.easeInOut(duration: 0.3)) {
            showsResult = true
            stage = .result
        }
        Haptics.success()
        UIAccessibility.post(notification: .screenChanged, argument: "\(outcome.title) \(Int(outcome.kcal.rounded()))킬로칼로리")
        await pause(0.15)
        // 그 사이 다시 담기를 눌렀으면 카드 연출을 이어 가지 않는다.
        guard !Task.isCancelled, showsResult else { return }
        withAnimation(.easeOut(duration: 0.6)) { countedKcal = outcome.kcal }
        for index in exercises.indices {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(duration: 0.45, bounce: 0.2).delay(Double(index) * 0.08)) {
                cardVisible[index] = true
            }
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.6).delay(Double(index) * 0.08 + 0.05)) {
                    cardProgress[index] = 1
                }
            }
        }
    }

    /// 빨리 실패한 경우: 칩이 그릇 오른쪽 가장자리에 부딪혀 튕겨 나온다(0.4초) → 입력칸으로 돌아온다.
    private func bounceOffRim(_ task: Task<ExerciseGameResult, Error>) async {
        withAnimation(.easeIn(duration: 0.2)) {
            chipOffset = CGSize(width: rimHit.width, height: rimHit.height)
            chipRotation = 6
            chipScale = 0.9
        }
        await pause(0.2)
        Haptics.impact(.rigid)
        withAnimation(.easeOut(duration: 0.2)) {
            chipOffset = CGSize(width: rimHit.width + 40, height: rimHit.height - 46)
            chipRotation = 24
        }
        await pause(0.2)
        await returnToInput()
    }

    /// 기다린 뒤 실패한 경우: 그릇이 비워지고 칩이 튀어나와 입력칸으로 돌아온다.
    private func rejectFromBowl() async {
        resetChip()
        chipOffset = fallTarget
        chipScale = 0.6
        chipOpacity = 1
        chipMasked = false
        chipVisible = true
        withAnimation(.easeInOut(duration: 0.3)) {
            fillProgress = 0
            glowOpacity = 0.28
            showsSteam = false
        }
        Haptics.impact(.rigid)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .easeOut(duration: 0.4)) {
            chipOffset = CGSize(width: rimHit.width + 40, height: rimHit.height - 46)
            chipRotation = 18
            chipScale = 0.9
        }
        await pause(0.4)
        await returnToInput()
    }

    private func returnToInput() async {
        Haptics.warning()
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
            chipOffset = .zero
            chipRotation = 0
            chipScale = 1
            chipOpacity = 0
            isInputCollapsed = false
            titleDimmed = false
            fillProgress = 0
            glowOpacity = 0.28
            showsSteam = false
        }
        await pause(0.3)
        chipVisible = false
        chipMasked = false
        failedText = text
        withAnimation(.easeIn(duration: 0.2)) {
            showsFailure = true
            stage = .input
        }
        UIAccessibility.post(notification: .announcement, argument: "그 음식은 아직 몰라요. 다른 음식을 담아 볼까요?")
    }

    /// 스크린샷·미리보기용 고정 상태(#49). 애니메이션 없이 그 순간의 화면을 바로 만든다.
    private func applySnapshot() {
        guard let snapshot else { return }
        switch snapshot {
        case .empty:
            break
        case .typing(let food):
            text = food
        case .falling(let food, let fraction):
            text = food
            chipText = food
            stage = .dropping
            isInputCollapsed = true
            titleDimmed = true
            chipVisible = true
            chipMasked = true
            trailVisible = true
            chipRotation = -8 * (1 - fraction)
            chipScale = 1.05 - 0.45 * fraction
            trailLag = CGSize(width: -6, height: 22)
            // 입력칸·그릇 위치를 잰 뒤에 떨어지는 위치를 정한다.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                chipOffset = CGSize(width: -22 * (1 - fraction), height: -12 + (fallTarget.height + 12) * fraction * fraction)
            }
        case .filled(let food):
            text = food
            chipText = food
            stage = .dropping
            isInputCollapsed = true
            titleDimmed = true
            fillProgress = 1
            glowOpacity = 0.45
            showsSteam = true
            showsWaiting = true
        case .result(let outcome):
            result = outcome
            countedKcal = outcome.kcal
            cardProgress = Array(repeating: 1, count: exercises.count)
            cardVisible = Array(repeating: true, count: exercises.count)
            showsResult = true
            stage = .result
        case .failure(let food):
            text = food
            failedText = food
            showsFailure = true
        }
    }

    private func resetChip() {
        chipOffset = .zero
        chipScale = 1
        chipRotation = 0
        chipOpacity = 1
        trailVisible = false
        chipMasked = false
    }

    /// 칩 시작점(입력칸 가운데)에서 그릇 입구 안쪽(입구 가운데보다 조금 아래)까지의 이동량. 실제 배치한 입력칸·그릇 위치로 계산한다.
    private var fallTarget: CGSize {
        CGSize(width: mouth.x - chipStart.x, height: mouth.y + 14 * bowlScaleNow - chipStart.y)
    }
    /// 그릇 오른쪽 테두리에 부딪히는 지점
    private var rimHit: CGSize {
        CGSize(width: mouth.x - chipStart.x + 112 * bowlScaleNow, height: fallTarget.height - 30)
    }

    /// 분석이 끝났는지(성공·실패 모두)
    private func isFinished(_ task: Task<ExerciseGameResult, Error>) -> Bool { analysisFinished }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// 스크린샷·미리보기용 고정 상태
enum ExerciseGameSnapshot {
    case empty
    case typing(String)
    /// 떨어지는 중(0 = 들어 올린 위치, 1 = 그릇 입구)
    case falling(String, Double)
    case filled(String)
    case result(ExerciseGameResult)
    case failure(String)
}

private extension CGSize {
    static func - (lhs: CGSize, rhs: CGSize) -> CGSize { CGSize(width: lhs.width - rhs.width, height: lhs.height - rhs.height) }
    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize { CGSize(width: lhs.width * rhs, height: lhs.height * rhs) }
}

/// 칩의 이동·크기·회전. 시작점은 입력칸 가운데.
private struct ChipMotion: ViewModifier {
    var offset: CGSize
    var scale: CGFloat
    var rotation: Double
    var center: CGPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .position(x: center.x + offset.width, y: center.y + offset.height)
    }
}

/// 0에서 값까지 올라가는 숫자
private struct CountingText: View, Animatable {
    var value: Double
    var format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

/// "계산하고 있어요" + 점 세 개가 차례로 깜빡임
private struct WaitingLabel: View {
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 10, paused: reduceMotion)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 4
            HStack(spacing: 2) {
                Text("계산하고 있어요")
                ForEach(0..<3, id: \.self) { index in
                    Text(".").opacity(reduceMotion || index < step ? 1 : 0.25)
                }
            }
            .font(.pretendardMedium(13))
            .foregroundStyle(Color(hex: 0xA3A8B3))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("계산하고 있어요")
    }
}

private enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

#Preview("담기 · 빈 입력") {
    ExerciseGameView(weightKG: 65, usesFallbackWeight: true, analyzer: ExerciseGameAnalyzer(), snapshot: .empty, onClose: {})
}

#Preview("담기") {
    ExerciseGameView(weightKG: 65, usesFallbackWeight: true, analyzer: ExerciseGameAnalyzer(), snapshot: .typing("먹고 싶은 음식"), onClose: {})
}

#Preview("담기는 순간") {
    ExerciseGameView(weightKG: 65, usesFallbackWeight: true, analyzer: ExerciseGameAnalyzer(), snapshot: .falling("먹고 싶은 음식", 0.55), onClose: {})
}

#Preview("결과") {
    ExerciseGameView(weightKG: 65, usesFallbackWeight: true, analyzer: ExerciseGameAnalyzer(),
                     snapshot: .result(ExerciseGameResult(displayName: "먹고 싶은 음식 1인분", kcal: 927)), onClose: {})
}
