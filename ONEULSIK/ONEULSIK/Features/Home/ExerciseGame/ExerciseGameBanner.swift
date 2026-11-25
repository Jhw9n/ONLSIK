import SwiftUI

/// 운동 환산 화면(#49)을 켜고 끄는 곳. 전시 뒤 배너를 숨기려면 false로 바꾼다.
enum ExerciseGameFeature {
    static let isBannerEnabled = true
}

/// 홈의 "먹고 싶은 음식 담아보기" 배너(343×96). 누르면 운동 환산 화면을 연다.
struct ExerciseGameBanner: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ExerciseBowlBadge()
                VStack(alignment: .leading, spacing: 4) {
                    Text("먹고 싶은 음식 담아보기")
                        .font(.pretendardBold(16))
                        .foregroundStyle(Color.white)
                    Text("운동으로 얼마나 빼야 할지 알려드려요")
                        .font(.pretendardSemiBold(12))
                        .foregroundStyle(Color.exerciseLightGreen)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(
                LinearGradient(colors: [Color(hex: 0x1E2A44), Color(hex: 0x18191F)], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("먹고 싶은 음식 담아보기. 운동으로 얼마나 빼야 할지 알려드려요")
        .accessibilityAddTraits(.isButton)
    }
}
