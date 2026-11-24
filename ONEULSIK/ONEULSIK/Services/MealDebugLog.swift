import Foundation
import os

/// 실기기에서만 생기는 AI 식사 입력 문제를 진단하려고 DEBUG 빌드에서만 콘솔에 남기는 기록(2026-11-23, #37).
/// 모든 줄은 "[ONEULSIK-AI]"로 시작한다. Release 빌드에서는 아무것도 하지 않는다(#if DEBUG).
/// os.Logger 하나로 남겨 Xcode 콘솔에 한 번만 나온다. 수준은 notice다(2026-11-24, #41 2차 G): debug 수준은 기기 로그 저장소에
/// 남지 않고 실시간으로 연결된 동안에만 보인다. 실기기에서 양 확인 선택 뒤 "선택:"·"기록:" 줄이 빠졌는데, 같은 흐름을 화면 경로
/// (MealEntryViewModel)로 도는 테스트 D04에서는 두 줄이 한 번씩 남아 코드 경로 차이는 찾지 못했다. 저장되는 수준으로 올려 확인한다.
/// 남기는 줄(#41): 원문, 모델 단계 결과, 모든 질문(제목·선택지), 모든 선택("선택: …", 양 확인 질문 포함),
/// 모든 최종 기록("기록: …"), 모든 오류("오류: {단계} {원인}", 화면에서 생긴 시간 초과·결과 검증 오류 포함).
/// Xcode 콘솔과 macOS 콘솔 앱(기기 선택 후 "ONEULSIK-AI" 검색)에서 볼 수 있다.
nonisolated enum MealDebugLog {
    #if DEBUG
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ONEULSIK", category: "ONEULSIK-AI")

    /// os.Logger 하나로만 남긴다. print와 함께 쓰면 Xcode 콘솔에 같은 줄이 두 번 나온다(#39).
    static func log(_ message: @autoclosure () -> String) {
        let line = "[ONEULSIK-AI] " + message()
        logger.notice("\(line, privacy: .public)")
        capture?.append(line)
    }

    /// 테스트가 남은 줄을 확인할 때만 쓰는 수집기(#41). TaskLocal이라 그 테스트의 작업에서 남긴 줄만 모인다.
    final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        var lines: [String] { lock.withLock { stored } }
        func append(_ line: String) { lock.withLock { stored.append(line) } }
    }

    @TaskLocal static var capture: Capture?

    /// 앱 시작 시 설치된 빌드를 구분하는 정보. 빌드 시각은 실행 파일의 수정 시각(빌드 때 다시 써짐)으로 본다.
    /// 커밋 해시는 빌드 단계 스크립트 없이 앱 안에서 알 수 없어 남기지 않는다.
    static func logBuildInfo() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "-"
        let build = info["CFBundleVersion"] as? String ?? "-"
        let built = Bundle.main.executableURL
            .flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
            .map { ISO8601DateFormatter.string(from: $0, timeZone: .current, formatOptions: [.withInternetDateTime]) } ?? "-"
        log("빌드 정보: 버전 \(version)(\(build)), 빌드 시각(실행 파일 수정 시각) \(built), 커밋 해시 없음(빌드 스크립트 없이 알 수 없음)")
    }

    static func describe(_ input: MealFoodInput) -> String {
        "이름 \(input.name), 수량 \(input.quantity) \(input.unit), 브랜드 \(input.brand.isEmpty ? "-" : input.brand), 설명 \(input.details.isEmpty ? "-" : input.details)"
    }

    static func describe(_ analysis: MealEntryAnalysis) -> String {
        switch analysis {
        case .ready(let items):
            return "기록: " + items.map { item in
                let food = item.food
                return "\(food.id) \(food.name)\(food.brand.isEmpty ? "" : " · \(food.brand)") \(item.count)\(food.servingUnit)"
                    + " \(food.baseAmount * item.count)\(food.amountUnit) \(Int(item.nutrition.calories.rounded()))kcal"
                    + " 분량 근거 \(item.portionBasis.rawValue), 영양 근거 \(item.nutritionBasis.rawValue), 출처 \(food.source)"
            }.joined(separator: " | ")
        case .question(let question):
            let choices = question.choices.prefix(3).map { choice in
                choice.title + (choice.selection.map { " [\($0.food.id) \($0.food.name)]" } ?? "")
            }
            return "질문: \(question.title) 선택지 \(choices.joined(separator: ", "))"
        }
    }
    #else
    @inline(__always) static func log(_ message: @autoclosure () -> String) {}
    @inline(__always) static func logBuildInfo() {}
    #endif
}
