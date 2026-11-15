import Foundation
import Observation

@Observable
final class MealEntryViewModel {
    struct InputRow: Identifiable {
        let id: UUID = UUID()
        var text: String = ""
    }

    enum Phase {
        case idle
        case analyzing
        case question(MealEntryQuestion)
        case ready
        case failed(String)
    }

    private(set) var inputRows: [InputRow] = [InputRow()]
    private(set) var activeRowID: UUID?
    private(set) var failedRowID: UUID?
    private(set) var showsSplitHint = false
    private var rowResults: [UUID: [MealEntryItem]] = [:]
    var text: String { inputRows.map(\.text).joined(separator: "\n") }
    var mealType: MealType
    private(set) var phase: Phase = .idle
    private(set) var items: [MealEntryItem] = []
    private(set) var invalidQuantityIDs: Set<UUID> = []
    private(set) var recentMeals: [RecentMealEntry] = []
    private(set) var recentMealsFailed = false
    private(set) var isSaving = false
    var saveError: String?

    @ObservationIgnored private let analyzer: any MealEntryAnalyzing
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var retryChoice: MealEntryChoice?
    @ObservationIgnored private let analysisTimeout: Duration

    init(mealType: MealType, analyzer: (any MealEntryAnalyzing)? = nil, analysisTimeout: Duration = .seconds(60)) {
        self.mealType = mealType
        self.analyzer = analyzer ?? AIMealEntryService()
        self.analysisTimeout = analysisTimeout
    }

    var canSubmit: Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSaving else { return false }
        if case .analyzing = phase { return false }
        return true
    }

    var canSave: Bool {
        guard case .ready = phase else { return false }
        return !isSaving && !items.isEmpty && invalidQuantityIDs.isEmpty && items.allSatisfy(\.isValid)
    }

    var totalCalories: Double { items.reduce(0) { $0 + $1.nutrition.calories } }
    /// 화면 합계. 음식별로 보이는 반올림 값의 합이라 카드 숫자를 더한 값과 항상 같다.
    var displayedTotalCalories: Int { items.reduce(0) { $0 + $1.displayedCalories } }

    static func calorieText(_ calories: Int) -> String {
        "약 \(calories.formatted(.number.grouping(.automatic))) kcal"
    }
    var canAddRow: Bool { inputRows.count < 8 && !isSaving }

    func isRowComplete(_ id: UUID) -> Bool { rowResults[id] != nil }

    @discardableResult
    func addRow(after id: UUID? = nil) -> UUID? {
        guard !isSaving else { return nil }
        let index = id.flatMap { rowID in inputRows.firstIndex { $0.id == rowID } } ?? (inputRows.count - 1)
        if inputRows[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inputRows[index].id
        }
        if inputRows.indices.contains(index + 1), inputRows[index + 1].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inputRows[index + 1].id
        }
        guard canAddRow else { return nil }
        let row = InputRow()
        inputRows.insert(row, at: index + 1)
        return row.id
    }

    @discardableResult
    func updateRow(_ id: UUID, text value: String) -> UUID? {
        guard !isSaving, let index = inputRows.firstIndex(where: { $0.id == id }), inputRows[index].text != value else { return nil }
        let lines = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        guard inputRows.count + lines.count - 1 <= 8 else {
            saveError = "한 번에 8줄까지 입력할 수 있어요. 나누어 붙여넣어주세요."
            return nil
        }
        cancelAnalysis()
        rowResults.removeValue(forKey: id)
        inputRows[index].text = lines[0]
        let added = lines.dropFirst().map { InputRow(text: $0) }
        inputRows.insert(contentsOf: added, at: index + 1)
        resetAfterEditing()
        return added.last?.id
    }

    @discardableResult
    func removeRow(_ id: UUID) -> UUID? {
        guard !isSaving, let index = inputRows.firstIndex(where: { $0.id == id }) else { return nil }
        cancelAnalysis()
        rowResults.removeValue(forKey: id)
        inputRows.remove(at: index)
        if inputRows.isEmpty { inputRows = [InputRow()] }
        resetAfterEditing()
        return inputRows[min(index, inputRows.count - 1)].id
    }

    private func refreshItems() {
        items = inputRows.flatMap { rowResults[$0.id] ?? [] }
        invalidQuantityIDs.formIntersection(Set(items.map(\.id)))
    }

    private func resetAfterEditing() {
        failedRowID = nil
        activeRowID = nil
        showsSplitHint = false
        saveError = nil
        refreshItems()
        let filled = inputRows.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        phase = !filled.isEmpty && filled.allSatisfy { rowResults[$0.id] != nil } && !items.isEmpty ? .ready : .idle
    }

    func updateText(_ value: String) {
        guard text != value else { return }
        cancelAnalysis()
        inputRows = value.components(separatedBy: "\n").map { InputRow(text: $0) }
        rowResults = [:]
        resetAfterEditing()
    }

    func submit() {
        guard canSubmit else { return }
        beginAnalysis(choice: nil)
    }

    func retry() {
        guard case .failed = phase else { return }
        beginAnalysis(choice: retryChoice)
    }

    private func beginAnalysis(choice: MealEntryChoice?) {
        let choiceRowID = activeRowID
        cancelAnalysis()
        failedRowID = nil
        showsSplitHint = false
        guard text.count <= 500, inputRows.count <= 8 else {
            phase = .failed(MealEntryError.inputTooLong.localizedDescription)
            return
        }
        let currentID = UUID()
        let pendingRows = inputRows.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rowResults[$0.id] == nil }
        requestID = currentID
        retryChoice = choice
        phase = .analyzing
        saveError = nil
        timeoutTask = Task { [weak self, analysisTimeout] in
            do { try await Task.sleep(for: analysisTimeout) } catch { return }
            guard let self, self.requestID == currentID else { return }
            self.analysisTask?.cancel()
            self.analysisTask = nil
            self.requestID = nil
            self.failedRowID = self.activeRowID
            self.phase = .failed(MealEntryError.timedOut.localizedDescription)
        }
        analysisTask = Task { [weak self, analyzer] in
            do {
                for row in pendingRows {
                    try Task.checkCancellation()
                    guard let self, self.requestID == currentID else { return }
                    self.activeRowID = row.id
                    let result: MealEntryAnalysis
                    if let choice, row.id == choiceRowID {
                        result = try await analyzer.resolve(choice)
                    } else {
                        self.retryChoice = nil
                        result = try await analyzer.analyze(row.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    try Task.checkCancellation()
                    guard self.requestID == currentID else { return }
                    switch result {
                    case .question(let question):
                        guard !question.choices.isEmpty || question.clarification != nil,
                              Set(question.choices.map(\.id)).count == question.choices.count
                        else { throw MealEntryError.invalidResult }
                        self.phase = .question(question)
                        self.retryChoice = nil
                        self.finishAnalysis()
                        return
                    case .ready(let resultItems):
                        try self.validate(resultItems)
                        let existingIDs = Set(self.items.map(\.id))
                        guard resultItems.allSatisfy({ !existingIDs.contains($0.id) }) else { throw MealEntryError.invalidResult }
                        self.rowResults[row.id] = resultItems
                        self.refreshItems()
                    }
                }
                guard let self, self.requestID == currentID else { return }
                try self.validate(self.items)
                self.phase = .ready
                self.activeRowID = nil
                self.retryChoice = nil
                self.finishAnalysis()
            } catch {
                guard let self, self.requestID == currentID, !Task.isCancelled else { return }
                let failure = error as? MealEntryError ?? .generationFailed
                self.failedRowID = self.activeRowID
                switch failure {
                case .foodNotFound, .invalidResult, .generationFailed: self.showsSplitHint = true
                default: self.showsSplitHint = false
                }
                self.phase = .failed(failure.localizedDescription)
                self.finishAnalysis()
            }
        }
    }

    func select(_ choice: MealEntryChoice) {
        guard case .question(let question) = phase,
              let currentChoice = question.choices.first(where: { $0.id == choice.id }) else { return }
        beginAnalysis(choice: currentChoice)
    }

    func answer(_ details: String) {
        let details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !details.isEmpty, details.count <= 200,
              case .question(let question) = phase,
              var choice = question.clarification,
              var input = choice.continuationInput else { return }
        input.details = details
        choice.continuationInput = input
        beginAnalysis(choice: choice)
    }

    func selectRecent(_ meal: RecentMealEntry) {
        cancelAnalysis()
        inputRows = [InputRow()]
        rowResults = [:]
        items = []
        invalidQuantityIDs = []
        failedRowID = nil
        activeRowID = nil
        showsSplitHint = false
        do {
            try validate(meal.items)
            guard meal.items.count <= 8 else { throw MealEntryError.inputTooLong }
            inputRows = meal.items.map { InputRow(text: "\($0.food.name) \($0.amountDescription)") }
            for (row, item) in zip(inputRows, meal.items) {
                rowResults[row.id] = [item]
            }
            refreshItems()
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func setQuantity(_ quantity: Double?, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        let divisor = item.servingCount * (item.usesWeight ? item.food.baseAmount : 1)
        guard let quantity, quantity.isFinite, (0.1...10000).contains(quantity), divisor > 0 else {
            invalidQuantityIDs.insert(id)
            return
        }
        var updated = item
        updated.scale = quantity / divisor
        guard updated.isValid else {
            invalidQuantityIDs.insert(id)
            return
        }
        items[index] = updated
        for row in inputRows {
            if let itemIndex = rowResults[row.id]?.firstIndex(where: { $0.id == id }) {
                rowResults[row.id]?[itemIndex] = updated
            }
        }
        invalidQuantityIDs.remove(id)
    }

    func remove(_ id: UUID) {
        for row in inputRows {
            rowResults[row.id]?.removeAll { $0.id == id }
        }
        items.removeAll { $0.id == id }
        invalidQuantityIDs.remove(id)
        if items.isEmpty { phase = .idle }
    }

    func loadRecentMeals(store: MealRecordStore, userID: Int64, date: Date) {
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)),
              let start = calendar.date(byAdding: .day, value: -30, to: end) else { return }
        do {
            recentMeals = RecentMealEntry.grouped(from: try store.records(for: userID, from: start, to: end))
            recentMealsFailed = false
        } catch {
            recentMeals = []
            recentMealsFailed = true
        }
    }

    func save(store: MealRecordStore, userID: Int64, date: Date) -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try store.insertMeal(items: items, mealType: mealType, recordedAt: date, kakaoUserID: userID)
            items = []
            rowResults = [:]
            phase = .idle
            return true
        } catch {
            saveError = "식사를 저장하지 못했어요. 다시 시도해주세요."
            return false
        }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        requestID = nil
        retryChoice = nil
        if case .analyzing = phase { phase = .idle }
    }

    private func finishAnalysis() {
        timeoutTask?.cancel()
        timeoutTask = nil
        analysisTask = nil
        requestID = nil
    }

    private func validate(_ result: [MealEntryItem]) throws {
        guard !result.isEmpty, result.allSatisfy(\.isValid), Set(result.map(\.id)).count == result.count else {
            throw MealEntryError.invalidResult
        }
    }

    #if DEBUG
    func configurePreview(text: String, phase: Phase, recentMeals: [RecentMealEntry], items: [MealEntryItem] = []) {
        inputRows = text.components(separatedBy: "\n").map { InputRow(text: $0) }
        self.phase = phase
        self.recentMeals = recentMeals
        self.items = []
        rowResults = [:]
        if case .ready = phase {
            rowResults[inputRows[0].id] = items
            refreshItems()
        }
        if case .question = phase { activeRowID = inputRows[0].id }
        if case .failed = phase { failedRowID = inputRows[0].id }
    }
    #endif
}
