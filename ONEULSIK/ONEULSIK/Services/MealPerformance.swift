import Foundation
import OSLog

nonisolated enum MealPerformance {
    @TaskLocal static var trace: Trace?

    @MainActor
    static func measure<Result>(_ operation: String, body: () async throws -> Result) async rethrows -> Result {
        #if DEBUG
        let trace = Trace(operation: operation)
        return try await $trace.withValue(trace) {
            var completed = false
            defer { trace.finish(completed: completed) }
            let result = try await body()
            completed = true
            return result
        }
        #else
        return try await body()
        #endif
    }

    static func begin(_ stage: String) -> Span? {
        guard let trace else { return nil }
        return Span(trace: trace, stage: stage)
    }

    struct Span {
        let trace: Trace
        let stage: String
        private let started = ContinuousClock.now

        func finish() {
            trace.record(stage, duration: started.duration(to: .now))
        }
    }

    final class Trace: @unchecked Sendable {
        private static let logger = Logger(subsystem: "ONEULSIK", category: "MealPerformance")
        private let lock = NSLock()
        private let identifier = UUID().uuidString
        private let operation: String
        private let started = ContinuousClock.now
        private var counts: [String: Int] = [:]
        private var milliseconds: [String: Double] = [:]

        init(operation: String) { self.operation = operation }

        func record(_ stage: String, duration: Duration) {
            lock.lock()
            counts[stage, default: 0] += 1
            milliseconds[stage, default: 0] += Self.milliseconds(duration)
            lock.unlock()
        }

        func finish(completed: Bool) {
            lock.lock()
            let counts = counts
            let milliseconds = milliseconds
            lock.unlock()
            let total = Self.milliseconds(started.duration(to: .now))
            let llmCount = counts.filter { $0.key.hasPrefix("llm.") }.values.reduce(0, +)
            let llmTime = milliseconds.filter { $0.key.hasPrefix("llm.") }.values.reduce(0, +)
            let dbTime = (milliseconds["db.search"] ?? 0) + (milliseconds["db.lookup"] ?? 0)
            let stages = counts.keys.sorted().map { "\($0)=\(counts[$0] ?? 0)/\(Int(milliseconds[$0] ?? 0))ms" }.joined(separator: " ")
            let message = "trace=\(identifier) operation=\(operation) completed=\(completed) total=\(Int(total))ms llm=\(llmCount)/\(Int(llmTime))ms db=\(Int(dbTime))ms \(stages)"
            Self.logger.debug("\(message, privacy: .public)")
            #if DEBUG
            if ProcessInfo.processInfo.environment["ONEULSIK_METRICS_STDOUT"] == "1" { print(message) }
            #endif
        }

        private static func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
    }
}
