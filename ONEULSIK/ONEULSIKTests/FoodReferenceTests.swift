import Foundation
import Testing
@testable import ONEULSIK

/// 참고표 항목이 업체 제품을 가리키는 규칙(allowsBrandedProduct, #43).
/// 같은 업체 제품 레코드를 가리키는 항목이라도 필드가 없거나 false면 지금처럼 매칭되지 않아야 한다.
@MainActor
@Suite("참고표 업체 제품")
struct FoodReferenceTests {
    static func reference(allowsBranded: Bool?) throws -> FoodReference {
        var object: [String: Any] = [
            "name": "마라탕", "aliases": [], "referenceID": "P123-207020400-0006", "referenceName": "마라탕",
            "amountUnit": "g", "source": "식품의약품안전처", "sourceDate": "2026-09-29", "category": "가공식품",
            "estimatedPortions": ["인분": 512]
        ]
        if let allowsBranded { object["allowsBrandedProduct"] = allowsBranded }
        return try JSONDecoder().decode(FoodReference.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test("allowsBrandedProduct가 없으면 업체 제품에 매칭되지 않음")
    func brandedProductNeedsFlag() async throws {
        var failures: [Failure] = []
        guard let product = try await FoodCatalogService().food(id: "P123-207020400-0006") else {
            report(suite: "참고표 업체 제품", id: "F01", input: "P123-207020400-0006", expected: "DB에 제품 있음", actual: "없음",
                   failures: [Failure(type: .name, message: "DB에 제품 레코드 없음")])
            return
        }
        let results = try [nil, false, true].map { flag in (flag, try Self.reference(allowsBranded: flag)) }
            .map { flag, reference in (flag, reference.matches(product), reference.estimatedAmount(for: "인분", food: product)) }
        for (flag, matches, amount) in results where (flag == true) != matches {
            failures.append(Failure(type: .name, message: "allowsBrandedProduct \(flag.map(String.init) ?? "없음"): 매칭 \(matches), 인분 \(amount.map { "\($0)" } ?? "-")"))
        }
        report(suite: "참고표 업체 제품", id: "F01", input: "마라탕 → \(product.recordedName)",
               expected: "필드 없음·false는 매칭 안 됨, true만 매칭(인분 512)",
               actual: results.map { "\($0.0.map(String.init) ?? "없음"): \($0.1 ? "매칭 \($0.2.map { "\(Int($0))" } ?? "-")" : "안 됨")" }.joined(separator: ", "),
               failures: failures)
    }
}
