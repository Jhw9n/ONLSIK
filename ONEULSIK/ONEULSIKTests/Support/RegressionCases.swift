import Foundation
import Testing

/// MealRegressionCases.json의 구조. 기대값은 결과 기준(단위·범위·구분)으로만 적는다.
struct RegressionCases: Decodable {
    let grounding: [GroundingCase]
    let normalization: [NormalizationCase]
    let search: [SearchCase]
    let plausibility: [PlausibilityCase]
    let meals: [MealCase]

    static let shared: RegressionCases = {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "MealRegressionCases", withExtension: "json") else {
            fatalError("MealRegressionCases.json이 테스트 번들에 없습니다")
        }
        do {
            return try JSONDecoder().decode(RegressionCases.self, from: Data(contentsOf: url))
        } catch {
            fatalError("MealRegressionCases.json을 읽지 못했습니다: \(error)")
        }
    }()
}

private final class BundleToken {}

struct ValueRange: Decodable, CustomStringConvertible {
    let min: Double
    let max: Double
    func contains(_ value: Double) -> Bool { value >= min && value <= max }
    var description: String { "\(min.short)~\(max.short)" }
}

struct GroundingCase: Decodable, CustomTestStringConvertible {
    struct Expect: Decodable { let quantity: Double; let unit: String }
    let id: String
    let input: String
    let food: String
    let expect: Expect
    var testDescription: String { "\(id) \(input)" }
}

struct NormalizationCase: Decodable, CustomTestStringConvertible {
    let id: String
    let a: String?
    let b: String?
    let equal: Bool?
    let alias: String?
    let canonical: String?
    var testDescription: String { "\(id) \(a ?? alias ?? "")" }
}

struct SearchCase: Decodable, CustomTestStringConvertible {
    struct Expect: Decodable {
        /// 일반 항목 상위 `within`개 안에 이 글자를 포함한 이름이 있어야 함
        let topGeneralContains: String?
        let within: Int?
        /// 첫 가공식품 후보의 분류 코드(DB `category_code`)
        let firstProductCategoryCode: Int?
    }
    let id: String
    let query: String
    let note: String?
    let expect: Expect
    var testDescription: String { "\(id) \(query)" }
}

struct PlausibilityCase: Decodable, CustomTestStringConvertible {
    let id: String
    let unit: String
    let food: String
    let amount: Double
    let amountUnit: String
    let note: String?
    let expect: Bool
    var testDescription: String { "\(id) \(food) \(amount.short)\(amountUnit)/\(unit)" }
}

struct MealCase: Decodable, CustomTestStringConvertible {
    struct LLM: Decodable {
        struct Portion: Decodable { let amount: Double; let unit: String? }
        struct Estimate: Decodable {
            let referenceFood: String
            let amount: Double
            let amountUnit: String
            let calories: Double
            let carbohydrate: Double
            let protein: Double
            let fat: Double
            let ingredients: String
        }
        let food: String?
        /// 모델이 원문에서 뽑은 브랜드(없으면 "")
        let brand: String?
        let portion: Portion?
        let pick: String?
        let estimate: Estimate?
        /// 모델이 돌려줄 검색어(실기기 기록 재현용, #39). 없으면 빈 목록
        var searchTerms: [String]? = nil
        /// 한 줄에서 모델이 뽑을 음식 이름들(원문에 있는 것만 돌려준다). 없으면 food 하나
        var foods: [String]? = nil
        /// 원문과 상관없이 그대로 돌려줄 음식 이름(#41, 실기기 모델이 지시문 예시 이름을 섞어 돌려준 경우 재현)
        var rawFoods: [String]? = nil
    }
    struct AmountRange: Decodable { let units: [String]; let min: Double; let max: Double }
    struct Expect: Decodable {
        var maxQuestions: Int?
        var drink: Bool?
        var units: [String]?
        var kind: String?
        var nameContains: [String]?
        var nameExcludes: [String]?
        var count: Double?
        var amount: AmountRange?
        var kcal: ValueRange?
        /// 1,000kcal 초과로 "이 양이 맞나요?" 확인 질문이 나와야 함
        var confirmsAmount: Bool?
        /// 분량 근거(MealPortionBasis rawValue). 예: "package" = 제품 총중량 기준
        var basis: String?
        /// 수량 질문("얼마나 드셨나요?")을 거쳐야 함
        var asksAmount: Bool?
        /// 수량을 적지 않아 기본값(대표 분량 1단위)으로 가정했고, 카드에 그 안내가 붙어야 함(false면 붙으면 안 됨)
        var assumedQuantity: Bool?
        /// 기록에 저장되는 출처(nutritionSource)에 들어가야 할 글자(#41)
        var sourceContains: String?
        /// 기록에 쓰인 DB 항목 ID(#41, 같은 이름 제품의 가운데 제품 확인)
        var foodID: String?
        /// 질문 제목이나 고른 선택지에 이 글자가 들어가면 실패(#41, 예: 관련 없는 비슷한 음식 후보)
        var questionsExclude: [String]?
        /// 포장 중량을 모르는 제품에서 AI가 1단위 분량을 추정하고 수량을 고르는 질문을 거쳐야 함(#39, 무게 질문 대신)
        var asksUnitEstimate: Bool?
        /// mL 국물·면 항목에 대표 분량을 같은 숫자의 mL로 계산했다는 안내가 붙어야 함(false면 붙으면 안 됨)
        var volumeAsWeight: Bool?
        /// 여러 음식으로 기록돼야 할 때 순서대로 각 음식 이름(또는 DB 이름)에 들어갈 글자(#39). 없으면 음식 1개여야 함
        var items: [String]?
    }
    let id: String
    let input: String
    let note: String?
    let llm: LLM?
    /// 선택지 없는 질문(자유 입력)에 사용자가 적을 답. 순서대로 사용한다.
    let answers: [String]?
    /// 선택지 질문에서 제목이나 부제에 이 글자가 들어간 선택지를 고른다(없으면 첫 선택지)
    let choose: String?
    let expect: Expect
    var testDescription: String { "\(id) \(input)" }

    /// 보고서용 기대값 요약
    var expectedSummary: String {
        var parts: [String] = []
        if let units = expect.units { parts.append("단위 \(units.joined(separator: "/"))") }
        if let amount = expect.amount { parts.append("\(amount.min.short)~\(amount.max.short)\(amount.units.joined(separator: "/"))") }
        if let kcal = expect.kcal { parts.append("\(kcal)kcal") }
        if let count = expect.count { parts.append("수량 \(count.short)") }
        if let kind = expect.kind { parts.append(kind == "general" ? "일반 음식" : "가공식품") }
        if let names = expect.nameContains { parts.append("이름에 \(names.joined(separator: ","))") }
        if let names = expect.nameExcludes { parts.append("이름에 \(names.joined(separator: ",")) 없음") }
        if let max = expect.maxQuestions { parts.append("질문 \(max)회 이하") }
        if expect.drink == true { parts.append("인분 아님") }
        if expect.confirmsAmount == true { parts.append("양 확인 질문") }
        if expect.basis == "package" { parts.append("제품 총중량 기준") }
        if expect.asksAmount == true { parts.append("수량 질문") }
        if expect.assumedQuantity == true { parts.append("기본값 안내") }
        if expect.asksUnitEstimate == true { parts.append("AI 1단위 추정 수량 질문") }
        if let source = expect.sourceContains { parts.append("출처에 ‘\(source)’") }
        if let id = expect.foodID { parts.append("자료 \(id)") }
        if let excluded = expect.questionsExclude { parts.append("질문에 없음(\(excluded.joined(separator: ", ")))") }
        if expect.volumeAsWeight == true { parts.append("국물 mL 안내") }
        if expect.volumeAsWeight == false { parts.append("국물 mL 안내 없음") }
        if let items = expect.items { parts.append("음식 \(items.count)개(\(items.joined(separator: ", ")))") }
        return parts.joined(separator: ", ")
    }
}

extension Double {
    var short: String { formatted(.number.precision(.fractionLength(0...1)).grouping(.never)) }
}
