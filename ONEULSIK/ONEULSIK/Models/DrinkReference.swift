import Foundation

/// 술·음료의 용기 단위(병·캔·잔)와 대표 DB 항목. 값은 DrinkReferences.json에서만 관리한다.
nonisolated struct DrinkReference: Decodable, Sendable {
    struct Container: Decodable, Sendable {
        let unit: String
        let milliliters: Double
        let source: String
    }

    let name: String
    let aliases: [String]
    let matchesSuffix: Bool
    let productNames: [String]
    let referenceID: String
    let referenceName: String
    /// 검색에서 맨 앞에 보일 브랜드 없는 일반 항목(선택)
    let generalReferenceID: String?
    let defaultUnit: String
    let containers: [Container]

    var isValid: Bool {
        !name.isEmpty && !referenceID.isEmpty && !containers.isEmpty
            && containers.contains { $0.unit == defaultUnit }
            && containers.allSatisfy { $0.milliliters.isFinite && (1...5000).contains($0.milliliters) && !$0.source.isEmpty }
    }

    func container(for unit: String) -> Container? {
        containers.first { $0.unit == unit }
    }

    /// 입력 이름이 이 술의 제품명 자체인지(대표값이 아니라 그 제품을 먹은 것인지)
    func isProduct(_ name: String) -> Bool {
        let key = DrinkReferenceCatalog.key(name)
        return productNames.contains { FoodReferenceCatalog.normalized($0) == key }
    }

    func matches(_ food: FoodCatalogItem) -> Bool {
        food.id == referenceID && food.name == referenceName && food.amountUnit == "mL" && food.baseAmount > 0
    }
}

nonisolated enum DrinkReferenceCatalog {
    private struct File: Decodable {
        let plausibleMilliliters: [String: [Double]]
        let drinks: [DrinkReference]
    }

    private static let file: File? = {
        guard let url = Bundle.main.url(forResource: "DrinkReferences", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.drinks.allSatisfy(\.isValid),
              file.plausibleMilliliters.values.allSatisfy({ $0.count == 2 && $0[0] <= $0[1] }) else { return nil }
        return file
    }()

    static var entries: [DrinkReference] { file?.drinks ?? [] }

    /// 용기 단위별 한 단위 부피의 허용 범위(mL)
    static func plausibleRange(for unit: String) -> ClosedRange<Double>? {
        guard let bounds = file?.plausibleMilliliters[unit] else { return nil }
        return bounds[0]...bounds[1]
    }

    /// 도수 표기(17도, 16.9%, 알코올17.8)를 뗀 정규화 이름
    static func key(_ name: String) -> String {
        FoodReferenceCatalog.normalized(name)
            .replacingOccurrences(of: #"(?:알코올)?\d+(?:\.\d+)?(?:도|%)?$"#, with: "", options: .regularExpression)
    }

    static func entry(for name: String) -> DrinkReference? {
        let key = key(name)
        guard !key.isEmpty else { return nil }
        if let product = entries.first(where: { $0.isProduct(name) }) { return product }
        return entries.first { entry in
            let names = ([entry.name] + entry.aliases).map(FoodReferenceCatalog.normalized)
            return names.contains(key) || entry.matchesSuffix && names.contains(where: key.hasSuffix)
        }
    }

    static func entry(forFoodID id: String) -> DrinkReference? {
        entries.first { $0.referenceID == id }
    }

    static func recognizes(_ name: String) -> Bool {
        entry(for: name) != nil
    }
}
