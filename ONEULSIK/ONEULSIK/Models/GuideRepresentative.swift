import Foundation

/// 대표 자료 지정 표(Resource/Data/GuideRepresentatives.json, 2026-11-19 결정).
/// 대표 분량 출처가 식약처 「외식 영양성분 자료집 제2권」(2013)인 음식에서 자료집의 100g당 열량과 ±2% 안에서 맞는
/// g 기준 DB 자료. 검색이 같은 이름·단위 일반 음식 중 하나를 남길 때 참고표 지정 다음으로 먼저 둔다.
/// 표는 Scripts/build_guide_representatives.py가 만든다.
nonisolated enum GuideRepresentativeCatalog {
    struct Entry: Decodable, Sendable {
        /// 지정 자료의 DB 이름
        let name: String
        let foodID: String
        let guidePage: Int
    }

    private struct File: Decodable {
        let entries: [Entry]
    }

    static let entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "GuideRepresentatives", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.entries
    }()

    /// 지정된 식품코드. 파일이 없거나 읽지 못하면 비어 있고, 앱은 기존 순서(priority, 기준일, 식품코드)를 쓴다.
    static var foodIDs: [String] { entries.map(\.foodID) }

    /// SQLite json_each로 넘기는 JSON 배열 문자열
    static let foodIDsJSON: String = {
        guard let data = try? JSONEncoder().encode(entries.map(\.foodID)), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }()

    private static let byPage: [Int: Entry] = Dictionary(entries.map { ($0.guidePage, $0) }, uniquingKeysWith: { first, _ in first })

    /// 대표 분량표의 같은 행 이름을 같은 음식의 별칭으로 본다(2026-11-19 결정).
    /// 이름이 대표 분량표의 자료집 출처 행에 있고 그 쪽 번호에 지정 자료가 있으면 그 자료. 참고표 이름 여부는 호출하는 쪽이 본다.
    static func entry(forName name: String) -> Entry? {
        FoodPortion.guidePage(forName: name).flatMap { byPage[$0] }
    }
}
