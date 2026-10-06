import SwiftUI
import UIKit

struct FoodQuantityPresentation: View {
    let food: FoodCatalogItem
    let onCancel: () -> Void
    let onComplete: (FoodAmountSelection) -> Void

    @State private var keyboardFrame = CGRect.null

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            let overlap = frame.intersection(keyboardFrame)
            let keyboardOverlap = overlap.isNull ? 0 : overlap.height

            ZStack(alignment: .bottom) {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if keyboardOverlap > 0 {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        } else {
                            onCancel()
                        }
                    }
                    .accessibilityHidden(true)

                FoodQuantityView(
                    food: food,
                    keyboardOverlap: keyboardOverlap,
                    onCancel: onCancel,
                    onComplete: onComplete
                )
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.gray01)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                .accessibilityAddTraits(.isModal)
                .padding(.bottom, keyboardOverlap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .null
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardFrame = .null
            }
        }
    }
}
