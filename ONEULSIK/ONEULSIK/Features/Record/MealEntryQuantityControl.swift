import SwiftUI

struct MealEntryQuantityControl: View {
    let item: MealEntryItem
    let onChange: (Double?) -> Void

    @State private var text: String
    @FocusState private var isEditing: Bool

    init(item: MealEntryItem, onChange: @escaping (Double?) -> Void) {
        self.item = item
        self.onChange = onChange
        _text = State(initialValue: Self.formatted(item.quantity))
    }

    private var parsedQuantity: Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: #"^\d{1,5}(\.\d{0,2})?$"#, options: .regularExpression) != nil,
              let value = Double(normalized), (0.1...10000).contains(value) else { return nil }
        return value
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let buttonWidth = min(104, geometry.size.width * 0.3)
                HStack(spacing: 0) {
                    stepButton("minus", width: buttonWidth, enabled: (parsedQuantity ?? 0) > 0.1) {
                        adjust(by: -item.quantityStep)
                    }
                    TextField("양", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($isEditing)
                    .accessibilityLabel("\(item.food.name) 수량 직접 입력, 단위 \(item.quantityUnit)")
                    .font(.pretendardSemiBold(16))
                    .foregroundStyle(Color.black01)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .contentShape(Rectangle())
                    .onTapGesture { isEditing = true }
                    stepButton("plus", width: buttonWidth, enabled: (parsedQuantity ?? 10000) < 10000) {
                        adjust(by: item.quantityStep)
                    }
                }
                .background(Color.gray02.opacity(0.4), in: Capsule())
            }
            .frame(height: 40)

            if parsedQuantity == nil {
                Text("0.1~10,000 사이의 양을 입력해주세요")
                    .font(.pretendardMedium(12))
                    .foregroundStyle(Color.red01)
            } else if let description = item.basisDescription {
                Text(description)
                    .font(.pretendardMedium(12))
                    .foregroundStyle(Color.gray04)
            }
        }
        .onChange(of: text) { _, _ in onChange(parsedQuantity) }
        .onChange(of: item.quantity) { _, quantity in
            guard !isEditing else { return }
            text = Self.formatted(quantity)
        }
    }

    private func stepButton(_ symbol: String, width: CGFloat, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(symbol == "minus" ? "quantityMinus" : "quantityPlus")
                .renderingMode(.original)
                .frame(width: 18, height: 18)
                .frame(width: width, height: 40)
                .background(enabled ? Color("quantityButtonGray") : Color.gray03, in: RoundedRectangle(cornerRadius: 32))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("\(item.food.name) \(symbol == "minus" ? "양 줄이기" : "양 늘리기")")
    }

    private func adjust(by step: Double) {
        guard let quantity = parsedQuantity else { return }
        isEditing = false
        let increment = abs(step)
        let position = quantity / increment
        let nextPosition = step > 0
            ? floor(position + 0.000001) + 1
            : ceil(position - 0.000001) - 1
        text = Self.formatted(min(10000, max(0.1, nextPosition * increment)))
    }

    private static func formatted(_ quantity: Double) -> String {
        quantity.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }
}
