import Foundation

/// 식약처 음식 DB 원본의 식품중량(1인분 중량) 표(Resource/Data/DishServings.json, 2026-11-24 결정, #43).
/// 생성: Scripts/build_dish_servings.py. 식품코드 → [중량, 단위(g 또는 mL)]. 단위는 DB 레코드의 기준 단위와 같은 것만 들어 있다.
/// AI 식사 입력의 분량 순서: FoodPortion 표 → FoodReferences estimatedPortions → 이 표 → 모델 분량 추정 → 대체 분량.
nonisolated struct DishServing: Sendable {
    let amount: Double
    let unit: String

    /// 이 표의 값을 대표 분량으로 쓰는 단위(1인분과 1그릇을 같은 양으로 본다).
    /// 개는 넣지 않는다: 개수로 세는 음식은 1인분이 여러 개라 "5개"가 5인분(1,100g)으로 계산됐다(회귀 케이스 M15, #43).
    static let units: Set<String> = ["인분", "그릇"]

    private struct File: Decodable {
        let displayText: String
        let servings: [String: [Value]]

        enum Value: Decodable {
            case number(Double)
            case text(String)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let number = try? container.decode(Double.self) { self = .number(number) } else { self = .text(try container.decode(String.self)) }
            }
        }
    }

    private static let file: (displayText: String, servings: [String: DishServing])? = {
        guard let url = Bundle.main.url(forResource: "DishServings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        var servings: [String: DishServing] = [:]
        for (id, values) in file.servings {
            guard values.count == 2, case .number(let amount) = values[0], case .text(let unit) = values[1],
                  amount.isFinite, amount > 0, ["g", "mL"].contains(unit) else { continue }
            servings[id] = DishServing(amount: amount, unit: unit)
        }
        return (file.displayText, servings)
    }()

    /// 표에 든 식품코드(점검용)
    static var foodIDs: [String] { file.map { Array($0.servings.keys).sorted() } ?? [] }

    /// 카드에 붙이는 화면 문구(예: "식약처 음식 DB 1인분 중량 기준"). 기록에는 저장하지 않는다.
    static var displayText: String? { file?.displayText }

    /// 일반 음식 레코드의 1인분 중량. 가공식품이거나 단위가 레코드 기준 단위와 다르면 nil
    static func serving(for food: FoodCatalogItem) -> DishServing? {
        guard food.category != "가공식품", let serving = file?.servings[food.id], serving.unit == food.amountUnit else { return nil }
        return serving
    }
}
