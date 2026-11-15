import Foundation
import Testing
@testable import ONEULSIK

/// 사용자에게 보이는 문구에 내부 근거(결정 날짜, "결정", 내부 용어)가 섞이지 않았는지 검사한다.
/// 데이터 파일은 화면 문구를 `displayText`, 내부 근거를 `basisNote`처럼 별도 필드에 둔다.
@MainActor
@Suite("화면 문구")
struct DisplayTextTests {
    static let dataFiles = ["FoodReferences", "FoodModifiers", "DrinkReferences", "PackagedFoodReferences"]
    /// 화면에 보이는 필드 이름. 데이터 파일에 새 화면용 필드를 추가하면 여기에 넣는다.
    static let displayKeys: Set<String> = ["displayText", "rawDisplayText"]

    static func forbiddenParts(in text: String) -> [String] {
        let patterns = [#"\d{4}-\d{1,2}-\d{1,2}"#, #"\d{4}\.\s?\d{1,2}\.\s?\d{1,2}"#, #"\d{4}년\s?\d{1,2}월"#,
                        "결정", "내부 기준", "내부 근거", "대표값:", "온디바이스", "basisNote", "referenceID"]
        return patterns.compactMap { pattern in
            text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
        }
    }

    private static func displayValues(in value: Any, path: String) -> [(path: String, text: String)] {
        if let object = value as? [String: Any] {
            return object.sorted { $0.key < $1.key }.flatMap { key, child -> [(path: String, text: String)] in
                if displayKeys.contains(key), let text = child as? String { return [("\(path).\(key)", text)] }
                return displayValues(in: child, path: "\(path).\(key)")
            }
        }
        if let array = value as? [Any] {
            return array.enumerated().flatMap { displayValues(in: $1, path: "\(path)[\($0)]") }
        }
        return []
    }

    @Test("데이터 파일의 화면용 필드")
    func dataFileDisplayFields() throws {
        var failures: [Failure] = []
        var checked = 0
        for name in Self.dataFiles {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                failures.append(Failure(type: .displayText, message: "\(name).json 없음"))
                continue
            }
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            for (path, text) in Self.displayValues(in: json, path: name) {
                checked += 1
                let found = Self.forbiddenParts(in: text)
                if !found.isEmpty {
                    failures.append(Failure(type: .displayText, message: "\(path): ‘\(found.joined(separator: "’, ‘"))’ 포함"))
                }
            }
        }
        if checked == 0 {
            failures.append(Failure(type: .displayText, message: "검사한 화면용 필드가 없음"))
        }
        report(suite: "화면 문구", id: "T01", input: Self.dataFiles.map { "\($0).json" }.joined(separator: ", "),
               expected: "displayText에 날짜·결정·내부 용어 없음", actual: "화면용 필드 \(checked)개 검사", failures: failures)
    }

    @Test("앱이 읽은 화면 문구")
    func decodedDisplayText() {
        let texts = FoodReferenceCatalog.entries.compactMap(\.displayText) + FoodModifierCatalog.entries.map(\.displayText)
            + FoodModifierCatalog.entries.compactMap(\.rawDisplayText)
        let failures = texts.flatMap { text in
            Self.forbiddenParts(in: text).map { Failure(type: .displayText, message: "‘\(text)’에 ‘\($0)’") }
        }
        let missing = texts.isEmpty ? [Failure(type: .displayText, message: "읽은 화면 문구가 없음")] : []
        report(suite: "화면 문구", id: "T02", input: "FoodReferenceCatalog, FoodModifierCatalog",
               expected: "날짜·결정·내부 용어 없음", actual: "문구 \(texts.count)개", failures: failures + missing)
    }

    /// 실제 확인 질문 화면에 나오는 제목·안내·선택지 문구
    @Test("확인 질문 문구", arguments: [
        ("T03", "냉동삼겹살 1인분", "냉동삼겹살"), ("T04", "숯불쭈꾸미 1인분", "숯불쭈꾸미"),
        ("T05", "냉동만두 5개", "냉동만두"), ("T06", "생삼겹살 1인분", "생삼겹살"),
    ])
    func questionText(_ id: String, _ input: String, _ food: String) async throws {
        let script = MealCase.LLM(food: food, brand: nil, portion: .init(amount: 200, unit: nil), pick: nil, estimate: nil)
        let service = AIMealEntryService(interpreter: FakeMealFoodInterpreter(script: script), catalog: FoodCatalogService())
        var failures: [Failure] = []
        var shown: [String] = []
        var analysis = try await service.analyze(input)
        for _ in 0..<4 {
            guard case .question(let question) = analysis else { break }
            let texts = [question.title, question.explanation, question.inputPlaceholder]
                + question.choices.flatMap { [$0.title, $0.subtitle ?? ""] }
            shown.append(question.explanation)
            for text in texts {
                for part in Self.forbiddenParts(in: text) {
                    failures.append(Failure(type: .displayText, message: "‘\(text)’에 ‘\(part)’"))
                }
            }
            guard let first = question.choices.first else { break }
            analysis = try await service.resolve(first)
        }
        report(suite: "화면 문구", id: id, input: input, expected: "질문 문구에 날짜·결정·내부 용어 없음",
               actual: shown.joined(separator: " / "), failures: failures)
    }

    /// 수량 없이 입력해 1단위로 가정했을 때 카드에 붙는 안내(MealEntryItem.quantityNote)
    @Test("기본값 안내 문구")
    func assumedQuantityNote() {
        let expected = ["인분": "1인분으로", "공기": "1공기로", "줄": "1줄로", "개": "1개로", "병": "1병으로", "그릇": "1그릇으로"]
        var failures: [Failure] = []
        var shown: [String] = []
        for (unit, phrase) in expected.sorted(by: { $0.key < $1.key }) {
            let note = MealEntryItem.assumedQuantityNote(unit: unit)
            shown.append(note)
            if !note.contains(phrase) {
                failures.append(Failure(type: .displayText, message: "‘\(note)’ (기대 ‘\(phrase)’)"))
            }
            for part in Self.forbiddenParts(in: note) {
                failures.append(Failure(type: .displayText, message: "‘\(note)’에 ‘\(part)’"))
            }
        }
        report(suite: "화면 문구", id: "T07", input: expected.keys.sorted().joined(separator: ", "),
               expected: "수량이 없어서 1(단위)로/으로 가정했어요, 내부 용어 없음", actual: shown.first ?? "-", failures: failures)
    }
}

/// 인분으로 입력했는데 대표 분량 단위가 다를 때(예: 주꾸미볶음 1접시) 카드에 입력 단위를 그대로 보여주는지
@MainActor
@Suite("입력 단위 표시")
struct InputUnitDisplayTests {
    @Test("인분 입력과 대표 분량 단위", arguments: [
        ("U01", "쭈꾸미볶음 1인분", "쭈꾸미볶음", "인분", 200.0, "대표 분량 1접시 기준"),
        ("U02", "쭈꾸미볶음 1접시", "쭈꾸미볶음", "접시", 200.0, ""),
        ("U03", "삼겹살구이 1인분", "삼겹살구이", "인분", 130.0, ""),
    ])
    func unit(_ id: String, _ input: String, _ food: String, _ unit: String, _ grams: Double, _ note: String) async throws {
        let script = MealCase.LLM(food: food, brand: nil, portion: .init(amount: 300, unit: nil), pick: nil, estimate: nil)
        let service = AIMealEntryService(interpreter: FakeMealFoodInterpreter(script: script), catalog: FoodCatalogService())
        var analysis = try await service.analyze(input)
        for _ in 0..<3 {
            guard case .question(let question) = analysis, let first = question.choices.first else { break }
            analysis = try await service.resolve(first)
        }
        var failures: [Failure] = []
        var actual = "기록 없음"
        if case .ready(let items) = analysis, let item = items.first {
            let description = item.basisDescription ?? ""
            actual = "\(item.amountDescription) · \(description)"
            if item.food.servingUnit != unit {
                failures.append(Failure(type: .unit, message: "카드 단위 \(item.food.servingUnit) (기대 \(unit))"))
            }
            if abs(item.food.baseAmount * item.count - grams) > 0.5 {
                failures.append(Failure(type: .amount, message: "\((item.food.baseAmount * item.count).short)g (기대 \(grams.short)g)"))
            }
            if note.isEmpty ? description.contains("대표 분량") : !description.contains(note) {
                failures.append(Failure(type: .displayText, message: "분량 안내 ‘\(description)’ (기대 ‘\(note.isEmpty ? "대표 분량 안내 없음" : note)’)"))
            }
        } else {
            failures.append(Failure(type: .error, message: "기록되지 않음"))
        }
        report(suite: "입력 단위 표시", id: id, input: input,
               expected: "1\(unit) · 약 \(grams.short)g\(note.isEmpty ? "" : " · \(note)")", actual: actual, failures: failures)
    }
}

/// MealRecord.nutritionSource로 저장되는 출처 문자열(MealRecordStore가 item.food.source를 그대로 저장)에
/// 날짜·"결정"·"대표값:" 같은 내부 용어가 없는지 검사한다.
@MainActor
@Suite("저장 출처")
struct StoredSourceTests {
    private static func items(for testCase: MealCase) async -> [MealEntryItem] {
        let service = AIMealEntryService(interpreter: FakeMealFoodInterpreter(script: testCase.llm), catalog: FoodCatalogService())
        var answers = testCase.answers ?? []
        guard var analysis = try? await service.analyze(testCase.input) else { return [] }
        for _ in 0..<4 {
            switch analysis {
            case .ready(let items):
                return items
            case .question(let question):
                if let first = question.choices.first {
                    guard let next = try? await service.resolve(first) else { return [] }
                    analysis = next
                } else if var typed = question.clarification, typed.continuationInput != nil, !answers.isEmpty {
                    typed.continuationInput?.details = answers.removeFirst()
                    guard let next = try? await service.resolve(typed) else { return [] }
                    analysis = next
                } else {
                    return []
                }
            }
        }
        return []
    }

    @Test("식사 케이스와 참고값 항목의 저장 출처")
    func storedSources() async {
        var sources: [(String, String)] = []
        for testCase in RegressionCases.shared.meals {
            for item in await Self.items(for: testCase) {
                sources.append(("\(testCase.id) \(testCase.input)", item.food.source))
            }
        }
        sources += PreparedFoodReference.entries.map { ("참고값 \($0.food.name)", $0.food.source) }
        sources += PackagedFoodCatalog.entries.map { ("포장제품 \($0.name)", $0.food.source) }
        var failures: [Failure] = []
        for (label, source) in sources {
            if source.trimmingCharacters(in: .whitespaces).isEmpty {
                failures.append(Failure(type: .displayText, message: "\(label): 출처가 비어 있음"))
            }
            for part in DisplayTextTests.forbiddenParts(in: source) {
                failures.append(Failure(type: .displayText, message: "\(label): ‘\(source)’에 ‘\(part)’"))
            }
        }
        let drinks = sources.filter { ["M01", "M05", "M06"].contains(String($0.0.prefix(3))) }.map(\.1)
        report(suite: "저장 출처", id: "R01", input: "식사 케이스 \(RegressionCases.shared.meals.count)개 + 참고값·포장제품",
               expected: "저장 출처에 날짜·결정·대표값:·내부 용어 없음",
               actual: "출처 \(sources.count)개 검사. 예: \(drinks.first ?? "-")", failures: failures)
    }
}
