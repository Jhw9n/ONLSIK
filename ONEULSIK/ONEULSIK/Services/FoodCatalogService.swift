import Foundation
import SQLite3

struct FoodCatalogService {
    private static let database = FoodCatalogDatabase(
        url: Bundle.main.url(forResource: "FoodCatalog", withExtension: "sqlite")
    )

    func search(query: String) async throws -> [FoodCatalogItem] {
        try await Self.database.search(query: query)
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

    init(url: URL?) {
        self.url = url
    }

    func search(query: String) throws -> [FoodCatalogItem] {
        var foods: [FoodCatalogItem] = []
        var seen = Set<String>()
        for term in FoodReferenceCatalog.queries(for: query) {
            foods += try searchExact(query: term, reference: FoodReferenceCatalog.entry(for: query))
                .filter { seen.insert($0.id).inserted }
        }
        if foods.isEmpty {
            for reference in FoodReferenceCatalog.spellingCandidates(for: query) {
                foods += try searchExact(query: reference.referenceName, reference: reference)
                    .filter { seen.insert($0.id).inserted }
            }
        }
        return Array(foods.prefix(resultLimit))
    }

    private func searchExact(query: String, reference: FoodReference?) throws -> [FoodCatalogItem] {
        try Task.checkCancellation()
        guard let url else { throw CatalogError.unavailable }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw CatalogError.unavailable
        }
        defer { sqlite3_close(database) }

        var terms = query.split(whereSeparator: \.isWhitespace)
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }
        if terms.count == 1, let name = terms.first {
            for dish in ["김밥", "볶음밥", "찌개", "칼국수"] where name.hasSuffix(dish) && name != dish {
                terms = [String(name.dropLast(dish.count)), dish]
                break
            }
        }
        let columns = "id, name, brand, basis_unit, calories, carbohydrates, protein, fat, source, source_date, category"
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
        parameters.insert(reference?.referenceID ?? "", at: 0)
        if !terms.isEmpty {
            sql += " ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END, display_priority, CASE WHEN search_name IN (?, ?, ?) THEN 0 WHEN search_name LIKE ? THEN 1 ELSE 2 END, CASE WHEN category = '원재료성 식품' THEN 0 ELSE 1 END, length(name), name, source_date DESC, id"
            parameters.append(reference?.referenceID ?? "")
            let fullQuery = normalized(query)
            parameters += [fullQuery, fullQuery + "생것", reversedDishName(fullQuery) ?? fullQuery, "\(fullQuery)%"]
        } else {
            sql += " ORDER BY display_priority, name, source_date DESC, id"
        }
        sql += " LIMIT \(resultLimit)"

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
                category: string(statement, column: 10)
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
}
