import Foundation

/// 먹고 싶은 음식의 열량을 운동 시간으로 바꾸는 표(Resource/Data/ExerciseEquivalents.json, #49).
/// MET 값과 출처는 데이터 파일에만 둔다(2024 Adult Compendium of Physical Activities).
nonisolated struct ExerciseEquivalent: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let compendiumCode: String
    let met: Double
    /// 거리 계산용 시속(km). 없으면 거리를 보이지 않는다.
    let speedKmh: Double?
    let symbol: String
    let colorHex: String
    /// 설명 문구. {km}를 거리로 바꾼다.
    let detailFormat: String
    /// VoiceOver용 설명 문구. {km}를 거리로 바꾼다.
    let spokenDetailFormat: String

    /// 분당 소비 열량(kcal) = MET × 3.5 × 체중(kg) ÷ 200
    func kcalPerMinute(weightKG: Double) -> Double {
        met * 3.5 * weightKG / 200
    }

    /// 열량을 태우는 데 걸리는 시간(분, 반올림 전)
    func exactMinutes(kcal: Double, weightKG: Double) -> Double {
        let perMinute = kcalPerMinute(weightKG: weightKG)
        guard perMinute > 0, kcal.isFinite, kcal > 0 else { return 0 }
        return kcal / perMinute
    }

    /// 화면에 보이는 시간(분). 반올림
    func minutes(kcal: Double, weightKG: Double) -> Int {
        Int(exactMinutes(kcal: kcal, weightKG: weightKG).rounded())
    }

    /// 거리(km, 소수 첫째 자리). 반올림 전 시간으로 계산한다.
    func kilometers(kcal: Double, weightKG: Double) -> Double? {
        guard let speedKmh else { return nil }
        return (speedKmh * exactMinutes(kcal: kcal, weightKG: weightKG) / 60 * 10).rounded() / 10
    }

    func detail(kcal: Double, weightKG: Double) -> String {
        Self.fill(detailFormat, kilometers: kilometers(kcal: kcal, weightKG: weightKG))
    }

    func spokenDetail(kcal: Double, weightKG: Double) -> String {
        Self.fill(spokenDetailFormat, kilometers: kilometers(kcal: kcal, weightKG: weightKG))
    }

    private static func fill(_ format: String, kilometers: Double?) -> String {
        guard let kilometers else { return format }
        return format.replacingOccurrences(of: "{km}", with: kilometers.formatted(.number.precision(.fractionLength(1))))
    }

    /// "○분", 60분 이상은 "○시간 ○분"(0분이면 "○시간")
    static func durationText(minutes: Int) -> String {
        let minutes = max(0, minutes)
        guard minutes >= 60 else { return "\(minutes)분" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
    }
}

nonisolated enum ExerciseEquivalentCatalog {
    private struct File: Decodable {
        let fallbackWeightKG: Double
        let exercises: [ExerciseEquivalent]
    }

    private static let file: File? = {
        guard let url = Bundle.main.url(forResource: "ExerciseEquivalents", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }()

    static var exercises: [ExerciseEquivalent] { file?.exercises ?? [] }

    /// 체중을 알 수 없을 때 쓰는 체중(kg)
    static var fallbackWeightKG: Double { file?.fallbackWeightKG ?? 65 }

    /// 계산에 쓸 체중. 가장 최근 체중 기록 → 프로필 체중 → 대체 체중(65kg) 순.
    /// 20kg 미만·300kg 초과는 쓰지 않는다. 대체 체중을 썼으면 isFallback이 true.
    static func weight(latestRecordTenthsKG: Int?, profileTenthsKG: Int?) -> (kg: Double, isFallback: Bool) {
        for tenths in [latestRecordTenthsKG, profileTenthsKG].compactMap({ $0 }) {
            let kg = Double(tenths) / 10
            if (20...300).contains(kg) { return (kg, false) }
        }
        return (fallbackWeightKG, true)
    }
}
