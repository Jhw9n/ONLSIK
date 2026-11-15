import Foundation

/// 음식 이름 앞의 상태·조리 수식어(냉동, 생, 숯불 등). 목록은 FoodModifiers.json에서만 관리한다.
nonisolated struct FoodModifier: Decodable, Sendable {
    let word: String
    /// 수식어를 뗀 뒤 후보 중 먼저 볼 분류(예: 생 → 원재료성 식품, 숯불 → 음식). 없으면 순서를 바꾸지 않는다.
    let prefersCategory: String?
    /// 비슷한 음식 확인 질문에 보여줄 화면 문구. 날짜·결정·출처 메모는 넣지 않는다.
    let displayText: String
    /// 내부 근거(선택). 화면에 보여주지 않는다.
    let basisNote: String?
}

nonisolated enum FoodModifierCatalog {
    struct Stripped {
        let base: String
        let modifiers: [FoodModifier]

        var prefersCategory: String? { modifiers.compactMap(\.prefersCategory).last }
        var displayText: String { modifiers.map(\.displayText).joined(separator: ". ") }
    }

    private struct File: Decodable {
        let modifiers: [FoodModifier]
        let keepWords: [String]
    }

    private static let file: File? = {
        guard let url = Bundle.main.url(forResource: "FoodModifiers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.modifiers.allSatisfy({ !$0.word.isEmpty && !$0.displayText.isEmpty }) else { return nil }
        return file
    }()

    static var entries: [FoodModifier] { file?.modifiers ?? [] }

    /// 앞쪽 수식어를 모두 뗀 이름. 뗄 수식어가 없거나 남는 이름이 두 글자 미만이면 nil.
    /// `생강`처럼 수식어로 시작하는 음식 이름(keepWords)은 떼지 않는다.
    static func stripped(_ name: String) -> Stripped? {
        guard let file else { return nil }
        let normalize = FoodReferenceCatalog.normalized
        let keepWords = file.keepWords.map(normalize)
        let modifiers = file.modifiers.sorted { $0.word.count > $1.word.count }
        var remainder = normalize(name)
        var removed: [FoodModifier] = []
        while !keepWords.contains(where: remainder.hasPrefix),
              let modifier = modifiers.first(where: { remainder.hasPrefix(normalize($0.word)) }),
              remainder.count - modifier.word.count >= 2 {
            remainder.removeFirst(modifier.word.count)
            removed.append(modifier)
        }
        return removed.isEmpty ? nil : Stripped(base: remainder, modifiers: removed)
    }
}
