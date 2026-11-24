import Foundation
import Testing
@testable import ONEULSIK

// 입력 방식(한 줄 자연어 / 자동완성 + 단위 선택)과 무관하게 남는 공통 기반을 먼저 검사한다.
// 케이스는 모두 MealRegressionCases.json에 있다.

@MainActor
@Suite("분량·단위 파싱")
struct GroundingTests {
    @Test(arguments: RegressionCases.shared.grounding)
    func grounding(_ testCase: GroundingCase) {
        let seed = MealFoodInput(name: testCase.food, sourceText: testCase.input, quantity: 1, unit: "인분", brand: "")
        var failures: [Failure] = []
        var actual = "파싱 실패"
        do {
            let grounded = try MealInputGrounding.ground([seed], in: testCase.input)
            if let first = grounded.first {
                actual = "\(first.quantity.short) \(first.unit)"
                if first.unit != testCase.expect.unit {
                    failures.append(Failure(type: .parsing, message: "단위 \(first.unit) (기대 \(testCase.expect.unit))"))
                }
                if abs(first.quantity - testCase.expect.quantity) > 0.001 {
                    failures.append(Failure(type: .parsing, message: "수량 \(first.quantity.short) (기대 \(testCase.expect.quantity.short))"))
                }
            }
        } catch {
            failures.append(Failure(type: .parsing, message: "파싱 오류: \(error)"))
        }
        report(suite: "파싱", id: testCase.id, input: testCase.input,
               expected: "\(testCase.expect.quantity.short) \(testCase.expect.unit)", actual: actual, failures: failures)
    }
}

@MainActor
@Suite("표기 정규화와 별칭")
struct NormalizationTests {
    @Test(arguments: RegressionCases.shared.normalization)
    func normalization(_ testCase: NormalizationCase) {
        var failures: [Failure] = []
        let input: String
        let expected: String
        let actual: String
        if let alias = testCase.alias, let canonical = testCase.canonical {
            input = alias
            expected = "대표 이름 \(canonical)"
            let result = MealFoodNames.canonical(alias)
            actual = result
            if result != canonical {
                failures.append(Failure(type: .normalization, message: "‘\(alias)’ → ‘\(result)’ (기대 ‘\(canonical)’)"))
            }
        } else if let a = testCase.a, let b = testCase.b, let equal = testCase.equal {
            input = "\(a) / \(b)"
            expected = equal ? "같은 키" : "다른 키"
            let left = FoodReferenceCatalog.normalized(a)
            let right = FoodReferenceCatalog.normalized(b)
            actual = "\(left) / \(right)"
            if (left == right) != equal {
                failures.append(Failure(type: .normalization, message: "\(left) vs \(right)"))
            }
        } else {
            Issue.record("케이스 형식 오류: \(testCase.id)")
            return
        }
        report(suite: "정규화", id: testCase.id, input: input, expected: expected, actual: actual, failures: failures)
    }
}

@MainActor
@Suite("DB 검색과 정렬")
struct SearchTests {
    @Test(arguments: RegressionCases.shared.search)
    func search(_ testCase: SearchCase) async throws {
        let results = try await FoodCatalogService().search(query: testCase.query)
        let general = results.filter { $0.brand.isEmpty && $0.category != "가공식품" }
        var failures: [Failure] = []
        var expected: [String] = []
        var actual: [String] = []
        if let contains = testCase.expect.topGeneralContains {
            let within = testCase.expect.within ?? 1
            expected.append("일반 항목 상위 \(within)개에 ‘\(contains)’")
            if !general.prefix(within).contains(where: { $0.name.contains(contains) }) {
                failures.append(Failure(type: .search, message: "일반 항목 상위 \(within)개에 ‘\(contains)’ 없음"))
            }
            let names = general.prefix(3).map(\.name).joined(separator: " | ")
            actual.append(names.isEmpty ? "일반 항목 없음 (전체 \(results.count)건)" : names)
        }
        if let code = testCase.expect.firstProductCategoryCode {
            let product = results.first { $0.category == "가공식품" }
            expected.append("첫 가공식품 후보의 분류 코드 \(code)")
            if product?.categoryCode != code {
                failures.append(Failure(type: .search, message: "첫 가공식품 후보의 분류 코드가 \(code)가 아님"))
            }
            actual.append(product.map { "첫 가공식품 \($0.recordedName) [\($0.id), 분류 \($0.categoryCode.map(String.init) ?? "없음")]" } ?? "가공식품 후보 없음")
        }
        report(suite: "검색", id: testCase.id, input: testCase.query,
               expected: expected.joined(separator: ", "), actual: actual.joined(separator: " / "), failures: failures)
    }
}

@MainActor
@Suite("분량 타당성")
struct PlausibilityTests {
    @Test(arguments: RegressionCases.shared.plausibility)
    func plausibility(_ testCase: PlausibilityCase) {
        let estimate = MealPortionEstimate(amountPerUnit: testCase.amount, amountUnit: testCase.amountUnit)
        let result = estimate.isPlausible(for: testCase.unit, foodName: testCase.food)
        var failures: [Failure] = []
        if result != testCase.expect {
            failures.append(Failure(type: .plausibility, message: "\(result ? "통과시킴" : "거부함") (기대 \(testCase.expect ? "통과" : "거부"))"))
        }
        report(suite: "타당성", id: testCase.id,
               input: "\(testCase.food) 1\(testCase.unit) = \(testCase.amount.short)\(testCase.amountUnit)",
               expected: testCase.expect ? "통과" : "거부", actual: result ? "통과" : "거부", failures: failures)
    }
}

/// AI 호출 순서에 묶인 흐름 테스트. 결과(단위·분량·열량·구분)만 판정한다.
@MainActor
@Suite("식사 입력 결과")
struct MealEntryOutcomeTests {
    private static let maxQuestionRounds = 4
    private static let lineCalorieLimit = 1000.0
    private static let amountConfirmationTitle = "이 양이 맞나요?"

    @Test(arguments: RegressionCases.shared.meals)
    func meal(_ testCase: MealCase) async {
        let service = AIMealEntryService(interpreter: FakeMealFoodInterpreter(script: testCase.llm), catalog: FoodCatalogService())
        var failures: [Failure] = []
        var questionLog: [String] = []
        var shownText: [String] = []
        var caughtError: String?
        var items: [MealEntryItem] = []
        let answers = testCase.answers ?? []
        var answerIndex = 0
        do {
            var analysis = try await service.analyze(testCase.input)
            loop: while true {
                switch analysis {
                case .ready(let ready):
                    items = ready
                    break loop
                case .question(let question):
                    guard questionLog.count < Self.maxQuestionRounds else {
                        failures.append(Failure(type: .question, message: "질문이 \(Self.maxQuestionRounds)회를 넘음"))
                        break loop
                    }
                    let preferred = testCase.choose.flatMap { wanted in
                        question.choices.first { "\($0.title) \($0.subtitle ?? "")".contains(wanted) }
                    }
                    shownText.append(([question.title] + question.choices.map(\.title)).joined(separator: " / "))
                    if question.choices.isEmpty {
                        // 방문자가 고를 것이 없는 질문은 어떤 경로에서도 내지 않는다(#41).
                        failures.append(Failure(type: .question, message: "선택지 0개 질문: \(question.title)"))
                    }
                    if let first = preferred ?? question.choices.first {
                        questionLog.append("\(question.title) → \(first.title)\(first.subtitle.map { " (\($0))" } ?? "")")
                        analysis = try await service.resolve(first)
                    } else if var typed = question.clarification, typed.continuationInput != nil,
                              answers.indices.contains(answerIndex) {
                        // 선택지 없는 질문은 케이스에 적힌 사용자 입력(answers)을 순서대로 넣는다.
                        let answer = answers[answerIndex]
                        answerIndex += 1
                        typed.continuationInput?.details = answer
                        questionLog.append("\(question.title) → 입력 ‘\(answer)’")
                        analysis = try await service.resolve(typed)
                    } else {
                        questionLog.append("\(question.title) → (선택지 없음)")
                        failures.append(Failure(type: .question, message: "선택지 없는 질문: \(question.title)"))
                        break loop
                    }
                }
            }
        } catch {
            caughtError = error.localizedDescription
            if testCase.expect.errorContains == nil {
                failures.append(Failure(type: .error, message: "\(error.localizedDescription)"))
            }
        }

        let expect = testCase.expect
        if let excluded = expect.questionsExclude,
           let hit = shownText.first(where: { line in excluded.contains { line.contains($0) } }) {
            failures.append(Failure(type: .question, message: "나오면 안 되는 질문·선택지: \(hit)"))
        }
        // 방문자에게 무게(g·mL)를 묻지 않는다(#39).
        if let weight = questionLog.first(where: { $0.contains("중량을 알려주세요") }) {
            failures.append(Failure(type: .question, message: "무게 질문: \(weight)"))
        }
        if let max = expect.maxQuestions, questionLog.count > max {
            failures.append(Failure(type: .question, message: "질문 \(questionLog.count)회 (허용 \(max)회): \(questionLog.first ?? "")"))
        }

        // 모든 경로가 실패해 오류 화면이 나와야 하는 케이스(#41, 작업 G 표)
        if let expectedError = expect.errorContains {
            if let caughtError, !caughtError.contains(expectedError) {
                failures.append(Failure(type: .error, message: "오류 ‘\(caughtError)’ (기대 ‘\(expectedError)’)"))
            } else if caughtError == nil {
                failures.append(Failure(type: .error, message: "오류 화면 ‘\(expectedError)’이 나와야 하는데 오류 없음"))
            }
            report(suite: "식사", id: testCase.id, input: testCase.input, expected: testCase.expectedSummary,
                   actual: caughtError.map { "오류: \($0)" } ?? "오류 없음", questions: questionLog.count, questionLog: questionLog,
                   failures: failures)
            return
        }

        var actual = items.isEmpty ? "기록 없음" : ""
        if let names = expect.exactNames, items.map(\.food.name) != names {
            failures.append(Failure(type: .name, message: "기록 이름 \(items.map(\.food.name).joined(separator: ", ")) (기대 \(names.joined(separator: ", ")))"))
        }
        if let expected = expect.items {
            if items.count != expected.count {
                failures.append(Failure(type: .error, message: "음식 \(items.count)개로 기록됨 (기대 \(expected.count)개)"))
            }
            for (item, name) in zip(items, expected) {
                let databaseName = (try? await FoodCatalogService().food(id: item.food.id))?.name
                let names = [item.food.name, databaseName].compactMap { $0 }.map(FoodReferenceCatalog.normalized)
                if !names.contains(where: { $0.contains(FoodReferenceCatalog.normalized(name)) }) {
                    failures.append(Failure(type: .name, message: "‘\(item.food.name)’에 \(name) 없음"))
                }
            }
        } else if items.count > 1 {
            failures.append(Failure(type: .error, message: "음식 \(items.count)개로 기록됨"))
        }
        if let item = items.first {
            let food = item.food
            let amount = food.baseAmount * item.count
            let kcal = item.nutrition.calories
            let isGeneral = food.brand.isEmpty && food.category != "가공식품"
            // 유사 음식으로 기록되면 이름은 입력값이 남으므로, 실제로 참고한 DB 항목 이름도 함께 본다.
            let databaseName = (try? await FoodCatalogService().food(id: food.id))?.name
            let names = [food.name, databaseName].compactMap { $0 }.map(FoodReferenceCatalog.normalized)
            let shownName = databaseName.map { $0 == food.name ? food.recordedName : "\(food.recordedName) (DB: \($0))" } ?? food.recordedName
            actual = "\(shownName) · \(item.amountDescription) · \(amount.short)\(food.amountUnit) · \(kcal.short)kcal · \(isGeneral ? "일반" : "가공")"
                + (item.portionBasis.label.map { " · \($0)" } ?? "") + (item.volumeNote.map { " · \($0)" } ?? "")
                + (item.quantityNote.map { " · \($0)" } ?? "")
                + items.dropFirst().map { " ＋ \($0.food.name) · \($0.amountDescription) · \($0.nutrition.calories.short)kcal" }.joined()

            // 2026-11-15 결정: 1,000kcal를 넘는 줄은 막지 않고 "이 양이 맞나요?" 확인을 거쳐야 한다.
            let confirmedAmount = questionLog.contains { $0.hasPrefix(Self.amountConfirmationTitle) }
            for other in items where other.nutrition.calories > Self.lineCalorieLimit && !confirmedAmount {
                failures.append(Failure(type: .limit, message: "한 줄 \(other.nutrition.calories.short)kcal인데 양 확인 질문 없음 (1,000kcal 초과 시 확인 필요)"))
            }
            if expect.confirmsAmount == true, !confirmedAmount {
                failures.append(Failure(type: .question, message: "양 확인 질문(\(Self.amountConfirmationTitle))이 없음"))
            }
            if expect.asksAmount == true, !questionLog.contains(where: { $0.contains("얼마나 드셨나요") }) {
                failures.append(Failure(type: .question, message: "수량 질문이 없음"))
            }
            if let volume = expect.volumeAsWeight, (item.volumeNote != nil) != volume {
                failures.append(Failure(type: .amount, message: volume ? "국물 mL 안내가 없음" : "국물 mL 안내가 붙음: \(item.volumeNote ?? "")"))
            }
            if let source = expect.sourceContains, !item.food.source.contains(source) {
                failures.append(Failure(type: .name, message: "출처 ‘\(item.food.source)’에 ‘\(source)’ 없음"))
            }
            if let id = expect.foodID, item.food.id != id {
                failures.append(Failure(type: .name, message: "자료 \(item.food.id) (기대 \(id))"))
            }
            if expect.asksUnitEstimate == true,
               !questionLog.contains(where: { $0.contains("얼마나 드셨나요") && $0.contains("(약 ") }) {
                failures.append(Failure(type: .question, message: "AI 1단위 추정 수량 질문이 없음"))
            }
            if let assumed = expect.assumedQuantity, (item.quantityNote != nil) != assumed {
                failures.append(Failure(type: .amount, message: assumed ? "기본값 안내가 없음" : "기본값 안내가 붙음: \(item.quantityNote ?? "")"))
            }
            if let basis = expect.basis, item.portionBasis.rawValue != basis {
                failures.append(Failure(type: .amount, message: "분량 근거 \(item.portionBasis.rawValue) (기대 \(basis))"))
            }
            if expect.drink == true, food.servingUnit == "인분" {
                failures.append(Failure(type: .limit, message: "음료가 인분으로 기록됨"))
            }
            if let units = expect.units, !units.contains(food.servingUnit) {
                failures.append(Failure(type: .unit, message: "단위 \(food.servingUnit) (기대 \(units.joined(separator: "/")))"))
            }
            if let range = expect.amount {
                if !range.units.contains(food.amountUnit) {
                    failures.append(Failure(type: .unit, message: "분량 단위 \(food.amountUnit) (기대 \(range.units.joined(separator: "/")))"))
                } else if !(range.min...range.max).contains(amount) {
                    failures.append(Failure(type: .amount, message: "\(amount.short)\(food.amountUnit) (기대 \(range.min.short)~\(range.max.short))"))
                }
            }
            if let range = expect.kcal, !range.contains(kcal) {
                failures.append(Failure(type: .calories, message: "\(kcal.short)kcal (기대 \(range))"))
            }
            if let count = expect.count, abs(item.count - count) > 0.001 {
                failures.append(Failure(type: .amount, message: "수량 \(item.count.short) (기대 \(count.short))"))
            }
            if let kind = expect.kind, (kind == "general") != isGeneral {
                failures.append(Failure(type: .kind, message: "\(isGeneral ? "일반 음식" : "가공식품")으로 기록됨 (기대 \(kind == "general" ? "일반 음식" : "가공식품"))"))
            }
            if let expected = expect.nameContains,
               !names.contains(where: { name in expected.allSatisfy { name.contains(FoodReferenceCatalog.normalized($0)) } }) {
                failures.append(Failure(type: .name, message: "‘\(shownName)’에 \(expected.joined(separator: ",")) 없음"))
            }
            if let excluded = expect.nameExcludes,
               let hit = excluded.first(where: { word in names.contains { $0.contains(FoodReferenceCatalog.normalized(word)) } }) {
                failures.append(Failure(type: .name, message: "‘\(shownName)’에 ‘\(hit)’ 포함"))
            }
        } else if failures.isEmpty {
            failures.append(Failure(type: .error, message: "결과 없음"))
        }

        report(suite: "식사", id: testCase.id, input: testCase.input, expected: testCase.expectedSummary,
               actual: actual, questions: questionLog.count, questionLog: questionLog, failures: failures)
    }
}

@MainActor
func report(suite: String, id: String, input: String, expected: String, actual: String,
                    questions: Int? = nil, questionLog: [String] = [], failures: [Failure], details: [String] = []) {
    var seen = Set<String>()
    TestResultRecorder.record(.init(
        suite: suite, id: id, input: input, expected: expected, actual: actual,
        questions: questions, questionLog: questionLog, passed: failures.isEmpty,
        failureTypes: failures.map(\.type.rawValue).filter { seen.insert($0).inserted },
        reasons: failures.map(\.message),
        details: details
    ))
    for failure in failures {
        Issue.record("[\(failure.type.rawValue)] \(id) \(input): \(failure.message)")
    }
}
