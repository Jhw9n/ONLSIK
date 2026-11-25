import Foundation

/// 운동 환산 화면(#49)의 분석 결과. 식사 기록(MealRecord)으로 저장하지 않는다.
struct ExerciseGameResult: Equatable, Sendable {
    /// 결과 제목에 쓰는 음식 표시 이름(예: "{음식} 1인분", "{음식} 반마리", "{음식} 외 1개")
    let displayName: String
    /// 모든 음식의 열량 합계(kcal)
    let kcal: Double

    /// 조사를 붙인 제목(예: "{음식} 1인분은")
    var title: String { ExerciseGameAnalyzer.withTopicParticle(displayName) }
}

enum ExerciseGameError: Error, Equatable {
    /// 음식을 찾지 못했거나 기록할 수 없는 결과
    case notFound
    case timedOut
}

/// 먹고 싶은 음식 문장을 기존 식사 입력 분석 서비스(AIMealEntryService)로 분석해 열량만 얻는다(#49).
/// - 질문(MealEntryQuestion)은 사용자에게 보이지 않고 첫 선택지를 고른다. 열량 확인 질문의 첫 선택지는 "맞아요, 그대로 기록"이다.
/// - 선택은 최대 5번. 그래도 기록까지 가지 못하면 실패로 본다.
/// - 결과를 저장하지 않는다(MealRecordStore를 쓰지 않는다).
@MainActor
final class ExerciseGameAnalyzer {
    static let maxChoiceSteps = 5

    private let analyzer: any MealEntryAnalyzing
    private let timeout: Duration

    init(analyzer: (any MealEntryAnalyzing)? = nil, timeout: Duration = .seconds(60)) {
        self.analyzer = analyzer ?? AIMealEntryService()
        self.timeout = timeout
    }

    func analyze(_ text: String) async throws -> ExerciseGameResult {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 200 else { throw ExerciseGameError.notFound }
        let analyzer = self.analyzer
        let timeout = self.timeout
        return try await withThrowingTaskGroup(of: ExerciseGameResult.self) { group in
            group.addTask { @MainActor in try await Self.run(text, analyzer: analyzer) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ExerciseGameError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw ExerciseGameError.notFound }
            return result
        }
    }

    private static func run(_ text: String, analyzer: any MealEntryAnalyzing) async throws -> ExerciseGameResult {
        var analysis: MealEntryAnalysis
        do {
            analysis = try await analyzer.analyze(text)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ExerciseGameError.notFound
        }
        for step in 0...maxChoiceSteps {
            try Task.checkCancellation()
            switch analysis {
            case .ready(let items):
                guard !items.isEmpty, items.allSatisfy(\.isValid) else { throw ExerciseGameError.notFound }
                let kcal = items.reduce(0) { $0 + $1.nutrition.calories }
                guard kcal.isFinite, kcal > 0 else { throw ExerciseGameError.notFound }
                return ExerciseGameResult(displayName: displayName(items: items, text: text), kcal: kcal)
            case .question(let question):
                guard step < maxChoiceSteps, let first = question.choices.first else { throw ExerciseGameError.notFound }
                do {
                    analysis = try await analyzer.resolve(first)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw ExerciseGameError.notFound
                }
            }
        }
        throw ExerciseGameError.notFound
    }

    // MARK: - 표시 이름

    /// 음식 하나면 "이름 양"(예: {음식} 1인분, {음식} 반마리), 둘 이상이면 "첫 음식 이름 외 N개"
    static func displayName(items: [MealEntryItem], text: String) -> String {
        guard let first = items.first else { return "" }
        let name = shownName(first, text: text)
        if items.count > 1 { return "\(name) 외 \(items.count - 1)개" }
        return "\(name) \(amountText(first))"
    }

    /// 기록 이름 대신 사용자가 적은 표기를 쓴다. 참고표(FoodReferences.json)의 대표 이름·별칭 중 입력 문장에 들어 있는 가장 긴 것.
    /// 예: 입력한 이름이 참고표의 별칭이면 기록 이름(대표 이름) 대신 입력한 별칭으로 보인다(테스트 X03).
    static func shownName(_ item: MealEntryItem, text: String) -> String {
        let key = FoodReferenceCatalog.normalized(text)
        let names = [item.food.name] + (FoodReferenceCatalog.entry(for: item.food.name)?.names ?? [])
        let typed = names.filter { !$0.isEmpty && key.contains(FoodReferenceCatalog.normalized($0)) }
        return typed.max { FoodReferenceCatalog.normalized($0).count < FoodReferenceCatalog.normalized($1).count } ?? item.food.name
    }

    /// 양 표기. 0.5단위는 "반"(예: 반마리), g·mL로 기록했으면 그 양
    static func amountText(_ item: MealEntryItem) -> String {
        if item.usesWeight { return item.amountDescription }
        let count = item.count
        if abs(count - 0.5) < 0.000_001 { return "반\(item.food.servingUnit)" }
        return "\(count.formatted(.number.precision(.fractionLength(0...2))))\(item.food.servingUnit)"
    }

    /// 주제 조사 "은/는"을 마지막 글자 받침에 맞춰 붙인다. 숫자·영문은 읽는 소리로 본다.
    static func withTopicParticle(_ text: String) -> String {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return text }
        let hasFinal: Bool
        if let scalar = last.unicodeScalars.first, (0xAC00...0xD7A3).contains(scalar.value) {
            hasFinal = (scalar.value - 0xAC00) % 28 != 0
        } else {
            // 영, 일, 이, 삼, 사, 오, 육, 칠, 팔, 구 / 그램(g), 킬로그램(kg), 밀리리터(mL), 리터(L)
            let withFinal: Set<Character> = ["0", "1", "3", "6", "7", "8", "g", "G", "m", "M", "n", "N", "l"]
            hasFinal = withFinal.contains(last)
        }
        return text + (hasFinal ? "은" : "는")
    }
}
