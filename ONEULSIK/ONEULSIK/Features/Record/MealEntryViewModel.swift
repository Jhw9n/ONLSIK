import Foundation
import Observation

@Observable
final class MealEntryViewModel {
    enum Phase {
        case idle
        case analyzing
        case question(MealEntryQuestion)
        case ready
        case failed(String)
    }

    private(set) var text = ""
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

    func updateText(_ value: String) {
        guard text != value else { return }
        cancelAnalysis()
        text = value
        items = []
        phase = .idle
        invalidQuantityIDs = []
        saveError = nil
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
        cancelAnalysis()
        guard text.count <= 500 else {
            phase = .failed(MealEntryError.inputTooLong.localizedDescription)
            return
        }
        let currentID = UUID()
        let submittedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        requestID = currentID
        retryChoice = choice
        items = []
        invalidQuantityIDs = []
        phase = .analyzing
        saveError = nil
        timeoutTask = Task { [weak self, analysisTimeout] in
            do { try await Task.sleep(for: analysisTimeout) } catch { return }
            guard let self, self.requestID == currentID else { return }
            self.analysisTask?.cancel()
            self.analysisTask = nil
            self.requestID = nil
            self.phase = .failed(MealEntryError.timedOut.localizedDescription)
        }
        analysisTask = Task { [weak self, analyzer] in
            do {
                let result: MealEntryAnalysis
                if let choice {
                    result = try await analyzer.resolve(choice)
                } else {
                    result = try await analyzer.analyze(submittedText)
                }
                try Task.checkCancellation()
                guard let self, self.requestID == currentID else { return }
                switch result {
                case .question(let question):
                    guard !question.choices.isEmpty || question.clarification != nil,
                          Set(question.choices.map(\.id)).count == question.choices.count
                    else { throw MealEntryError.invalidResult }
                    self.phase = .question(question)
                case .ready(let items):
                    try self.accept(items)
                }
                self.retryChoice = nil
                self.finishAnalysis()
            } catch {
                guard let self, self.requestID == currentID, !Task.isCancelled else { return }
                self.phase = .failed((error as? MealEntryError ?? .generationFailed).localizedDescription)
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
        text = meal.title
        do {
            try accept(meal.items)
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
        invalidQuantityIDs.remove(id)
    }

    func remove(_ id: UUID) {
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

    private func accept(_ result: [MealEntryItem]) throws {
        guard !result.isEmpty, result.allSatisfy(\.isValid), Set(result.map(\.id)).count == result.count else {
            throw MealEntryError.invalidResult
        }
        items = result
        invalidQuantityIDs = []
        phase = .ready
    }

    #if DEBUG
    func configurePreview(text: String, phase: Phase, recentMeals: [RecentMealEntry], items: [MealEntryItem] = []) {
        self.text = text
        self.phase = phase
        self.recentMeals = recentMeals
        self.items = items
    }
    #endif
}
