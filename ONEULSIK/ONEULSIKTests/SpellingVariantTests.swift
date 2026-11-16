import Foundation
import Testing
@testable import ONEULSIK

/// 표기 변형 동등성: SpellingVariants.json의 각 쌍(예: 달걀/계란)을 두 표기로 검색해 첫 후보가 같은지 본다.
/// 검색 조건과 순위 기준이 같은 정규화를 쓰는지 확인한다.
@MainActor
@Suite("표기 변형")
struct SpellingVariantTests {
    struct Pair: CustomTestStringConvertible {
        let standard: String
        let variant: String
        var testDescription: String { "\(standard)/\(variant)" }
    }

    static let pairs: [Pair] = SpellingVariant.entries.flatMap { entry in
        entry.variants.map { Pair(standard: entry.standard, variant: $0) }
    }

    @Test("표 읽기")
    func tableLoaded() {
        let failures = Self.pairs.isEmpty ? [Failure(type: .normalization, message: "SpellingVariants.json을 읽지 못함")] : []
        report(suite: "표기 변형", id: "V00", input: "SpellingVariants.json", expected: "쌍 1개 이상",
               actual: "쌍 \(Self.pairs.count)개", failures: failures)
    }

    @Test("두 표기의 첫 검색 후보", arguments: pairs)
    func firstCandidate(_ pair: Pair) async throws {
        let catalog = FoodCatalogService()
        let standard = try await catalog.search(query: pair.standard).first
        let variant = try await catalog.search(query: pair.variant).first
        var failures: [Failure] = []
        if standard == nil { failures.append(Failure(type: .search, message: "‘\(pair.standard)’ 검색 결과 없음")) }
        if standard?.id != variant?.id {
            failures.append(Failure(type: .search,
                message: "첫 후보가 다름: ‘\(pair.standard)’ → \(standard?.name ?? "없음"), ‘\(pair.variant)’ → \(variant?.name ?? "없음")"))
        }
        let index = (Self.pairs.firstIndex { $0.standard == pair.standard && $0.variant == pair.variant } ?? 0) + 1
        report(suite: "표기 변형", id: String(format: "V%02d", index), input: "\(pair.standard) / \(pair.variant)",
               expected: "두 표기의 첫 검색 후보가 같음", actual: "\(standard?.name ?? "없음") / \(variant?.name ?? "없음")",
               failures: failures)
    }
}
