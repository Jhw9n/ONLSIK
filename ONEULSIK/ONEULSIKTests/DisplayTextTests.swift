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
                        "결정", "내부 기준", "내부 근거", "basisNote", "referenceID"]
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
}
