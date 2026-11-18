import Foundation

/// Scripts/run_tests.sh가 보고서를 만들 수 있도록 케이스별 결과를 JSON Lines로 남긴다.
/// 경로는 xcodebuild에 TEST_RUNNER_ONEULSIK_REPORT_FILE로 전달된다. 값이 없으면 기록하지 않는다.
@MainActor
enum TestResultRecorder {
    struct Record: Encodable {
        let suite: String
        let id: String
        let input: String
        let expected: String
        let actual: String
        let questions: Int?
        let questionLog: [String]
        let passed: Bool
        let failureTypes: [String]
        let reasons: [String]
    }

    static func record(_ record: Record) {
        guard let path = ProcessInfo.processInfo.environment["ONEULSIK_REPORT_FILE"], !path.isEmpty,
              var data = try? JSONEncoder().encode(record) else { return }
        data.append(0x0A)
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

/// 실패 사유를 유형별로 묶기 위한 태그
enum FailureType: String {
    case question = "확인 질문"
    case unit = "단위"
    case amount = "분량 범위"
    case calories = "열량 범위"
    case kind = "일반/가공 구분"
    case name = "음식 이름"
    case limit = "공통 상한"
    case error = "오류·기록 실패"
    case parsing = "분량·단위 파싱"
    case normalization = "정규화·별칭"
    case search = "검색·정렬"
    case plausibility = "분량 타당성"
}

struct Failure {
    let type: FailureType
    let message: String
}
