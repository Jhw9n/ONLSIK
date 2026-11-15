import Foundation
import Testing
@testable import ONEULSIK

/// 메뉴 커버리지 점검. 합격/불합격을 판정하지 않고, 앱의 검색(FoodCatalogService.search) 결과만 기록한다.
/// Scripts/check_menu_coverage.py가 ONEULSIK_MENU_FILE(입력 목록)과 ONEULSIK_MENU_OUTPUT(JSON Lines)을
/// 넘길 때만 실행되며, 평소의 run_tests.sh에서는 건너뛴다.
@MainActor
@Suite("메뉴 커버리지 점검")
struct MenuCoverageTests {
    private static let environment = ProcessInfo.processInfo.environment

    private struct Row: Encodable {
        let category: String
        let menu: String
        let total: Int
        let general: Int
        let firstName: String
        let firstIsProcessed: Bool?
        let firstGeneralName: String
    }

    @Test(.enabled(if: environment["ONEULSIK_MENU_FILE"] != nil && environment["ONEULSIK_MENU_OUTPUT"] != nil))
    func coverage() async throws {
        let input = try String(contentsOfFile: Self.environment["ONEULSIK_MENU_FILE"]!, encoding: .utf8)
        let output = URL(fileURLWithPath: Self.environment["ONEULSIK_MENU_OUTPUT"]!)
        var category = ""
        var lines: [String] = []
        let encoder = JSONEncoder()
        for raw in input.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                category = String(line.dropFirst(3))
                continue
            }
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let results = try await FoodCatalogService().search(query: line)
            let general = results.filter { $0.brand.isEmpty && $0.category != "가공식품" }
            let first = results.first
            let row = Row(category: category, menu: line, total: results.count, general: general.count,
                          firstName: first?.recordedName ?? "",
                          firstIsProcessed: first.map { $0.category == "가공식품" || !$0.brand.isEmpty },
                          firstGeneralName: general.first?.name ?? "")
            lines.append(String(decoding: try encoder.encode(row), as: UTF8.self))
        }
        try (lines.joined(separator: "\n") + "\n").write(to: output, atomically: true, encoding: .utf8)
    }
}
