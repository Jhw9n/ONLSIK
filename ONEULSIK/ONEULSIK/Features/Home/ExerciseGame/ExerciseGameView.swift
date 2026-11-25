import SwiftUI
import UIKit

/// 홈 배너에서 여는 "먹고 싶은 음식 → 운동 시간" 화면(#49). Figma "운동 환산 이벤트 시안" 최종본 기준(375×812).
/// - 담기(A) → 담기는 연출(B) → 결과(C). 결과는 식사 기록으로 저장하지 않는다.
/// - 분석은 기존 식사 입력 분석 서비스(ExerciseGameAnalyzer → AIMealEntryService)의 열량만 쓴다.
struct ExerciseGameView: View {
    let weightKG: Double
    let usesFallbackWeight: Bool
    let analyzer: ExerciseGameAnalyzer
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isInputFocused: Bool

    @State private var text = ""
    @State private var stage = Stage.input
    @State private var keyboardHeight: CGFloat = 0

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
    @State private var analysisFinished = false
    @State private var layout = GameLayout(size: CGSize(width: 375, height: 812), safeTop: 44, safeBottom: 34)

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

    init(weightKG: Double, usesFallbackWeight: Bool, analyzer: ExerciseGameAnalyzer,
         snapshot: ExerciseGameSnapshot? = nil, onClose: @escaping () -> Void) {
        self.weightKG = weightKG
        self.usesFallbackWeight = usesFallbackWeight
        self.analyzer = analyzer
        self.snapshot = snapshot
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = GameLayout(size: proxy.size, safeTop: proxy.safeAreaInsets.top, safeBottom: proxy.safeAreaInsets.bottom)
            ZStack(alignment: .topLeading) {
                background
                bubbles(layout)

                Group {
                    if showsResult, let result {
                        resultContent(result, layout: layout)
                            .transition(.opacity)
                    } else {
                        inputContent(layout)
                            .transition(.opacity)
                    }
                }
                .offset(y: -contentLift(layout))

                bottomArea(layout)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear {
                self.layout = layout
                applySnapshot()
            }
            .onChange(of: proxy.size) { self.layout = layout }
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenHeight = UIScreen.main.bounds.height
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = max(0, screenHeight - frame.minY)
            }
        }
        .onDisappear { analysisTask?.cancel() }
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

    private func bubbles(_ layout: GameLayout) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                bubble(size: 54, tint: Color.exerciseLightGreen, time: time, period: 4.6, phase: 0)
                    .position(x: layout.x(48), y: layout.y(236))
                bubble(size: 40, tint: Color(hex: 0x3FC6A8), time: time, period: 5.4, phase: 1.7)
                    .position(x: layout.x(334), y: layout.y(214))
                bubble(size: 22, tint: .white, time: time, period: 3.9, phase: 3.1)
                    .position(x: layout.x(306), y: layout.y(270))
            }
            .opacity(showsResult ? 0.3 : 1)
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

    private func inputContent(_ layout: GameLayout) -> some View {
        let bowlScale = layout.bowlScale
        let bowlTop = layout.y(366)
        let mouth = CGPoint(x: layout.centerX, y: bowlTop + ExerciseBowlView.mouthCenter.y * bowlScale)
        let inputCenter = CGPoint(x: layout.centerX, y: layout.y(292) + 28)
        return ZStack(alignment: .topLeading) {
            titleBlock(lines: ["먹고 싶은 음식을", "그릇에 담아보세요"], subtitle: "운동으로 얼마나 빼야 하는지 알려드려요")
                .frame(width: layout.size.width)
                .position(x: layout.centerX, y: layout.y(84) + 52)
                .opacity(titleDimmed ? 0.35 : 1)

            ExerciseBowlView(fillProgress: fillProgress, glowOpacity: glowOpacity, showsSteam: showsSteam, reduceMotion: reduceMotion)
                .overlay(alignment: .topLeading) { ripple }
                .scaleEffect(x: 1, y: bowlSquash, anchor: .bottom)
                .scaleEffect(bowlScale, anchor: .top)
                .frame(width: ExerciseBowlView.size.width * bowlScale, height: ExerciseBowlView.size.height * bowlScale, alignment: .top)
                .position(x: layout.centerX, y: bowlTop + ExerciseBowlView.size.height * bowlScale / 2)

            if showsWaiting {
                WaitingLabel(reduceMotion: reduceMotion)
                    .position(x: layout.centerX, y: bowlTop + ExerciseBowlView.size.height * bowlScale + 14)
                    .transition(.opacity)
            }

            inputField
                .frame(width: min(287, layout.size.width - 48), height: 56)
                .scaleEffect(x: isInputCollapsed ? 0.4 : 1, y: isInputCollapsed ? 0.75 : 1)
                .opacity(isInputCollapsed ? 0 : 1)
                .position(inputCenter)
                .allowsHitTesting(stage == .input)

            if showsFailure {
                Text("그 음식은 아직 몰라요. 다른 음식을 담아 볼까요?")
                    .font(.pretendardMedium(13))
                    .foregroundStyle(Color(hex: 0xA3A8B3))
                    .multilineTextAlignment(.center)
                    .frame(width: layout.size.width - 32)
                    .position(x: layout.centerX, y: inputCenter.y + 28 + 20)
                    .transition(.opacity)
            }

            chipLayer(start: inputCenter, mouth: mouth, bowlScale: bowlScale, size: layout.size)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
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

    private var inputField: some View {
        HStack(spacing: 10) {
            TextField("", text: $text, prompt: Text("먹고 싶은 음식을 적어주세요").foregroundStyle(Color(hex: 0x9AA0AB)))
                .font(.pretendardMedium(16))
                .foregroundStyle(Color(hex: 0x1D1D1D))
                .tint(Color.exerciseGreen)
                .submitLabel(.done)
                .focused($isInputFocused)
                .onSubmit(start)
                .onChange(of: text) { _, newValue in
                    if showsFailure, newValue != failedText { withAnimation(.easeOut(duration: 0.2)) { showsFailure = false } }
                }
                .accessibilityLabel("먹고 싶은 음식")
                .accessibilityHint("음식 이름을 적고 담기를 누르면 운동 시간으로 알려드려요")

            Button(action: start) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Color.exerciseGreen, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canStart)
            .opacity(canStart ? 1 : 0.5)
            .accessibilityLabel("담기")
        }
        .padding(.leading, 22)
        .padding(.trailing, 8)
        .frame(maxHeight: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture { isInputFocused = true }
    }

    /// 음식 이름 칩과 잔상. 그릇 입구보다 아래로 내려가면 입구 안쪽 타원 밖은 가려져 그릇 속으로 들어가 보인다.
    private func chipLayer(start: CGPoint, mouth: CGPoint, bowlScale: CGFloat, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
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
                    Rectangle().frame(width: size.width, height: mouth.y)
                    Ellipse()
                        .frame(width: ExerciseBowlView.innerSize.width * bowlScale, height: ExerciseBowlView.innerSize.height * bowlScale)
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

    private func titleBlock(lines: [String], subtitle: String?) -> some View {
        VStack(spacing: 10) {
            Text(lines.joined(separator: "\n"))
                .font(.pretendardBold(30))
                .lineSpacing(9)
                .foregroundStyle(Color.exerciseGreen)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.pretendardMedium(15))
                    .foregroundStyle(Color(hex: 0xA3A8B3))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 화면 C

    private func resultContent(_ result: ExerciseGameResult, layout: GameLayout) -> some View {
        let cardWidth = min(343, layout.size.width - 32)
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 6) {
                Text(result.title)
                    .font(.pretendardBold(30))
                    .foregroundStyle(Color.exerciseGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 16)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    CountingText(value: countedKcal) { "\(Int($0.rounded()))" }
                        .font(.pretendardBold(48))
                    Text("kcal")
                        .font(.pretendardBold(24))
                }
                .foregroundStyle(Color.exerciseGreen)
                .monospacedDigit()
            }
            .frame(width: layout.size.width)
            .position(x: layout.centerX, y: layout.y(84) + 52)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(result.title) \(Int(result.kcal.rounded()))킬로칼로리")
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 14) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    exerciseCard(exercise, result: result, progress: cardProgress[safe: index] ?? 1)
                        .frame(width: cardWidth)
                        .opacity((cardVisible[safe: index] ?? true) ? 1 : 0)
                        .offset(y: (cardVisible[safe: index] ?? true) ? 0 : 16)
                }
            }
            .position(x: layout.centerX, y: layout.y(252) + (98 * 3 + 14 * 2) / 2)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
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
        .frame(height: 98)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name) \(ExerciseEquivalent.durationText(minutes: minutes)), \(exercise.spokenDetail(kcal: result.kcal, weightKG: weightKG))")
    }

    // MARK: - 하단

    private func bottomArea(_ layout: GameLayout) -> some View {
        VStack(spacing: 16) {
            if showsResult {
                Text(usesFallbackWeight
                     ? "체중 \(Int(weightKG.rounded()))kg 기준 대략적인 시간이에요"
                     : "내 체중으로 계산한 대략적인 시간이에요")
                    .font(.pretendardMedium(12))
                    .foregroundStyle(Color(hex: 0x8A8F9A))
                    .transition(.opacity)
            }
            OnboardingBottomButton(
                title: showsResult ? "닫기" : "담기",
                isEnabled: showsResult || canStart,
                action: showsResult ? onClose : start,
                disabledForegroundColor: Color.gray02
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, max(layout.safeBottom, keyboardHeight) + 4)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .bottom)
    }

    /// 키보드가 입력칸·+ 버튼을 가리면 화면을 올린다.
    private func contentLift(_ layout: GameLayout) -> CGFloat {
        guard keyboardHeight > 0, !showsResult else { return 0 }
        let inputBottom = layout.y(292) + 56
        let buttonTop = layout.size.height - keyboardHeight - 4 - 52
        return max(0, inputBottom + 16 - buttonTop)
    }

    private var canStart: Bool {
        stage == .input && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 연출

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
        Task { await runSequence(task) }
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
            chipOffset = CGSize(width: -22 * (1 - fraction), height: -12 + (fallTarget.height + 12) * fraction * fraction)
            chipRotation = -8 * (1 - fraction)
            chipScale = 1.05 - 0.45 * fraction
            trailLag = CGSize(width: -6, height: 22)
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

    /// 칩 시작점(입력칸 가운데)에서 그릇 입구 안쪽까지의 이동량(마지막으로 배치한 화면 크기 기준)
    private var fallTarget: CGSize { CGSize(width: 0, height: layout.fallDistance) }
    /// 그릇 오른쪽 테두리에 부딪히는 지점
    private var rimHit: CGSize { CGSize(width: 112 * layout.bowlScale, height: layout.fallDistance - 30) }

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

/// 375×812 기준 배치를 기기 크기에 맞춘다. 세로 위치는 안전 영역 안 높이(기준 734) 비율로 늘이고 줄인다.
struct GameLayout {
    let size: CGSize
    let safeTop: CGFloat
    let safeBottom: CGFloat

    var centerX: CGFloat { size.width / 2 }
    var vScale: CGFloat {
        let content = size.height - safeTop - safeBottom
        return min(1.15, max(0.78, content / 734))
    }
    var hScale: CGFloat { min(1.1, size.width / 375) }
    var bowlScale: CGFloat { min(1, vScale, hScale) }
    /// 기준 화면에서 위에서 design만큼 떨어진 위치(안전 영역 기준)
    func y(_ design: CGFloat) -> CGFloat { safeTop + (design - 44) * vScale }
    func x(_ design: CGFloat) -> CGFloat { design * size.width / 375 }
    /// 입력칸 가운데에서 그릇 입구 안쪽(입구 가운데보다 조금 아래)까지
    var fallDistance: CGFloat {
        let inputCenter = y(292) + 28
        let mouth = y(366) + ExerciseBowlView.mouthCenter.y * bowlScale
        return mouth + 14 * bowlScale - inputCenter
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

#Preview("담기") {
    ExerciseGameView(weightKG: 65, usesFallbackWeight: true, analyzer: ExerciseGameAnalyzer(), snapshot: .typing("먹고 싶은 음식"), onClose: {})
}

#Preview("결과") {
    ExerciseGameView(weightKG: 65, usesFallbackWeight: true, analyzer: ExerciseGameAnalyzer(),
                     snapshot: .result(ExerciseGameResult(displayName: "먹고 싶은 음식 1인분", kcal: 927)), onClose: {})
}
