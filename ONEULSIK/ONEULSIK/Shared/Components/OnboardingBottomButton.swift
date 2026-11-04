import SwiftUI

struct OnboardingBottomButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    var disabledForegroundColor: Color = Color("gray01")

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.pretendardSemiBold(16))
                .foregroundStyle(isEnabled ? Color("gray01") : disabledForegroundColor)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isEnabled ? Color("green03") : Color("gray04"))
                .clipShape(Capsule())
        }
        .buttonStyle(BottomActionButtonStyle())
        .disabled(!isEnabled)
    }
}

private struct BottomActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
