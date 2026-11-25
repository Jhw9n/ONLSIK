import Foundation

/// 식약처 음식 DB의 mL 자료로 기록된 고체 음식의 분량 표시 규칙(2026-11-25 사용자 결정, #43). 표시만 바꾸고
/// 저장 값·영양 계산·분량 근거는 그대로다. 음식 DB의 mL는 부피라 g으로 바꾸면 무게가 실제와 달라진다(예: 피자 4조각 800mL).
/// - 국물·면(VolumeAsWeight.json 판정, excludeNames 제외): 이 프로젝트가 이미 1mL=1g으로 보므로 같은 숫자를 g으로 보인다.
/// - 그 밖의 음식: mL 숫자를 숨기고 수량·단위와 열량만 보인다.
/// - mL를 그대로 보이는 경우(음료 판정은 기존 데이터 기준):
///   - 술·음료 표(DrinkReferences.json)의 자료이거나 그 이름인 것
///   - 음식 DB 자료가 아닌 것(식품코드가 D로 시작하지 않음: 가공식품·원재료. 음료·유제품 등 제품 표시 용량)
///   - 마시는 용기 단위(DrinkReferences.json plausibleMilliliters의 병·캔·잔·컵)로 기록한 것
///   - 사용자가 g·mL로 양을 직접 적은 것(단위가 mL이거나 분량 근거가 entered)
nonisolated enum MealAmountDisplay {
    enum Style: Equatable {
        /// 자료 단위 그대로(g 자료는 g, 음료 등 mL 자료는 mL)
        case asIs
        /// 같은 숫자를 g으로
        case grams
        /// 숫자를 숨김
        case hidden
    }

    static func style(foodID: String, name: String, servingUnit: String, usesMilliliters: Bool, isEntered: Bool) -> Style {
        guard usesMilliliters, !isEntered, servingUnit != "mL", foodID.hasPrefix("D") else { return .asIs }
        if DrinkReferenceCatalog.entry(forFoodID: foodID) != nil || DrinkReferenceCatalog.recognizes(name) { return .asIs }
        if DrinkReferenceCatalog.plausibleRange(for: servingUnit) != nil { return .asIs }
        return VolumeAsWeight.rule?.matches(name) == true ? .grams : .hidden
    }

    /// 분량 숫자와 단위(예: "800mL", "440g"). unit은 자료 단위(g·mL). 숨기면 nil
    static func amountText(_ amount: Double, unit: String, style: Style, fractionLength: ClosedRange<Int> = 0...1) -> String? {
        let number = amount.formatted(.number.precision(.fractionLength(fractionLength)))
        switch style {
        case .asIs: return "\(number)\(unit)"
        case .grams: return "\(number)g"
        case .hidden: return nil
        }
    }
}
