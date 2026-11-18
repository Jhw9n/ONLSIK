import Foundation

/// 음식 이름 앞의 상태·조리 수식어(냉동, 생, 숯불 등). 목록은 FoodModifiers.json에서만 관리한다.
nonisolated struct FoodModifier: Decodable, Sendable {
    let word: String
    /// 수식어를 뗀 뒤 후보 중 먼저 볼 분류(예: 생 → 원재료성 식품, 숯불 → 음식). 없으면 순서를 바꾸지 않는다.
    let prefersCategory: String?
    /// 먼저 볼 조리 음식 이름 끝말(예: 숯불 → "구이"면 "장어구이 …"). 조리 음식(음식 분류)에만 적용
    let preferNameSuffixes: [String]?
    /// 먼저 볼 원재료 상태(예: "구운것", "생것"). 원재료 이름 "재료, 상태" 형식에 적용
    let rawStates: [String]?
    /// 뒤로 미룰 조리 음식 끝말(예: 국·탕·조림). 뗀 이름 자체가 그 끝말로 끝나면 적용하지 않는다.
    let avoidNameSuffixes: [String]?
    /// 비슷한 음식 확인 질문에 보여줄 화면 문구. 날짜·결정·출처 메모는 넣지 않는다.
    let displayText: String
    /// 원재료 항목으로 연결될 때 보여줄 화면 문구(선택). 없으면 displayText
    let rawDisplayText: String?
    /// 내부 근거(선택). 화면에 보여주지 않는다.
    let basisNote: String?
}

nonisolated enum FoodModifierCatalog {
    struct Stripped {
        let base: String
        let modifiers: [FoodModifier]

        var prefersCategory: String? { modifiers.compactMap(\.prefersCategory).last }
        var displayText: String { modifiers.map(\.displayText).joined(separator: ". ") }

        /// 연결된 항목에 맞는 화면 문구. 원재료 항목이면 양념·기름 미반영 안내를 쓴다.
        func displayText(for food: FoodCatalogItem) -> String {
            guard food.category == FoodModifierCatalog.rawCategory else { return displayText }
            return modifiers.map { $0.rawDisplayText ?? $0.displayText }.joined(separator: ". ")
        }

        /// 수식어를 떼고 다시 찾은 "비슷한 음식" 후보의 순서(작을수록 먼저).
        /// 0 뗀 이름과 같음 · 1~ 우선 끝말 조리 음식 · 10~ 원재료 상태 · 20 선호 분류 · 21 그 밖 · 30 피할 끝말
        func rank(_ food: FoodCatalogItem) -> Int {
            let normalize = FoodReferenceCatalog.normalized
            let name = normalize(food.name)
            if name == base { return 0 }
            let preferred = modifiers.flatMap { $0.preferNameSuffixes ?? [] }
            if food.category == "음식",
               let index = preferred.firstIndex(where: { name.hasPrefix(base + normalize($0)) }) {
                return 1 + index
            }
            if food.category == FoodModifierCatalog.rawCategory {
                let segments = food.name.split(separator: ",").map { normalize(String($0)) }
                let states = modifiers.flatMap { $0.rawStates ?? [] }
                if segments.first == base,
                   let index = states.firstIndex(where: { state in segments.dropFirst().contains { $0.hasPrefix(normalize(state)) } }) {
                    return 10 + index
                }
            }
            let avoided = modifiers.flatMap { $0.avoidNameSuffixes ?? [] }.map(normalize)
            let firstWord = normalize(String(food.name.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "(" }).first ?? ""))
            if !avoided.contains(where: base.hasSuffix), avoided.contains(where: firstWord.hasSuffix) {
                return 30
            }
            if let prefersCategory, food.category == prefersCategory { return 20 }
            return 21
        }
    }

    static let rawCategory = "원재료성 식품"

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
