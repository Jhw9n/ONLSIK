import Foundation

struct CatalogBenchmarkRow: Codable {
    let query: String
    let milliseconds: [Double]
    let foods: [[String]]
}

@main
struct MealEntryBenchmark {
    @MainActor
    static func main() async throws {
        let arguments = CommandLine.arguments
        if arguments.contains("--live") {
            for text in [
                "김밥 한 줄",
                "김밥 한 줄, 쌀밥 한 공기, 미소된장국 한 그릇",
                "김밥 한 줄, 쌀밥 한 공기, 미소된장국 한 그릇, 비빔밥 반 인분, 회덮밥 한 인분, 고등어구이 한 접시, 참치김밥 한 줄, 치즈김밥 한 줄"
            ] {
                let started = ContinuousClock.now
                do {
                    switch try await AIMealEntryService().analyze(text) {
                    case .ready(let items):
                        print("LIVE ready count=\(items.count) elapsed=\(started.duration(to: .now))")
                        print(items.map { "\($0.food.id)|\($0.amountDescription)|\($0.basisDescription ?? "")|\($0.nutrition.calories)" })
                    case .question:
                        print("LIVE question elapsed=\(started.duration(to: .now))")
                    }
                } catch {
                    print("LIVE error=\(error) elapsed=\(started.duration(to: .now))")
                }
            }
            return
        }
        let catalog = FoodCatalogService()
        let queries = FoodReferenceCatalog.entries.flatMap(\.names) + [
            "", "밥", "김밥", "라면", "참치 김밥", "참치김밥", "김밥 참치", "KFC", "CJ",
            "순두부찌게", "돈까스", "돈가스", "오징어 젓갈", "없는음식검색987", "김밥 참치", "김 밥"
        ]
        var rows: [CatalogBenchmarkRow] = []
        for query in queries {
            var timings: [Double] = []
            var foods: [FoodCatalogItem] = []
            for attempt in 0..<3 {
                let started = ContinuousClock.now
                let result = try await catalog.search(query: query)
                let elapsed = started.duration(to: .now).components
                timings.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
                if attempt > 0 { precondition(result == foods, "Repeated query changed") }
                foods = result
            }
            rows.append(CatalogBenchmarkRow(query: query, milliseconds: timings, foods: foods.map {
                [$0.id, $0.name, $0.brand, $0.amountUnit, String($0.baseAmount), String($0.nutrition.calories),
                 String($0.nutrition.carbohydrateGrams), String($0.nutrition.proteinGrams), String($0.nutrition.fatGrams),
                 $0.source, $0.sourceDate, $0.category]
            }))
        }
        if let index = arguments.firstIndex(of: "--compare") {
            let previous = try JSONDecoder().decode([CatalogBenchmarkRow].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])))
            precondition(previous.count == rows.count)
            for (before, after) in zip(previous, rows) {
                precondition(before.query == after.query && before.foods == after.foods, "Results changed for \(after.query)")
            }
            print("PASS: \(rows.count) ordered search results, nutrition and metadata unchanged")
        }
        if let index = arguments.firstIndex(of: "--output") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(rows).write(to: URL(fileURLWithPath: arguments[index + 1]))
        }
        let first = rows.map { $0.milliseconds[0] }.sorted()
        let repeated = rows.flatMap { Array($0.milliseconds.dropFirst()) }.sorted()
        print("SEARCH cases=\(rows.count) first median=\(first[first.count / 2])ms repeated median=\(repeated[repeated.count / 2])ms")
    }
}
