import Foundation

/// 전시용 "검색 개선 기록"(#51). 식사 입력에서 음식 DB를 제대로 못 찾았거나 사용자가 제안을 바꾼 경우를 기기 안 파일에만 남긴다.
/// 외부로 보내지 않는다. Debug·Release 모두 기록한다. 식사 기록(MealRecord) 저장과 검색 결과에는 관여하지 않는다
/// (MealEntryViewModel이 화면에서 일어난 일을 보고 덧붙이기만 한다). 설정 > 검색 개선 기록에서 보고·복사·지운다.
/// 기존 DEBUG 기록(MealDebugLog)은 DEBUG 빌드 콘솔 전용이라 저장·Release 기록이 안 돼 따로 둔다.
nonisolated struct SearchImprovementEntry: Codable, Equatable, Identifiable, Sendable {
    /// 남긴 이유(여러 개일 수 있다)
    enum Reason: String, Codable, CaseIterable, Sendable {
        /// a. 영양정보를 찾지 못함(오류 또는 AI 영양 추정으로 기록)
        case notFound = "a"
        /// b. "비슷한 음식 기준으로 기록할까요?"를 보여 줌
        case similarQuestion = "b"
        /// c. 입력한 음식 이름과 자동으로 고른 항목 이름이 정규화 뒤에도 다름
        case nameMismatch = "c"
        /// d. 사용자가 제안을 거절하거나 다른 항목을 직접 고름
        case userChangedChoice = "d"
        /// e. 열량 확인 문구("열량이 높게 계산됐어요")가 뜸
        case calorieCheck = "e"

        var label: String {
            switch self {
            case .notFound: "a 영양정보 못 찾음"
            case .similarQuestion: "b 비슷한 음식 질문"
            case .nameMismatch: "c 이름 다름"
            case .userChangedChoice: "d 제안 거절·다른 항목"
            case .calorieCheck: "e 열량 확인"
            }
        }
    }

    /// 사용자의 최종 행동
    enum Action: String, Codable, Sendable {
        case accepted = "수락"
        case rejected = "거절"
        case otherItem = "다른 항목"
        case typedDetails = "직접 입력"
        case automatic = "자동 기록"
        case failed = "기록 못 함"
        case noResponse = "응답 없음"
    }

    var id = UUID()
    var date: Date
    /// 입력 문장(그 줄 원문)
    var inputText: String
    /// 뽑힌 음식 이름
    var foodName: String
    var reasons: [Reason]
    /// 제안된(자동으로 고른) 항목 이름과 kcal
    var suggestedName: String?
    var suggestedKcal: Double?
    /// 사용자가 고른 항목 이름과 kcal
    var selectedName: String?
    var selectedKcal: Double?
    var action: Action

    /// 목록·복사에 쓰는 한 줄 설명
    var summary: String {
        let time = date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        var parts = ["\(time)", "입력 ‘\(inputText)’", "음식 ‘\(foodName)’", "경우 \(reasons.map(\.rawValue).joined(separator: ","))"]
        if let suggestedName { parts.append("제안 \(suggestedName)\(Self.kcalText(suggestedKcal))") }
        if let selectedName { parts.append("선택 \(selectedName)\(Self.kcalText(selectedKcal))") }
        parts.append("행동 \(action.rawValue)")
        return parts.joined(separator: " · ")
    }

    private static func kcalText(_ kcal: Double?) -> String {
        kcal.map { " \(Int($0.rounded()))kcal" } ?? ""
    }
}

/// 기록 파일(Application Support/SearchImprovementLog.json). 가장 최근 500건까지 남긴다.
@MainActor
final class SearchImprovementLog {
    static let shared = SearchImprovementLog(fileURL: SearchImprovementLog.defaultURL)
    static let maxEntries = 500

    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    private static var defaultURL: URL? {
        guard let folder = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true) else { return nil }
        return folder.appendingPathComponent("SearchImprovementLog.json")
    }

    /// 오래된 것부터
    func entries() -> [SearchImprovementEntry] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder.searchLog.decode([SearchImprovementEntry].self, from: data) else { return [] }
        return entries
    }

    func append(_ entry: SearchImprovementEntry) {
        guard let fileURL else { return }
        var all = entries()
        all.append(entry)
        if all.count > Self.maxEntries { all.removeFirst(all.count - Self.maxEntries) }
        guard let data = try? JSONEncoder.searchLog.encode(all) else { return }
        try? data.write(to: fileURL, options: .atomic)
        MealDebugLog.log("검색 개선 기록: \(entry.summary)")
    }

    /// 이 기록만 지운다(식사 기록과 무관).
    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 전체 복사용 텍스트(최근 것부터)
    func exportText() -> String {
        let entries = entries()
        guard !entries.isEmpty else { return "검색 개선 기록 없음" }
        let legend = SearchImprovementEntry.Reason.allCases.map(\.label).joined(separator: ", ")
        return (["오늘식 검색 개선 기록 \(entries.count)건 (경우: \(legend))"] + entries.reversed().map(\.summary))
            .joined(separator: "\n")
    }
}

private extension JSONEncoder {
    static var searchLog: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var searchLog: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
