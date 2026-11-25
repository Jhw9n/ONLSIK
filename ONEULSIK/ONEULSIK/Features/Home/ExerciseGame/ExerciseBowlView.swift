import SwiftUI

/// 운동 환산 화면(#49)의 그릇. 이미지 없이 SwiftUI 도형으로 그린다. 기준 크기 320×230(Figma "개발" 페이지 섹션 2312:534의 Bowl).
/// 그리는 순서(아래부터): 초록 빛 → 바닥 그림자 → 몸통·받침 한 도형(BowlShape) → 받침 하이라이트 → 테두리 → 안쪽 → 김.
/// 좌표: 테두리(280×64)와 안쪽(250×48) 가운데가 (160, 80). 몸통과 받침은 Path 하나라 눌림 애니메이션에서 같이 움직인다.
struct ExerciseBowlView: View {
    /// 안쪽이 초록으로 차오른 정도(0...1)
    var fillProgress: Double
    /// 아래 초록 빛의 투명도(기본 0.28, 채워지면 0.45, 닿는 순간 잠깐 더 밝게)
    var glowOpacity: Double
    /// 김이 보이는지(채워진 상태)
    var showsSteam: Bool
    /// 동작 줄이기(김 움직임 없음)
    var reduceMotion: Bool

    static let size = CGSize(width: 320, height: 230)
    static let mouthCenter = CGPoint(x: 160, y: 80)
    static let innerSize = CGSize(width: 250, height: 48)

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 아래 초록 빛(10.5, 165, 300×116)
            Ellipse()
                .fill(Color.exerciseGreen)
                .frame(width: 300, height: 116)
                .blur(radius: 40)
                .opacity(glowOpacity)
                .position(x: 160.5, y: 223)

            // 바닥 그림자(85, 222, 150×14)
            Ellipse()
                .fill(Color.black.opacity(0.4))
                .frame(width: 150, height: 14)
                .blur(radius: 6)
                .position(x: 160, y: 229)

            // 몸통과 받침(한 도형)
            BowlShape()
                .fill(LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: Color(hex: 0xE4E9F2), location: 0.45),
                    .init(color: Color(hex: 0xB9C3D6), location: 0.8),
                    .init(color: Color(hex: 0x8C96AA), location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .frame(width: Self.size.width, height: Self.size.height)

            // 받침 하이라이트(112, 225, 96×2, 투명도 0.7)
            BowlFootHighlight()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .opacity(0.7)
                .frame(width: Self.size.width, height: Self.size.height)

            // 테두리(20, 48, 280×64)
            Ellipse()
                .fill(LinearGradient(colors: [.white, Color(hex: 0xEEF1F6)], startPoint: .top, endPoint: .bottom))
                .frame(width: 280, height: 64)
                .position(x: 160, y: 80)

            // 안쪽(35, 56, 250×48)
            BowlInnerView(fillProgress: fillProgress)
                .frame(width: Self.innerSize.width, height: Self.innerSize.height)
                .position(Self.mouthCenter)

            if showsSteam {
                BowlSteamView(reduceMotion: reduceMotion)
                    .frame(width: 120, height: 70)
                    .position(x: 160, y: 11)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// 그릇 몸통과 받침을 한 Path로(320×230 기준 좌표, 프레임 크기에 맞춰 같은 비율로 늘이고 줄인다).
struct BowlShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 320, sy = rect.height / 230
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(20, 80))
        path.addCurve(to: p(113.4, 212), control1: p(20, 139.3), control2: p(57.5, 192.25))
        path.addCurve(to: p(101, 224.5), control1: p(112, 219), control2: p(106, 222))
        path.addCurve(to: p(103, 231), control1: p(96, 226.5), control2: p(97, 230))
        path.addCurve(to: p(217, 231), control1: p(125, 233.6), control2: p(195, 233.6))
        path.addCurve(to: p(219, 224.5), control1: p(223, 230), control2: p(224, 226.5))
        path.addCurve(to: p(206.6, 212), control1: p(214, 222), control2: p(208, 219))
        path.addCurve(to: p(300, 80), control1: p(262.5, 192.25), control2: p(300, 139.3))
        path.closeSubpath()
        return path
    }
}

/// 받침 밑면의 반사선(112, 225에서 폭 96, 높이 2)
private struct BowlFootHighlight: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 320, sy = rect.height / 230
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 112 * sx, y: rect.minY + 225 * sy))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 208 * sx, y: rect.minY + 225 * sy),
                          control: CGPoint(x: rect.minX + 160 * sx, y: rect.minY + 229 * sy))
        return path
    }
}

/// 그릇 안쪽 타원. 빈 상태(회색)에서 아래부터 초록으로 차오른다.
private struct BowlInnerView: View {
    var fillProgress: Double

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack {
                Ellipse()
                    .fill(LinearGradient(colors: [Color(hex: 0xC3CBDA), Color(hex: 0xE6EAF1)], startPoint: .top, endPoint: .bottom))

                ZStack {
                    Ellipse()
                        .fill(LinearGradient(colors: [Color(hex: 0x2E8F43), Color.exerciseLightGreen], startPoint: .top, endPoint: .bottom))
                    // 안쪽 그림자(검정 18%, 아래로 4, 흐림 8)
                    Ellipse()
                        .stroke(Color.black.opacity(0.18), lineWidth: 8)
                        .offset(y: 4)
                        .blur(radius: 8)
                        .clipShape(Ellipse())
                    // 가운데 위쪽 밝은 빛
                    Ellipse()
                        .fill(Color(hex: 0xD9FFE2).opacity(0.55))
                        .frame(width: 160, height: 18)
                        .blur(radius: 8)
                        .offset(y: -height * 0.18)
                }
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: height * max(0, min(1, fillProgress)))
                }
            }
        }
    }
}

/// 아래쪽 반원(지름 = 폭). 위 변이 그릇 입구 가운데 선에 붙는다.
struct BowlBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// 김: 흰색 S자 선 3줄. 0.2초 시간차로 올라왔다 사라지기를 반복한다.
private struct BowlSteamView: View {
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 18) {
                ForEach(0..<3, id: \.self) { index in
                    let cycle = 1.6
                    let phase = reduceMotion ? 0.5 : ((time - Double(index) * 0.2).truncatingRemainder(dividingBy: cycle) + cycle)
                        .truncatingRemainder(dividingBy: cycle) / cycle
                    SteamCurve()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 14, height: 44)
                        .blur(radius: 3)
                        .opacity(0.22 * sin(Double.pi * phase))
                        .offset(y: reduceMotion ? 0 : 10 - 22 * phase)
                }
            }
        }
    }
}

private struct SteamCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.midY),
                      control1: CGPoint(x: rect.minX - 2, y: rect.maxY - rect.height * 0.15),
                      control2: CGPoint(x: rect.minX - 2, y: rect.midY + rect.height * 0.15))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                      control1: CGPoint(x: rect.maxX + 2, y: rect.midY - rect.height * 0.15),
                      control2: CGPoint(x: rect.maxX + 2, y: rect.minY + rect.height * 0.15))
        return path
    }
}

/// 홈 배너의 작은 그릇(56pt): 흰 몸통 반원 + 안쪽 초록 타원, 흰 테두리 2pt
struct ExerciseBowlBadge: View {
    var body: some View {
        ZStack(alignment: .top) {
            BowlBodyShape()
                .fill(Color.white)
                .frame(width: 52, height: 26)
                .offset(y: 16)
            Ellipse()
                .fill(LinearGradient(colors: [Color(hex: 0x2E8F43), Color.exerciseLightGreen], startPoint: .top, endPoint: .bottom))
                .overlay { Ellipse().stroke(Color.white, lineWidth: 2) }
                .frame(width: 52, height: 16)
                .offset(y: 8)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

extension Color {
    /// 운동 환산 화면의 초록(#4AC364, 앱의 green03과 같은 값)
    static let exerciseGreen = Color(hex: 0x4AC364)
    static let exerciseLightGreen = Color(hex: 0x7FE79A)

    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
