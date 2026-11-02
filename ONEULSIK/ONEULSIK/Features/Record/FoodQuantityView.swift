import SwiftUI

struct FoodQuantityView: View {
    let food: FoodCatalogItem
    let keyboardOverlap: CGFloat
    let onCancel: () -> Void
    let onComplete: (FoodAmountSelection) -> Void

    @State private var amountText: String
    @State private var usesDirectAmount: Bool
    @State private var portionEstimate: String?
    @FocusState private var isAmountFocused: Bool

    init(food: FoodCatalogItem, keyboardOverlap: CGFloat = 0, onCancel: @escaping () -> Void, onComplete: @escaping (FoodAmountSelection) -> Void) {
        self.food = food
        self.keyboardOverlap = keyboardOverlap
        self.onCancel = onCancel
        self.onComplete = onComplete
        let amount = food.representativePortion?.grams ?? food.baseAmount
        _amountText = State(initialValue: amount.formatted(.number.grouping(.never).precision(.fractionLength(0...2))))
        _usesDirectAmount = State(initialValue: food.representativePortion == nil)
    }

    private var amount: Double? { FoodAmountSelection.parse(amountText) }
    private var portion: FoodPortion? { food.representativePortion }
    private var isKeyboardVisible: Bool { keyboardOverlap > 0 }
    private var selection: FoodAmountSelection? {
        guard let amount else { return nil }
        return FoodAmountSelection(amount: amount, portion: usesDirectAmount ? nil : portion)
    }

    private var guidance: String {
        if amount == nil {
            return "0.1~10,000\(food.amountUnit) · 소수 둘째 자리까지 입력 가능"
        }
        if usesDirectAmount {
            if portion == nil, let portionEstimate {
                return "AI 추정: \(portionEstimate)"
            }
            return "포장지의 무게·용량을 참고해주세요"
        }
        return "약 \((amount ?? portion?.grams ?? food.baseAmount).formatted(.number.precision(.fractionLength(0...2))))g · 대표 분량 기준"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("닫기")
                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 60)
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .onTapGesture { isAmountFocused = false }

            VStack(alignment: .leading, spacing: usesDirectAmount ? 26 : 28) {
                foodInformation
                    .contentShape(Rectangle())
                    .onTapGesture { isAmountFocused = false }
                if usesDirectAmount {
                    directAmountControl
                } else if let portion {
                    portionControl(portion)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, usesDirectAmount ? 2 : 4)

            if !isKeyboardVisible {
                if let portion {
                    Button(usesDirectAmount ? "\(portion.unit) 단위로 선택" : "무게 직접 입력") {
                        isAmountFocused = false
                        usesDirectAmount.toggle()
                    }
                    .font(.pretendardMedium(12))
                    .foregroundStyle(Color.green03)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)
                }
                if !food.source.isEmpty {
                    Text("영양정보 출처: \(food.source)")
                        .font(.pretendardMedium(10))
                        .foregroundStyle(Color.gray03)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, portion == nil ? 12 : 0)
                }
                Button {
                    guard let selection else { return }
                    isAmountFocused = false
                    onComplete(selection)
                } label: {
                    Text("완료")
                        .font(.pretendardSemiBold(16))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(selection == nil ? Color.gray03 : Color.green03, in: Capsule())
                }
                .disabled(selection == nil)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, portion == nil && food.source.isEmpty ? 24 : 12)
                .padding(.bottom, 38)
            }
        }
        .padding(.bottom, isKeyboardVisible ? 20 : 0)
        .foregroundStyle(Color.black01)
        .background(Color.gray01)
        .preferredColorScheme(.light)
        .task(id: food) {
            portionEstimate = nil
            guard portion == nil else { return }
            let estimate = await AIFoodPortionService.shared.estimate(for: food)
            guard !Task.isCancelled else { return }
            portionEstimate = estimate
        }
        .task(id: usesDirectAmount) {
            guard usesDirectAmount else {
                isAmountFocused = false
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()
                isAmountFocused = true
            } catch {
                return
            }
        }
    }

    private var foodInformation: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(food.recordedName)
                    .font(.pretendardSemiBold(18))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(amount.map {
                    food.nutrition(for: $0 / food.baseAmount).calories.formatted(.number.precision(.fractionLength(0))) + "kcal"
                } ?? "— kcal")
                .font(.pretendardMedium(16))
                .fixedSize()
            }
            Text(guidance)
                .font(.pretendardMedium(12))
                .foregroundStyle(Color.gray04)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var directAmountControl: some View {
        HStack(spacing: 12) {
            TextField("예: 150", text: $amountText)
                .keyboardType(.decimalPad)
                .focused($isAmountFocused)
                .font(.pretendardSemiBold(20))
                .accessibilityLabel("섭취량 \(food.amountUnit)")
            Text(food.amountUnit)
                .font(.pretendardMedium(16))
                .foregroundStyle(Color.gray04)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func portionControl(_ portion: FoodPortion) -> some View {
        let count = (amount ?? portion.grams) / portion.grams
        return HStack(spacing: 0) {
            quantityButton("minus", enabled: count > 0.5) {
                setAmount(max(0.5, (ceil(count * 2) - 1) / 2) * portion.grams)
            }
            Text("\(count < 0.01 ? "0.01 미만" : count.formatted(.number.precision(.fractionLength(0...2))))\(portion.unit)")
                .font(.pretendardSemiBold(16))
                .frame(maxWidth: .infinity)
            quantityButton("plus", enabled: (floor(count * 2) + 1) / 2 * portion.grams <= 10_000) {
                setAmount((floor(count * 2) + 1) / 2 * portion.grams)
            }
        }
        .background(Color.gray02.opacity(0.4), in: Capsule())
    }

    private func quantityButton(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 104, height: 44)
                .background(enabled ? Color("quantityButtonGray") : Color.gray03, in: RoundedRectangle(cornerRadius: 32))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(name == "minus" ? "반 분량 줄이기" : "반 분량 늘리기")
    }

    private func setAmount(_ amount: Double) {
        amountText = amount.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }
}

#Preview("대표 분량 · 밥") {
    FoodQuantityView(food: FoodCatalogService.previewFood, onCancel: {}, onComplete: { _ in })
}

#Preview("직접 입력 · 음료") {
    FoodQuantityView(
        food: FoodCatalogItem(id: "preview-drink", name: "음료", servingUnit: "회", servingGrams: 0,
                              nutrition: .zero, servingMilliliters: 100, brand: "예시 브랜드"),
        onCancel: {}, onComplete: { _ in }
    )
}
