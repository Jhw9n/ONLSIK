import Foundation

/// 국물·면 요리 판정 표(Resource/Data/VolumeAsWeight.json, 2026-11-17 결정 B).
/// mL 기준으로만 있는 국물·면 일반 조리 음식은 g 기준 자료를 찾기 전까지 대표 분량 N g을 N mL로 본다(1mL=1g).
/// 판정 규칙은 Scripts/compare_volume_weight_pairs.py의 is_soup_or_noodle과 같다.
nonisolated struct VolumeAsWeight: Decodable, Sendable {
    let suffixes: [String]
    let includeNames: [String]
    let excludeNames: [String]
    /// 카드에 붙이는 화면 문구. 기록에는 저장하지 않는다.
    let displayText: String
    let basisNote: String?

    static let rule: VolumeAsWeight? = {
        guard let url = Bundle.main.url(forResource: "VolumeAsWeight", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VolumeAsWeight.self, from: data)
    }()

    /// 국물·면 요리인지. 정규화한 이름이 excludeNames에 있으면 아니고, includeNames에 있으면 맞다.
    /// 그 밖에는 괄호 안을 뺀 이름을 공백·쉼표로 나눈 조각 중 하나가 끝말로 끝나면 맞다.
    func matches(_ name: String) -> Bool {
        let key = FoodReferenceCatalog.normalized(name)
        if excludeNames.contains(where: { FoodReferenceCatalog.normalized($0) == key }) { return false }
        if includeNames.contains(where: { FoodReferenceCatalog.normalized($0) == key }) { return true }
        let plain = name.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        let words = plain.split(whereSeparator: { $0.isWhitespace || $0 == "," })
        return words.contains { word in suffixes.contains { word.hasSuffix($0) } }
    }

    /// 판정에 걸린 끝말(점검·보고용). 맞지 않으면 nil
    func matchedSuffix(_ name: String) -> String? {
        guard matches(name) else { return nil }
        let plain = name.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        let words = plain.split(whereSeparator: { $0.isWhitespace || $0 == "," })
        return suffixes.filter { suffix in words.contains { $0.hasSuffix(suffix) } }.max { $0.count < $1.count } ?? "포함 목록"
    }
}
