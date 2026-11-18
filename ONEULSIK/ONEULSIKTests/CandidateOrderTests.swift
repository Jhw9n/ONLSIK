import Foundation
import Testing
@testable import ONEULSIK

/// 같은 이름 후보의 분류 다수결 정렬(`groupedByMajorityCategory`) 규칙 점검. 음식 이름이 아닌 만든 항목으로 본다.
@MainActor
@Suite("후보 분류 정렬")
struct CandidateOrderTests {
    static func item(_ id: String, _ name: String, code: Int?) -> FoodCatalogItem {
        FoodCatalogItem(id: id, name: name, servingUnit: "회", servingGrams: 100,
                        nutrition: NutritionValues(calories: 100, carbohydrateGrams: 0, proteinGrams: 0, fatGrams: 0),
                        category: code == nil ? "음식" : "가공식품", categoryCode: code)
    }

    private func check(id: String, input: String, foods: [FoodCatalogItem], name: String, expected: [String]) {
        let actual = foods.groupedByMajorityCategory(sameNameAs: name).map(\.id)
        let failures = actual == expected ? [] : [Failure(type: .search, message: "순서가 다름: \(actual.joined(separator: ","))")]
        report(suite: "후보 분류 정렬", id: id, input: input, expected: expected.joined(separator: ","),
               actual: actual.joined(separator: ","), failures: failures)
    }

    @Test("다수 분류를 같은 이름 후보 자리 안에서 앞으로")
    func majorityFirst() {
        // 1(분류 1), 2·3·4(분류 9), 다른 이름 x는 자리 유지, 이름은 띄어쓰기를 무시하고 비교
        let foods = [Self.item("1", "가나다", code: 1), Self.item("x", "가나다라", code: 1),
                     Self.item("2", "가나다", code: 9), Self.item("3", "가 나다", code: 9), Self.item("4", "가나다", code: 9)]
        check(id: "O01", input: "같은 이름 4개(분류 1×1, 분류 9×3)와 다른 이름 1개", foods: foods, name: "가나다",
              expected: ["2", "x", "3", "4", "1"])
    }

    @Test("동률이면 그대로")
    func tieKeepsOrder() {
        let foods = [Self.item("1", "가나다", code: 1), Self.item("2", "가나다", code: 9),
                     Self.item("3", "가나다", code: 9), Self.item("4", "가나다", code: 1)]
        check(id: "O02", input: "같은 이름 4개(분류 1×2, 분류 9×2)", foods: foods, name: "가나다", expected: ["1", "2", "3", "4"])
    }

    @Test("같은 이름 후보가 하나뿐이거나 분류 코드가 없으면 그대로")
    func singleOrUncoded() {
        let single = [Self.item("1", "가나다", code: 1), Self.item("2", "가나다라", code: 9), Self.item("3", "가나다마", code: 9)]
        check(id: "O03", input: "같은 이름 1개", foods: single, name: "가나다", expected: ["1", "2", "3"])
        let uncoded = [Self.item("g", "가나다", code: nil), Self.item("1", "가나다", code: 1),
                       Self.item("2", "가나다", code: 9), Self.item("3", "가나다", code: 9)]
        check(id: "O04", input: "분류 코드 없는 같은 이름 항목은 자리 유지", foods: uncoded, name: "가나다",
              expected: ["g", "2", "3", "1"])
    }
}
