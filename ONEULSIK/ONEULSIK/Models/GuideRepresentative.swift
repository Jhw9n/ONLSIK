import Foundation

/// 대표 자료 지정 표(Resource/Data/GuideRepresentatives.json, 2026-11-19 결정).
/// 대표 분량 출처가 식약처 「외식 영양성분 자료집 제2권」(2013)인 음식에서 자료집의 100g당 열량과 ±2% 안에서 맞는
/// g 기준 DB 자료. 검색이 같은 이름·단위 일반 음식 중 하나를 남길 때 참고표 지정 다음으로 먼저 둔다.
/// 표는 Scripts/build_guide_representatives.py가 만든다.
nonisolated enum GuideRepresentativeCatalog {
    private struct File: Decodable {
        struct Entry: Decodable { let foodID: String }
        let entries: [Entry]
    }

    /// 지정된 식품코드. 파일이 없거나 읽지 못하면 비어 있고, 앱은 기존 순서(priority, 기준일, 식품코드)를 쓴다.
    static let foodIDs: [String] = {
        guard let url = Bundle.main.url(forResource: "GuideRepresentatives", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.entries.map(\.foodID)
    }()

    /// SQLite json_each로 넘기는 JSON 배열 문자열
    static let foodIDsJSON: String = {
        guard let data = try? JSONEncoder().encode(foodIDs), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }()
}
