import Foundation
import Testing
@testable import ONEULSIK

/// 전시 대비 입력 점검(#35). 합격/불합격을 판정하지 않고 AI 식사 입력 흐름의 결과만 기록한다.
/// Scripts/check_exhibition_inputs.py가 ONEULSIK_EXHIBITION_FILE(입력 목록, Docs/ExhibitionInputs.txt)과
/// ONEULSIK_EXHIBITION_OUTPUT(JSON Lines)을 넘길 때만 실행되며, 평소의 run_tests.sh에서는 건너뛴다.
/// 가짜 해석기는 입력 줄을 그대로 음식 이름으로 돌려주고 분량·영양 추정은 하지 않는다(실기기 모델이 하는 부분).
/// 확인 질문은 첫 선택지를 고르고, 수량 질문("얼마나")과 선택지 없는 질문에서는 멈춘다. "[제외]" 분류(여러 음식 한 줄)는 돌리지 않는다.
@MainActor
@Suite("전시 입력 점검")
struct ExhibitionAuditTests {
    private static let environment = ProcessInfo.processInfo.environment

    private struct Item: Encodable {
        let id: String
        let name: String
        let databaseName: String
        let databaseUnit: String
        let brand: String
        let category: String
        let unit: String
        let count: Double
        let amount: Double
        let amountUnit: String
        let kcal: Double
        let portionBasis: String
        let nutritionBasis: String
        let source: String
    }

    private struct Row: Encodable {
        let category: String
        let input: String
        /// ready(기록 카드까지 감), question(답할 수 없는 질문에서 멈춤), error
        let outcome: String
        let questions: [String]
        let choices: [String]
        let items: [Item]
        let error: String
    }

    @Test(.enabled(if: environment["ONEULSIK_EXHIBITION_FILE"] != nil && environment["ONEULSIK_EXHIBITION_OUTPUT"] != nil))
    func audit() async throws {
        let input = try String(contentsOfFile: Self.environment["ONEULSIK_EXHIBITION_FILE"]!, encoding: .utf8)
        let output = URL(fileURLWithPath: Self.environment["ONEULSIK_EXHIBITION_OUTPUT"]!)
        var category = ""
        var lines: [String] = []
        let encoder = JSONEncoder()
        for raw in input.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                category = String(line.dropFirst(3))
                continue
            }
            guard !line.isEmpty, !line.hasPrefix("#"), !category.hasPrefix("[제외]") else { continue }
            let row = await Self.run(line, category: category)
            lines.append(String(decoding: try encoder.encode(row), as: UTF8.self))
        }
        try (lines.joined(separator: "\n") + "\n").write(to: output, atomically: true, encoding: .utf8)
    }

    private static func run(_ text: String, category: String) async -> Row {
        let script = MealCase.LLM(food: text, brand: nil, portion: nil, pick: nil, estimate: nil)
        let service = AIMealEntryService(interpreter: FakeMealFoodInterpreter(script: script), catalog: FoodCatalogService())
        var questions: [String] = []
        var choices: [String] = []
        do {
            var analysis = try await service.analyze(text)
            for _ in 0..<6 {
                switch analysis {
                case .ready(let items):
                    var recorded: [Item] = []
                    for item in items {
                        let database = try? await FoodCatalogService().food(id: item.food.id)
                        recorded.append(Item(
                            id: item.food.id, name: item.food.name, databaseName: database?.recordedName ?? "",
                            databaseUnit: database?.amountUnit ?? "", brand: item.food.brand,
                            category: database?.category ?? item.food.category,
                            unit: item.food.servingUnit, count: item.count,
                            amount: item.food.baseAmount * item.count, amountUnit: item.food.amountUnit,
                            kcal: item.nutrition.calories, portionBasis: item.portionBasis.rawValue,
                            nutritionBasis: item.nutritionBasis.rawValue, source: item.food.source))
                    }
                    return Row(category: category, input: text, outcome: "ready", questions: questions, choices: choices,
                               items: recorded, error: "")
                case .question(let question):
                    questions.append(question.title)
                    choices.append(question.choices.first.map { choice in
                        let food = choice.selection?.food
                        return "\(choice.title)" + (food.map { " [\($0.id) \($0.recordedName)]" } ?? "")
                    } ?? "-")
                    // 수량 질문은 방문자가 답할 자리라 여기서 멈춘다(가짜 해석기는 분량 추정을 하지 않아 답해도 다시 묻는다).
                    guard !question.title.contains("얼마나"), let first = question.choices.first else {
                        return Row(category: category, input: text, outcome: "question", questions: questions, choices: choices,
                                   items: [], error: "")
                    }
                    analysis = try await service.resolve(first)
                }
            }
            return Row(category: category, input: text, outcome: "question", questions: questions + ["(질문 반복)"],
                       choices: choices, items: [], error: "")
        } catch {
            return Row(category: category, input: text, outcome: "error", questions: questions, choices: choices,
                       items: [], error: "\(error)")
        }
    }
}
