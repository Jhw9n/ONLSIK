import Foundation

/// 음식 이름의 표기 변형(Resource/Data/SpellingVariants.json). 표기를 맞추는 모든 곳이 이 표 하나를 읽는다.
nonisolated struct SpellingVariant: Decodable, Sendable {
    let standard: String
    let variants: [String]

    private struct File: Decodable { let entries: [SpellingVariant] }

    static let entries: [SpellingVariant] = {
        guard let url = Bundle.main.url(forResource: "SpellingVariants", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.entries
    }()

    /// 글자 사이 띄어쓰기를 허용하는 정규식 조각. 예: "소세지" → 소\s*세\s*지
    static func spacedPattern(_ text: String) -> String {
        text.filter { !$0.isWhitespace }.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s*")
    }

    /// 변형 표기를 표준 표기로 바꾼다(글자 사이 띄어쓰기 허용).
    static func standardize(_ text: String) -> String {
        entries.reduce(text) { result, entry in
            entry.variants.reduce(result) { current, variant in
                current.replacingOccurrences(of: spacedPattern(variant), with: entry.standard, options: .regularExpression)
            }
        }
    }

    /// 표준 표기의 띄어쓰기 허용 정규식 조각을 모든 표기의 선택지로 넓힌다. 예: 달\s*걀 → (?:달\s*걀|계\s*란)
    static func widen(_ pattern: String) -> String {
        entries.reduce(pattern) { result, entry in
            let standard = spacedPattern(entry.standard)
            guard result.contains(standard) else { return result }
            let options = ([entry.standard] + entry.variants).map(spacedPattern).joined(separator: "|")
            return result.replacingOccurrences(of: standard, with: "(?:\(options))")
        }
    }
}
