import Foundation
import SQLite3

struct FoodCatalogService {
    private static let database = FoodCatalogDatabase(
        url: Bundle.main.url(forResource: "FoodCatalog", withExtension: "sqlite")
    )

    func search(query: String) async throws -> [FoodCatalogItem] {
        let span = MealPerformance.begin("db.search")
        defer { span?.finish() }
        return try await Self.database.search(query: query).filter(FoodCatalogQuality.isUsable)
    }

    func food(id: String) async throws -> FoodCatalogItem? {
        let span = MealPerformance.begin("db.lookup")
        defer { span?.finish() }
        guard let food = try await Self.database.food(id: id), FoodCatalogQuality.isUsable(food) else { return nil }
        return food
    }

    static let previewFood = FoodCatalogItem(
        id: "preview-rice",
        name: "쌀밥",
        servingUnit: "회",
        servingGrams: 100,
        nutrition: NutritionValues(
            calories: 166,
            carbohydrateGrams: 37.33,
            proteinGrams: 3.36,
            fatGrams: 0.32
        )
    )
}

private actor FoodCatalogDatabase {
    private let url: URL?
    private let resultLimit = 100
    private let cacheLimit = 64
    private var connection: CatalogConnection?
    private var cache: [String: [FoodCatalogItem]] = [:]
    private var cacheOrder: [String] = []
    private let columns = "id, name, brand, basis_unit, calories, carbohydrates, protein, fat, source, source_date, category, package_amount, package_unit"

    init(url: URL?) {
        self.url = url
    }

    func search(query: String) throws -> [FoodCatalogItem] {
        try Task.checkCancellation()
        let key = "search:" + query
        if let cached = cachedFoods(for: key) { return cached }
        var foods: [FoodCatalogItem] = []
        var seen = Set<String>()
        for term in FoodReferenceCatalog.queries(for: query) {
            foods += try searchExact(query: term, preferredID: preferredID(for: query))
                .filter { seen.insert($0.id).inserted }
        }
        if foods.isEmpty {
            for reference in FoodReferenceCatalog.spellingCandidates(for: query) {
                foods += try searchExact(query: reference.referenceName, preferredID: reference.referenceID)
                    .filter { seen.insert($0.id).inserted }
            }
        }
        // 일반 음식이 하나도 없으면 앞쪽 수식어(FoodModifiers.json)를 떼고 다시 찾아 뒤에 붙인다.
        if !foods.contains(where: { $0.brand.isEmpty && $0.category != "가공식품" }),
           let stripped = FoodModifierCatalog.stripped(query) {
            var related: [FoodCatalogItem] = []
            for term in FoodReferenceCatalog.queries(for: stripped.base) {
                related += try searchExact(query: term, preferredID: preferredID(for: stripped.base))
                    .filter { seen.insert($0.id).inserted }
            }
            // 수식어 규칙(FoodModifiers.json) 순서로 다시 정렬한다. 같은 순위 안에서는 검색 순서를 유지한다.
            foods += related.enumerated().sorted { left, right in
                let leftRank = stripped.rank(left.element), rightRank = stripped.rank(right.element)
                return leftRank != rightRank ? leftRank < rightRank : left.offset < right.offset
            }.map(\.element)
        }
        try Task.checkCancellation()
        let result = Array(foods.prefix(resultLimit))
        cacheFoods(result, for: key)
        return result
    }

    func food(id: String) throws -> FoodCatalogItem? {
        try Task.checkCancellation()
        let key = "id:" + id
        if let cached = cachedFoods(for: key) { return cached.first }
        let foods = try execute("SELECT \(columns) FROM foods WHERE id = ? LIMIT 1", parameters: [id])
        try Task.checkCancellation()
        cacheFoods(foods, for: key)
        return foods.first
    }

    private func cachedFoods(for key: String) -> [FoodCatalogItem]? {
        guard let foods = cache[key] else { return nil }
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        MealPerformance.begin("db.cacheHit")?.finish()
        return foods
    }

    private func cacheFoods(_ foods: [FoodCatalogItem], for key: String) {
        cache[key] = foods
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        if cacheOrder.count > cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    /// 데이터 파일(FoodReferences.json, DrinkReferences.json)이 지정한 대표 일반 항목
    private func preferredID(for query: String) -> String? {
        FoodReferenceCatalog.entry(for: query)?.referenceID ?? DrinkReferenceCatalog.entry(for: query)?.generalReferenceID
    }

    private func searchExact(query: String, preferredID: String?) throws -> [FoodCatalogItem] {
        try Task.checkCancellation()

        var terms = query.split(whereSeparator: \.isWhitespace)
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }
        if terms.count == 1, let name = terms.first {
            for dish in ["김밥", "볶음밥", "찌개", "칼국수"] where name.hasSuffix(dish) && name != dish {
                terms = [String(name.dropLast(dish.count)), dish]
                break
            }
        }
        let priority = "CASE WHEN category = '가공식품' OR brand != '' THEN 2 ELSE priority END"
        let nameKey = "REPLACE(name_key, '돈까스', '돈가스')"
        let brandKey = "REPLACE(brand_key, '돈까스', '돈가스')"
        let isGeneralFood = "brand = '' AND category != '가공식품'"
        let nutritionKey = ["calories", "carbohydrates", "protein", "fat"]
            .map { "CASE WHEN \(isGeneralFood) THEN NULL ELSE \($0) END" }
            .joined(separator: ", ")
        var filter = ""
        var parameters: [String] = []
        if !terms.isEmpty {
            filter = " WHERE (" + terms.map { _ in "(\(nameKey) LIKE ? OR \(brandKey) LIKE ?)" }.joined(separator: " AND ") + ")"
            for term in terms {
                parameters += ["%\(term)%", "%\(term)%"]
            }
            if let reversed = reversedDishName(normalized(query)) {
                filter += " OR \(nameKey) LIKE ?"
                parameters.append("%\(reversed)%")
            }
        }
        var sql = """
            WITH matches AS (
                SELECT \(columns), \(nameKey) AS search_name, \(priority) AS display_priority,
                    ROW_NUMBER() OVER (
                        PARTITION BY \(nameKey), \(brandKey), basis_unit,
                            CASE WHEN \(isGeneralFood) THEN 0 ELSE 1 END, \(nutritionKey)
                        ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END, \(priority), source_date DESC, id
                    ) AS duplicate_rank
                FROM foods\(filter)
            )
            SELECT \(columns) FROM matches WHERE duplicate_rank = 1
            """
        parameters.insert(preferredID ?? "", at: 0)
        if !terms.isEmpty {
            // 이름 일치 순위: 전체 일치 > 쉼표로 나뉜 이름 조각 일치(예: "증류주, 소주, 희석식") >
            // 첫 단어 일치(예: "만두 군만두"의 "만두") > 접두사(예: "만두국") > 조각 접두사 >
            // 그 밖의 부분 일치(예: "채소 주스"의 "소주"). 이름 길이는 같은 순위 안에서만 본다.
            let segments = "(',' || REPLACE(name, ' ', '') || ',')"
            sql += """
                 ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END, display_priority,
                    CASE WHEN search_name IN (?, ?, ?) THEN 0 WHEN \(segments) LIKE ? THEN 1 WHEN name LIKE ? THEN 2
                         WHEN search_name LIKE ? THEN 3 WHEN \(segments) LIKE ? THEN 4 ELSE 5 END,
                    CASE WHEN category = '원재료성 식품' THEN 0 ELSE 1 END, length(name), name, source_date DESC, id
                """
            parameters.append(preferredID ?? "")
            let fullQuery = normalized(query)
            let compactQuery = query.filter { !$0.isWhitespace }
            parameters += [fullQuery, fullQuery + "생것", reversedDishName(fullQuery) ?? fullQuery,
                           "%,\(compactQuery),%", "\(compactQuery) %", "\(fullQuery)%", "%,\(compactQuery)%"]
        } else {
            sql += " ORDER BY display_priority, name, source_date DESC, id"
        }
        sql += " LIMIT \(resultLimit)"

        return try execute(sql, parameters: parameters)
    }

    private func execute(_ sql: String, parameters: [String]) throws -> [FoodCatalogItem] {
        try Task.checkCancellation()
        let span = MealPerformance.begin("db.query")
        defer { span?.finish() }
        if connection == nil {
            guard let url else { throw CatalogError.unavailable }
            let opening = MealPerformance.begin("db.open")
            defer { opening?.finish() }
            connection = try CatalogConnection(url: url)
        }
        guard let database = connection?.handle else { throw CatalogError.unavailable }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogError.unavailable
        }
        defer { sqlite3_finalize(statement) }
        for (index, parameter) in parameters.enumerated() {
            let result = parameter.withCString {
                sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard result == SQLITE_OK else { throw CatalogError.unavailable }
        }

        var foods: [FoodCatalogItem] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            try Task.checkCancellation()
            let isVolume = string(statement, column: 3) == "mL"
            // 제품 총중량은 영양 기준 단위(g/mL)와 같은 단위일 때만 쓴다.
            let packageAmount = sqlite3_column_double(statement, 11)
            let packageUnit = string(statement, column: 12).lowercased()
            let usesPackage = packageAmount.isFinite && packageAmount > 0 && packageUnit == (isVolume ? "ml" : "g")
            foods.append(FoodCatalogItem(
                id: string(statement, column: 0),
                name: string(statement, column: 1),
                servingUnit: "회",
                servingGrams: isVolume ? 0 : 100,
                nutrition: NutritionValues(
                    calories: sqlite3_column_double(statement, 4),
                    carbohydrateGrams: sqlite3_column_double(statement, 5),
                    proteinGrams: sqlite3_column_double(statement, 6),
                    fatGrams: sqlite3_column_double(statement, 7)
                ),
                servingMilliliters: isVolume ? 100 : 0,
                brand: string(statement, column: 2),
                source: string(statement, column: 8),
                sourceDate: string(statement, column: 9),
                category: string(statement, column: 10),
                packageAmount: usesPackage ? packageAmount : 0
            ))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw CatalogError.unavailable }
        return foods
    }

    private func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .replacingOccurrences(of: "계란", with: "달걀")
            .replacingOccurrences(of: "자장", with: "짜장")
            .replacingOccurrences(of: "흰쌀밥", with: "쌀밥")
            .replacingOccurrences(of: "돈까스", with: "돈가스")
    }

    private func reversedDishName(_ name: String) -> String? {
        for dish in ["김밥", "볶음밥", "찌개", "칼국수"] where name.hasSuffix(dish) && name != dish {
            return dish + name.dropLast(dish.count)
        }
        return nil
    }

    private func string(_ statement: OpaquePointer?, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private enum CatalogError: Error {
        case unavailable
    }

    private final class CatalogConnection {
        let handle: OpaquePointer

        init(url: URL) throws {
            var database: OpaquePointer?
            guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
                  let database else {
                sqlite3_close(database)
                throw CatalogError.unavailable
            }
            handle = database
        }

        deinit { sqlite3_close(handle) }
    }
}
