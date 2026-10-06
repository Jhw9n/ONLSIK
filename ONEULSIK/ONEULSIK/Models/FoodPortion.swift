import Foundation

nonisolated struct FoodPortion: Hashable, Sendable {
    let unit: String
    let grams: Double
    let sourceURL: URL

    static func representative(for food: FoodCatalogItem) -> FoodPortion? {
        guard food.brand.isEmpty, food.category != "가공식품",
              food.servingGrams > 0, food.servingMilliliters == 0 else { return nil }
        let name = food.name.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "돈까스", with: "돈가스")
        let riceSource = "https://www.foodsafetykorea.go.kr/upload/20170417/20170417053825_1492418305214.pdf"
        let mealSource = "https://www.foodsafetykorea.go.kr/portal/board/boardDetail.do?bbs_no=bbs039&menu_grp=MENU_NEW03&menu_no=4847&ntctxt_no=22493"
        let eggSource = "https://www.foodsafetykorea.go.kr/portal/cookrcp/cookrcpInfoDtl.do?menu_grp=MENU_NEW03&menu_no=3608&rcp_seq=3185"
        let portion: (String, Double, String)
        switch name {
        case "쌀밥", "흰쌀밥", "백미밥", "잡곡밥", "현미밥", "보리밥":
            portion = ("공기", 210, riceSource)
        case "김치찌개", "순두부찌개":
            portion = ("인분", 400, mealSource)
        case "자장면", "짜장면":
            portion = ("그릇", 650, mealSource)
        case "비빔밥", "회덮밥", "제육덮밥", "불고기덮밥":
            portion = ("인분", 500, mealSource)
        case "볶음밥":
            portion = ("인분", 400, mealSource)
        case "오므라이스", "쫄면":
            portion = ("인분", 450, mealSource)
        case "김밥":
            portion = ("줄", 200, mealSource)
        case "참치김밥", "김밥참치":
            portion = ("줄", 250, mealSource)
        case "삼계탕":
            portion = ("인분", 1000, mealSource)
        case "짬뽕":
            portion = ("그릇", 1000, mealSource)
        case "탕수육":
            portion = ("인분", 200, mealSource)
        case "해물칼국수", "칼국수해물":
            portion = ("그릇", 900, mealSource)
        case "생선초밥":
            portion = ("인분", 300, mealSource)
        case "군만두":
            portion = ("인분", 250, mealSource)
        case "물만두":
            portion = ("인분", 120, mealSource)
        case "우동":
            portion = ("그릇", 700, mealSource)
        case "갈비탕":
            portion = ("인분", 600, mealSource)
        case "물냉면", "콩국수":
            portion = ("그릇", 800, mealSource)
        case "비빔냉면":
            portion = ("그릇", 550, mealSource)
        case "달걀,생것", "달걀,삶은것", "계란", "삶은달걀", "삶은계란":
            portion = ("개", 50, eggSource)
        default:
            return additionalPortion(for: name)
        }
        guard let url = URL(string: portion.2) else { return nil }
        return FoodPortion(unit: portion.0, grams: portion.1, sourceURL: url)
    }

    private static func additionalPortion(for name: String) -> FoodPortion? {
        let portion: (unit: String, grams: Double, page: Int)
        switch name {
        case "김밥치즈", "치즈김밥": portion = ("줄", 250, 55)
        case "갈치구이": portion = ("접시", 250, 8)
        case "고등어구이": portion = ("접시", 250, 9)
        case "돼지갈비구이", "갈비구이돼지고기": portion = ("접시", 350, 10)
        case "떡갈비": portion = ("접시", 250, 11)
        case "소불고기", "불고기소고기": portion = ("접시", 200, 12)
        case "햄버그스테이크", "햄버거스테이크": portion = ("인분", 200, 13)
        case "훈제오리", "오리훈제": portion = ("접시", 250, 14)
        case "떡국": portion = ("그릇", 800, 15)
        case "굴짬뽕", "짬뽕굴": portion = ("그릇", 900, 20)
        case "기스면": portion = ("그릇", 1000, 21)
        case "김치우동", "우동김치": portion = ("그릇", 800, 22)
        case "메밀국수", "모밀국수": portion = ("그릇", 600, 23)
        case "삼선우동", "우동삼선": portion = ("그릇", 1000, 24)
        case "삼선자장면", "삼선짜장면", "짜장면삼선", "자장면삼선": portion = ("그릇", 700, 25)
        case "삼선짬뽕", "짬뽕삼선": portion = ("그릇", 900, 26)
        case "수제비": portion = ("그릇", 800, 27)
        case "오일소스스파게티", "스파게티오일소스": portion = ("접시", 400, 28)
        case "울면": portion = ("그릇", 1000, 29)
        case "잔치국수", "국수잔치국수": portion = ("그릇", 700, 30)
        case "잡채": portion = ("접시", 150, 31)
        case "크림소스스파게티", "스파게티크림소스": portion = ("접시", 400, 32)
        case "토마토소스스파게티", "스파게티토마토소스": portion = ("접시", 500, 33)
        case "해물크림소스스파게티": portion = ("접시", 500, 34)
        case "해물토마토소스스파게티": portion = ("접시", 500, 35)
        case "도토리묵": portion = ("접시", 100, 37)
        case "홍어회무침": portion = ("접시", 200, 40)
        case "농어초밥", "초밥농어": portion = ("인분", 250, 41)
        case "류산슬덮밥", "유산슬덮밥": portion = ("인분", 550, 42)
        case "문어초밥", "초밥문어": portion = ("인분", 250, 43)
        case "삼선볶음밥", "볶음밥삼선": portion = ("인분", 400, 44)
        case "새우초밥", "초밥새우": portion = ("인분", 250, 45)
        case "새우튀김롤": portion = ("인분", 300, 46)
        case "송이덮밥": portion = ("인분", 600, 47)
        case "연어롤": portion = ("인분", 300, 48)
        case "연어초밥", "초밥연어": portion = ("인분", 250, 49)
        case "육회비빔밥", "비빔밥육회": portion = ("인분", 450, 50)
        case "장어덮밥": portion = ("인분", 400, 51)
        case "장어초밥", "초밥장어": portion = ("인분", 250, 52)
        case "짬뽕밥": portion = ("인분", 900, 53)
        case "충무김밥": portion = ("접시", 400, 54)
        case "캘리포니아롤": portion = ("인분", 300, 56)
        case "한치초밥", "초밥한치": portion = ("인분", 250, 57)
        case "해물덮밥": portion = ("인분", 700, 58)
        case "해물볶음밥", "볶음밥해물": portion = ("인분", 400, 59)
        case "낙지볶음": portion = ("접시", 200, 60)
        case "두부김치": portion = ("접시", 250, 61)
        case "라볶이": portion = ("접시", 200, 62)
        case "주꾸미볶음", "쭈꾸미볶음": portion = ("접시", 200, 63)
        case "곰보빵", "소보로빵": portion = ("개", 70, 64)
        case "만주": portion = ("개", 35, 65)
        case "머핀": portion = ("개", 130, 66)
        case "베이글": portion = ("개", 120, 67)
        case "생크림케이크": portion = ("인분", 100, 68)
        case "초콜릿케이크": portion = ("인분", 100, 69)
        case "치즈케이크": portion = ("인분", 100, 70)
        case "카스텔라", "카스테라": portion = ("개", 70, 71)
        case "간장게장", "게장간장": portion = ("접시", 250, 72)
        case "양념게장", "게장양념": portion = ("접시", 200, 74)
        case "고추전": portion = ("인분", 150, 75)
        case "김치전": portion = ("인분", 150, 76)
        case "깻잎전": portion = ("인분", 150, 77)
        case "녹두빈대떡", "빈대떡": portion = ("인분", 100, 78)
        case "동그랑땡": portion = ("개", 15, 79)
        case "동태전": portion = ("개", 25, 80)
        case "파전": portion = ("인분", 150, 81)
        case "해물파전": portion = ("인분", 150, 82)
        case "화양적": portion = ("개", 50, 83)
        case "갈치조림": portion = ("접시", 100, 84)
        case "고등어조림": portion = ("접시", 100, 85)
        case "두부조림": portion = ("접시", 50, 87)
        case "북어조림": portion = ("접시", 100, 89)
        case "잣죽": portion = ("그릇", 700, 92)
        case "참치죽": portion = ("그릇", 800, 93)
        case "부대찌개": portion = ("인분", 600, 94)
        case "콩비지찌개", "비지찌개": portion = ("인분", 400, 95)
        case "돼지고기수육", "수육돼지고기": portion = ("접시", 300, 96)
        case "소갈비찜", "갈비찜소고기": portion = ("접시", 250, 97)
        case "아구찜", "아귀찜": portion = ("접시", 400, 98)
        case "한방오리백숙": portion = ("그릇", 300, 99)
        case "홍어찜": portion = ("접시", 250, 100)
        case "감자탕": portion = ("인분", 900, 101)
        case "광어매운탕": portion = ("인분", 600, 102)
        case "닭볶음탕", "닭도리탕": portion = ("접시", 300, 103)
        case "대구매운탕": portion = ("인분", 600, 104)
        case "설렁탕": portion = ("인분", 600, 105)
        case "연포탕": portion = ("그릇", 1000, 106)
        case "우럭매운탕": portion = ("인분", 600, 107)
        case "장어탕": portion = ("그릇", 800, 108)
        case "닭강정": portion = ("접시", 100, 109)
        case "등심돈가스", "돈가스등심": portion = ("인분", 200, 110)
        case "미꾸라지튀김": portion = ("개", 20, 111)
        case "생선까스", "생선가스": portion = ("인분", 200, 112)
        case "안심돈가스", "돈가스안심": portion = ("인분", 200, 113)
        case "치즈돈가스", "돈가스치즈": portion = ("인분", 250, 114)
        case "치킨까스", "치킨가스": portion = ("인분", 200, 115)
        default: return nil
        }
        guard let url = URL(string: "https://www.foodsafetykorea.go.kr/upload/mkisna/2013.pdf#page=\(portion.page)") else { return nil }
        return FoodPortion(unit: portion.unit, grams: portion.grams, sourceURL: url)
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
