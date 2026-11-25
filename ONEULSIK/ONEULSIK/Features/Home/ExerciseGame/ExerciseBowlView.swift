import SwiftUI

/// 운동 환산 화면(#49)의 그릇. 이미지 없이 SwiftUI 도형으로 그린다. 기준 크기 320×230(Figma "운동 환산 이벤트 시안").
/// 좌표: 입구(테두리 타원) 가운데가 (160, 32), 몸통 반원(지름 280) 바닥이 y=172, 받침이 그 아래 23.
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
    static let mouthCenter = CGPoint(x: 160, y: 32)
    static let innerSize = CGSize(width: 250, height: 48)

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 아래 초록 빛
            Ellipse()
                .fill(Color.exerciseGreen)
                .frame(width: 300, height: 116)
                .blur(radius: 40)
                .opacity(glowOpacity)
                .position(x: 160, y: 168)

            // 바닥 그림자
            Ellipse()
                .fill(Color.black.opacity(0.4))
                .frame(width: 150, height: 14)
                .blur(radius: 6)
                .position(x: 160, y: 198)

            // 받침(굽)
            BowlFootShape()
                .fill(LinearGradient(stops: [
                    .init(color: Color(hex: 0xD3DAE6), location: 0),
                    .init(color: Color(hex: 0xB4BDCD), location: 0.55),
                    .init(color: Color(hex: 0x8C96AA), location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .overlay {
                    BowlFootBottomEdge()
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                }
                .frame(width: 124, height: 23)
                .position(x: 160, y: 170 + 11.5)

            // 몸통: 아래쪽 반원
            BowlBodyShape()
                .fill(LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: Color(hex: 0xE4E9F2), location: 0.6),
                    .init(color: Color(hex: 0xB9C3D6), location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .frame(width: 280, height: 140)
                .position(x: 160, y: 32 + 70)

            // 테두리
            Ellipse()
                .fill(LinearGradient(colors: [.white, Color(hex: 0xEEF1F6)], startPoint: .top, endPoint: .bottom))
                .frame(width: 280, height: 64)
                .position(x: 160, y: 32)

            // 안쪽
            BowlInnerView(fillProgress: fillProgress)
                .frame(width: Self.innerSize.width, height: Self.innerSize.height)
                .position(x: 160, y: 32)

            if showsSteam {
                BowlSteamView(reduceMotion: reduceMotion)
                    .frame(width: 120, height: 70)
                    .position(x: 160, y: -24)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
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

/// 받침(굽): 위는 몸통 바닥에 붙어 폭 92, 아래로 곡선으로 벌어져 밑면 폭 약 120, 밑면 모서리와 아래 변이 둥글다.
struct BowlFootShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let topInset = (w - 92) / 2
        let bottomInset = (w - 120) / 2
        var path = Path()
        path.move(to: CGPoint(x: topInset, y: 0))
        path.addLine(to: CGPoint(x: w - topInset, y: 0))
        // 오른쪽 옆면: 아래로 갈수록 벌어지는 곡선
        path.addCurve(to: CGPoint(x: w - bottomInset, y: h - 5),
                      control1: CGPoint(x: w - topInset + 2, y: h * 0.45),
                      control2: CGPoint(x: w - bottomInset - 4, y: h * 0.7))
        // 밑면 오른쪽 모서리
        path.addQuadCurve(to: CGPoint(x: w - bottomInset - 6, y: h), control: CGPoint(x: w - bottomInset + 1, y: h))
        // 아래 변: 살짝 아래로 휜 곡선
        path.addQuadCurve(to: CGPoint(x: bottomInset + 6, y: h), control: CGPoint(x: w / 2, y: h + 3))
        path.addQuadCurve(to: CGPoint(x: bottomInset, y: h - 5), control: CGPoint(x: bottomInset - 1, y: h))
        path.addCurve(to: CGPoint(x: topInset, y: 0),
                      control1: CGPoint(x: bottomInset + 4, y: h * 0.7),
                      control2: CGPoint(x: topInset - 2, y: h * 0.45))
        path.closeSubpath()
        return path
    }
}

/// 받침 밑면 가장자리의 반사선
private struct BowlFootBottomEdge: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let inset = (w - 120) / 2 + 8
        var path = Path()
        path.move(to: CGPoint(x: inset, y: h - 1.5))
        path.addQuadCurve(to: CGPoint(x: w - inset, y: h - 1.5), control: CGPoint(x: w / 2, y: h + 1.5))
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
