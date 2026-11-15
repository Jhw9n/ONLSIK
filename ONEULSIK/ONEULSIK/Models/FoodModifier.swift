import Foundation

/// 음식 이름 앞의 상태·조리 수식어(냉동, 생, 숯불 등). 목록은 FoodModifiers.json에서만 관리한다.
nonisolated struct FoodModifier: Decodable, Sendable {
    let word: String
    /// 수식어를 뗀 뒤 후보 중 먼저 볼 분류(예: 생 → 원재료성 식품, 숯불 → 음식). 없으면 순서를 바꾸지 않는다.
    let prefersCategory: String?
    let explanation: String
}

nonisolated enum FoodModifierCatalog {
    struct Stripped {
        let base: String
        let modifiers: [FoodModifier]

        var prefersCategory: String? { modifiers.compactMap(\.prefersCategory).last }
        var explanation: String { modifiers.map(\.explanation).joined(separator: ". ") }
    }

    private struct File: Decodable {
        let modifiers: [FoodModifier]
        let keepWords: [String]
    }

    private static let file: File? = {
        guard let url = Bundle.main.url(forResource: "FoodModifiers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.modifiers.allSatisfy({ !$0.word.isEmpty && !$0.explanation.isEmpty }) else { return nil }
        return file
    }()

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
