import SwiftUI

private struct MealEntryInputFrames: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private struct MealEntryKeyboardDismissal: ViewModifier {
    @State private var inputFrames: [CGRect] = []

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onPreferenceChange(MealEntryInputFrames.self) { inputFrames = $0 }
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .global)
                    .onEnded { tap in
                        guard !inputFrames.contains(where: { $0.contains(tap.location) }) else { return }
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
            )
    }
}

extension View {
    func mealEntryInputRegion() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: MealEntryInputFrames.self, value: [geometry.frame(in: .global)])
            }
        }
    }

    func dismissMealEntryKeyboardOnOutsideTap() -> some View {
        modifier(MealEntryKeyboardDismissal())
    }
}
