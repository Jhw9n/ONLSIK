import Foundation

nonisolated struct FoodPortion: Hashable, Sendable {
    let unit: String
    let grams: Double
    /// 근거. https URL(외부 자료) 또는 "내부 기준: … (YYYY-MM-DD 결정)" 형식의 설명(술 용기 표와 같은 방식)
    let source: String
    /// 같은 대표 분량으로 계산하는 다른 단위(예: 1인분과 1접시를 같은 양으로 보는 메뉴)
    var equivalentUnits: [String] = []

    /// 외부 자료 URL. 내부 기준이면 nil
    var sourceURL: URL? {
        guard let url = URL(string: source), url.scheme == "https" else { return nil }
        return url
    }

    /// 외부 자료 없이 내부에서 정한 값인지
    var isInternalDecision: Bool { sourceURL == nil }

    func accepts(_ unit: String) -> Bool {
        unit == self.unit || equivalentUnits.contains(unit)
    }

    /// 출처가 URL이거나, 내부 기준이면 결정일이 적힌 설명이어야 한다.
    private static func isValidSource(_ source: String) -> Bool {
        if let url = URL(string: source), url.scheme == "https", url.host != nil { return true }
        return source.hasPrefix("내부 기준") && source.range(of: #"\d{4}-\d{2}-\d{2} 결정"#, options: .regularExpression) != nil
    }

    /// 대표 분량표. 같은 음식의 여러 표기를 names에 모은다. 출처는 https URL 또는 "내부 기준: … (YYYY-MM-DD 결정)".
    private struct Row {
        let names: [String]
        let unit: String
        let grams: Double
        let source: String
        var equivalentUnits: [String] = []
    }

    private static let riceSource = "https://www.foodsafetykorea.go.kr/upload/20170417/20170417053825_1492418305214.pdf"
    private static let mealSource = "https://www.foodsafetykorea.go.kr/portal/board/boardDetail.do?bbs_no=bbs039&menu_grp=MENU_NEW03&menu_no=4847&ntctxt_no=22493"
    private static let eggSource = "https://www.foodsafetykorea.go.kr/portal/cookrcp/cookrcpInfoDtl.do?menu_grp=MENU_NEW03&menu_no=3608&rcp_seq=3185"
    private static func guideSource(page: Int) -> String {
        "https://www.foodsafetykorea.go.kr/upload/mkisna/2013.pdf#page=\(page)"
    }

    private static let rows: [Row] = [
        Row(names: ["삼겹살구이"], unit: "인분", grams: 130, source: "내부 기준: 삼겹살 생고기 1인분 170g에 대응하는 조리 후 중량 (2026-11-15 결정)", equivalentUnits: ["접시"]),
        Row(names: ["카레라이스"], unit: "그릇", grams: 500, source: "https://www.foodsafetykorea.go.kr/upload/20150824/20150824011539_1440389739434.pdf"),
        Row(names: ["쌀밥", "흰쌀밥", "백미밥", "잡곡밥", "현미밥", "보리밥"], unit: "공기", grams: 210, source: riceSource),
        Row(names: ["김치찌개", "순두부찌개"], unit: "인분", grams: 400, source: mealSource),
        Row(names: ["자장면", "짜장면"], unit: "그릇", grams: 650, source: mealSource),
        Row(names: ["비빔밥", "회덮밥", "제육덮밥", "불고기덮밥"], unit: "인분", grams: 500, source: mealSource),
        Row(names: ["볶음밥"], unit: "인분", grams: 400, source: mealSource),
        Row(names: ["오므라이스", "쫄면"], unit: "인분", grams: 450, source: mealSource),
        Row(names: ["김밥"], unit: "줄", grams: 200, source: mealSource),
        Row(names: ["참치김밥", "김밥참치"], unit: "줄", grams: 250, source: mealSource),
        Row(names: ["삼계탕"], unit: "인분", grams: 1000, source: mealSource),
        Row(names: ["짬뽕"], unit: "그릇", grams: 1000, source: mealSource),
        Row(names: ["탕수육"], unit: "인분", grams: 200, source: mealSource),
        Row(names: ["해물칼국수", "칼국수해물"], unit: "그릇", grams: 900, source: mealSource),
        Row(names: ["생선초밥"], unit: "인분", grams: 300, source: mealSource),
        Row(names: ["군만두"], unit: "인분", grams: 250, source: mealSource),
        Row(names: ["물만두"], unit: "인분", grams: 120, source: mealSource),
        Row(names: ["우동"], unit: "그릇", grams: 700, source: mealSource),
        Row(names: ["갈비탕"], unit: "인분", grams: 600, source: mealSource),
        Row(names: ["물냉면", "콩국수"], unit: "그릇", grams: 800, source: mealSource),
        Row(names: ["비빔냉면"], unit: "그릇", grams: 550, source: mealSource),
        Row(names: ["달걀,생것", "달걀,삶은것", "계란", "삶은달걀", "삶은계란"], unit: "개", grams: 50, source: eggSource),
        Row(names: ["김밥치즈", "치즈김밥"], unit: "줄", grams: 250, source: guideSource(page: 55)),
        Row(names: ["갈치구이"], unit: "접시", grams: 250, source: guideSource(page: 8)),
        Row(names: ["고등어구이"], unit: "접시", grams: 250, source: guideSource(page: 9)),
        Row(names: ["돼지갈비구이", "돼지갈비구이간장", "갈비구이돼지고기"], unit: "접시", grams: 350, source: guideSource(page: 10)),
        Row(names: ["떡갈비"], unit: "접시", grams: 250, source: guideSource(page: 11)),
        Row(names: ["소불고기", "불고기소고기"], unit: "접시", grams: 200, source: guideSource(page: 12)),
        Row(names: ["햄버그스테이크", "햄버거스테이크"], unit: "인분", grams: 200, source: guideSource(page: 13)),
        Row(names: ["훈제오리", "오리훈제"], unit: "접시", grams: 250, source: guideSource(page: 14)),
        Row(names: ["떡국"], unit: "그릇", grams: 800, source: guideSource(page: 15)),
        Row(names: ["굴짬뽕", "짬뽕굴"], unit: "그릇", grams: 900, source: guideSource(page: 20)),
        Row(names: ["기스면"], unit: "그릇", grams: 1000, source: guideSource(page: 21)),
        Row(names: ["김치우동", "우동김치"], unit: "그릇", grams: 800, source: guideSource(page: 22)),
        Row(names: ["메밀국수", "모밀국수"], unit: "그릇", grams: 600, source: guideSource(page: 23)),
        Row(names: ["삼선우동", "우동삼선"], unit: "그릇", grams: 1000, source: guideSource(page: 24)),
        Row(names: ["삼선자장면", "삼선짜장면", "짜장면삼선", "자장면삼선"], unit: "그릇", grams: 700, source: guideSource(page: 25)),
        Row(names: ["삼선짬뽕", "짬뽕삼선"], unit: "그릇", grams: 900, source: guideSource(page: 26)),
        Row(names: ["수제비"], unit: "그릇", grams: 800, source: guideSource(page: 27)),
        Row(names: ["오일소스스파게티", "스파게티오일소스"], unit: "접시", grams: 400, source: guideSource(page: 28)),
        Row(names: ["울면"], unit: "그릇", grams: 1000, source: guideSource(page: 29)),
        Row(names: ["잔치국수", "국수잔치국수"], unit: "그릇", grams: 700, source: guideSource(page: 30)),
        Row(names: ["잡채"], unit: "접시", grams: 150, source: guideSource(page: 31)),
        Row(names: ["크림소스스파게티", "스파게티크림소스"], unit: "접시", grams: 400, source: guideSource(page: 32)),
        Row(names: ["토마토소스스파게티", "스파게티토마토소스"], unit: "접시", grams: 500, source: guideSource(page: 33)),
        Row(names: ["해물크림소스스파게티"], unit: "접시", grams: 500, source: guideSource(page: 34)),
        Row(names: ["해물토마토소스스파게티"], unit: "접시", grams: 500, source: guideSource(page: 35)),
        Row(names: ["도토리묵"], unit: "접시", grams: 100, source: guideSource(page: 37)),
        Row(names: ["홍어회무침"], unit: "접시", grams: 200, source: guideSource(page: 40)),
        Row(names: ["농어초밥", "초밥농어"], unit: "인분", grams: 250, source: guideSource(page: 41)),
        Row(names: ["류산슬덮밥", "유산슬덮밥"], unit: "인분", grams: 550, source: guideSource(page: 42)),
        Row(names: ["문어초밥", "초밥문어"], unit: "인분", grams: 250, source: guideSource(page: 43)),
        Row(names: ["삼선볶음밥", "볶음밥삼선"], unit: "인분", grams: 400, source: guideSource(page: 44)),
        Row(names: ["새우초밥", "초밥새우"], unit: "인분", grams: 250, source: guideSource(page: 45)),
        Row(names: ["새우튀김롤"], unit: "인분", grams: 300, source: guideSource(page: 46)),
        Row(names: ["송이덮밥"], unit: "인분", grams: 600, source: guideSource(page: 47)),
        Row(names: ["연어롤"], unit: "인분", grams: 300, source: guideSource(page: 48)),
        Row(names: ["연어초밥", "초밥연어"], unit: "인분", grams: 250, source: guideSource(page: 49)),
        Row(names: ["육회비빔밥", "비빔밥육회"], unit: "인분", grams: 450, source: guideSource(page: 50)),
        Row(names: ["장어덮밥"], unit: "인분", grams: 400, source: guideSource(page: 51)),
        Row(names: ["장어초밥", "초밥장어"], unit: "인분", grams: 250, source: guideSource(page: 52)),
        Row(names: ["짬뽕밥"], unit: "인분", grams: 900, source: guideSource(page: 53)),
        Row(names: ["충무김밥"], unit: "접시", grams: 400, source: guideSource(page: 54)),
        Row(names: ["캘리포니아롤"], unit: "인분", grams: 300, source: guideSource(page: 56)),
        Row(names: ["한치초밥", "초밥한치"], unit: "인분", grams: 250, source: guideSource(page: 57)),
        Row(names: ["해물덮밥"], unit: "인분", grams: 700, source: guideSource(page: 58)),
        Row(names: ["해물볶음밥", "볶음밥해물"], unit: "인분", grams: 400, source: guideSource(page: 59)),
        Row(names: ["낙지볶음"], unit: "접시", grams: 200, source: guideSource(page: 60)),
        Row(names: ["두부김치"], unit: "접시", grams: 250, source: guideSource(page: 61)),
        Row(names: ["라볶이"], unit: "접시", grams: 200, source: guideSource(page: 62)),
        Row(names: ["주꾸미볶음", "쭈꾸미볶음"], unit: "접시", grams: 200, source: guideSource(page: 63)),
        Row(names: ["곰보빵", "소보로빵"], unit: "개", grams: 70, source: guideSource(page: 64)),
        Row(names: ["만주"], unit: "개", grams: 35, source: guideSource(page: 65)),
        Row(names: ["머핀"], unit: "개", grams: 130, source: guideSource(page: 66)),
        Row(names: ["베이글"], unit: "개", grams: 120, source: guideSource(page: 67)),
        Row(names: ["생크림케이크"], unit: "인분", grams: 100, source: guideSource(page: 68)),
        Row(names: ["초콜릿케이크"], unit: "인분", grams: 100, source: guideSource(page: 69)),
        Row(names: ["치즈케이크"], unit: "인분", grams: 100, source: guideSource(page: 70)),
        Row(names: ["카스텔라", "카스테라"], unit: "개", grams: 70, source: guideSource(page: 71)),
        Row(names: ["간장게장", "게장간장"], unit: "접시", grams: 250, source: guideSource(page: 72)),
        Row(names: ["양념게장", "게장양념"], unit: "접시", grams: 200, source: guideSource(page: 74)),
        Row(names: ["고추전"], unit: "인분", grams: 150, source: guideSource(page: 75)),
        Row(names: ["김치전"], unit: "인분", grams: 150, source: guideSource(page: 76)),
        Row(names: ["깻잎전"], unit: "인분", grams: 150, source: guideSource(page: 77)),
        Row(names: ["녹두빈대떡", "빈대떡"], unit: "인분", grams: 100, source: guideSource(page: 78)),
        Row(names: ["동그랑땡"], unit: "개", grams: 15, source: guideSource(page: 79)),
        Row(names: ["동태전"], unit: "개", grams: 25, source: guideSource(page: 80)),
        Row(names: ["파전"], unit: "인분", grams: 150, source: guideSource(page: 81)),
        Row(names: ["해물파전"], unit: "인분", grams: 150, source: guideSource(page: 82)),
        Row(names: ["화양적"], unit: "개", grams: 50, source: guideSource(page: 83)),
        Row(names: ["갈치조림"], unit: "접시", grams: 100, source: guideSource(page: 84)),
        Row(names: ["고등어조림"], unit: "접시", grams: 100, source: guideSource(page: 85)),
        Row(names: ["두부조림"], unit: "접시", grams: 50, source: guideSource(page: 87)),
        Row(names: ["북어조림"], unit: "접시", grams: 100, source: guideSource(page: 89)),
        Row(names: ["잣죽"], unit: "그릇", grams: 700, source: guideSource(page: 92)),
        Row(names: ["참치죽"], unit: "그릇", grams: 800, source: guideSource(page: 93)),
        Row(names: ["부대찌개"], unit: "인분", grams: 600, source: guideSource(page: 94)),
        Row(names: ["콩비지찌개", "비지찌개"], unit: "인분", grams: 400, source: guideSource(page: 95)),
        Row(names: ["돼지고기수육", "수육돼지고기"], unit: "접시", grams: 300, source: guideSource(page: 96)),
        Row(names: ["소갈비찜", "갈비찜소고기"], unit: "접시", grams: 250, source: guideSource(page: 97)),
        Row(names: ["아구찜", "아귀찜"], unit: "접시", grams: 400, source: guideSource(page: 98)),
        Row(names: ["한방오리백숙"], unit: "그릇", grams: 300, source: guideSource(page: 99)),
        Row(names: ["홍어찜"], unit: "접시", grams: 250, source: guideSource(page: 100)),
        Row(names: ["감자탕"], unit: "인분", grams: 900, source: guideSource(page: 101)),
        Row(names: ["광어매운탕"], unit: "인분", grams: 600, source: guideSource(page: 102)),
        Row(names: ["닭볶음탕", "닭도리탕"], unit: "접시", grams: 300, source: guideSource(page: 103)),
        Row(names: ["대구매운탕"], unit: "인분", grams: 600, source: guideSource(page: 104)),
        Row(names: ["설렁탕"], unit: "인분", grams: 600, source: guideSource(page: 105)),
        Row(names: ["연포탕"], unit: "그릇", grams: 1000, source: guideSource(page: 106)),
        Row(names: ["우럭매운탕"], unit: "인분", grams: 600, source: guideSource(page: 107)),
        Row(names: ["장어탕"], unit: "그릇", grams: 800, source: guideSource(page: 108)),
        Row(names: ["닭강정"], unit: "접시", grams: 100, source: guideSource(page: 109)),
        Row(names: ["등심돈가스", "돈가스등심"], unit: "인분", grams: 200, source: guideSource(page: 110)),
        Row(names: ["미꾸라지튀김"], unit: "개", grams: 20, source: guideSource(page: 111)),
        Row(names: ["생선까스", "생선가스"], unit: "인분", grams: 200, source: guideSource(page: 112)),
        Row(names: ["안심돈가스", "돈가스안심"], unit: "인분", grams: 200, source: guideSource(page: 113)),
        Row(names: ["치즈돈가스", "돈가스치즈"], unit: "인분", grams: 250, source: guideSource(page: 114)),
        Row(names: ["치킨까스", "치킨가스"], unit: "인분", grams: 200, source: guideSource(page: 115)),
    ]

    /// 대표 분량표의 행별 이름 목록(점검 테스트용)
    static var tableNames: [[String]] { rows.map(\.names) }

    /// 이름 비교 키. 띄어쓰기·쉼표·괄호 같은 기호를 무시하고 표기 차이(돈까스/돈가스 등)를 맞춘다.
    static func lookupKey(_ name: String) -> String {
        FoodReferenceCatalog.normalized(name)
    }

    /// 표의 이름을 비교 키로 바꿔 둔 색인. 같은 키가 여러 번 나오면 먼저 나온 행을 쓴다.
    private static let index: [String: Row] = {
        var index: [String: Row] = [:]
        for row in rows {
            for name in row.names where index[lookupKey(name)] == nil {
                index[lookupKey(name)] = row
            }
        }
        return index
    }()

    /// 대표 분량. g 기준 일반 음식만 붙인다(g 값을 mL 항목에 쓰지 않는다).
    /// DB 이름으로 먼저 찾고, 없으면 그 항목을 가리키는 참고표(FoodReferences.json)의 대표 이름·별칭으로 찾는다.
    static func representative(for food: FoodCatalogItem) -> FoodPortion? {
        guard food.brand.isEmpty, food.category != "가공식품",
              food.servingGrams > 0, food.servingMilliliters == 0 else { return nil }
        let referenceNames = FoodReferenceCatalog.entries.filter { $0.matches(food) }.flatMap(\.names)
        for name in [food.name] + referenceNames {
            guard let row = index[lookupKey(name)], isValidSource(row.source) else { continue }
            return FoodPortion(unit: row.unit, grams: row.grams, source: row.source, equivalentUnits: row.equivalentUnits)
        }
        return nil
    }

    static func smallSideGrams(for name: String) -> Double? {
        let name = name.filter { !$0.isWhitespace }
        if name.hasSuffix("김치") || ["깍두기", "오이소박이", "단무지", "단무지무침"].contains(name) { return 30 }
        if name.hasSuffix("젓갈") || name.hasSuffix("젓") || ["멸치볶음", "잔멸치볶음", "볶음멸치"].contains(name) { return 10 }
        if name.hasSuffix("나물") || ["무말랭이", "무말랭이무침", "시금치무침", "콩나물무침", "오이무침"].contains(name) { return 30 }
        return nil
    }
}

nonisolated struct FoodAmountSelection {
    let amount: Double
    let portion: FoodPortion?

    var isValid: Bool {
        amount.isFinite && amount >= 0.1 && amount <= 10_000
            && (portion.map { $0.grams.isFinite && $0.grams > 0 } ?? true)
    }

    var count: Double { amount / (portion?.grams ?? 1) }

    static func parse(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard value.range(of: #"^\d+(?:\.\d{0,2})?$"#, options: .regularExpression) != nil,
              let amount = Double(value), FoodAmountSelection(amount: amount, portion: nil).isValid
        else { return nil }
        return amount
    }

    func recordingFood(from food: FoodCatalogItem) -> FoodCatalogItem {
        let basis = portion?.grams ?? 1
        return FoodCatalogItem(
            id: food.id, name: food.name,
            servingUnit: portion?.unit ?? food.amountUnit,
            servingGrams: food.servingMilliliters > 0 ? 0 : basis,
            nutrition: food.nutrition(for: basis / food.baseAmount),
            servingMilliliters: food.servingMilliliters > 0 ? basis : 0,
            brand: food.brand, source: food.source, sourceDate: food.sourceDate,
            category: food.category
        )
    }
}
