import SwiftUI

struct FoodSearchView: View {
    let profile: UserProfile
    let mealType: MealType
    let recordedAt: Date
    let mealRecordStore: MealRecordStore
    let onSaved: () -> Void
    var availabilityMessage: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedFood: FoodCatalogItem?
    @State private var shouldDismissAfterSaving = false
    @State private var searchResults: [FoodCatalogItem] = []
    @State private var isSearching = true
    @State private var searchFailed = false
    @State private var showsAllProducts = false
    @FocusState private var isSearchFocused: Bool

    private let catalog = FoodCatalogService()

    private var generalFoods: [FoodCatalogItem] {
        searchResults.filter { $0.brand.isEmpty && $0.category != "가공식품" }
    }

    private var products: [FoodCatalogItem] {
        searchResults.filter { !$0.brand.isEmpty || $0.category == "가공식품" }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            if let availabilityMessage {
                Text(availabilityMessage)
                    .font(.pretendardMedium(12))
                    .foregroundStyle(Color.gray04)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if isSearching {
                        ProgressView()
                            .padding(.top, 32)
                    } else if searchFailed {
                        Text("음식 정보를 불러오지 못했어요. 잠시 후 다시 검색해주세요.")
                            .font(.pretendardMedium(14))
                            .foregroundStyle(Color.gray04)
                            .padding(.top, 32)
                    } else if searchResults.isEmpty {
                        Text("검색 결과가 없어요. 다른 이름으로 검색해보세요.")
                            .font(.pretendardMedium(14))
                            .foregroundStyle(Color.gray04)
                            .padding(.top, 32)
                    }

                    if !generalFoods.isEmpty && !products.isEmpty {
                        sectionTitle("일반 음식")
                    }
                    ForEach(generalFoods) { food in
                        foodRow(food)
                    }

                    if !products.isEmpty {
                        sectionTitle("브랜드·제품 음식")
                        ForEach(showsAllProducts || generalFoods.isEmpty ? products : Array(products.prefix(5))) { food in
                            foodRow(food)
                        }
                        if !showsAllProducts && !generalFoods.isEmpty && products.count > 5 {
                            Button("브랜드·제품 음식 더 보기 (\(products.count - 5)개)") {
                                showsAllProducts = true
                            }
                            .font(.pretendardMedium(14))
                            .foregroundStyle(Color.green03)
                            .padding(.vertical, 16)
                        }
                    }

                    if searchResults.count == 100 {
                        Text("상위 100개 결과예요. 음식명이나 브랜드를 더 입력해보세요.")
                            .font(.pretendardMedium(12))
                            .foregroundStyle(Color.gray04)
                            .padding(.vertical, 20)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.gray01)
        .preferredColorScheme(.light)
        .task(id: query) {
            await updateSearchResults()
        }
        .fullScreenCover(item: $selectedFood, onDismiss: finishQuantitySelection) { food in
            FoodQuantityPresentation(
                food: food,
                onCancel: {
                    shouldDismissAfterSaving = false
                    selectedFood = nil
                },
                onComplete: { selection in
                    save(food: food, selection: selection)
                }
            )
            .presentationBackground(.clear)
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.gray03)

                TextField("음식·브랜드 검색", text: $query)
                    .font(.pretendardMedium(16))
                    .foregroundStyle(Color.black01)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Color.gray02.opacity(0.3), in: Capsule())

            Button("취소") {
                dismiss()
            }
            .font(.pretendardMedium(16))
            .foregroundStyle(Color.black01)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.gray02.opacity(0.55))
                .frame(height: 1)
        }
    }

    private func foodRow(_ food: FoodCatalogItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                highlightedName(food.name)
                    .font(.pretendardMedium(16))
                    .lineLimit(2)

                if !food.brand.isEmpty {
                    Text(food.brand)
                        .font(.pretendardMedium(11))
                        .foregroundStyle(Color.gray04)
                        .lineLimit(1)
                }

                Text(food.selectionDescription)
                    .font(.pretendardMedium(12))
                    .foregroundStyle(Color.gray03)

            }

            Spacer()

            (
                Text(food.nutrition(for: (food.representativePortion?.grams ?? food.baseAmount) / food.baseAmount).calories, format: .number.precision(.fractionLength(0)))
                + Text("kcal")
            )
            .font(.pretendardMedium(16))
            .fixedSize()

            Button {
                selectedFood = food
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 20, height: 20)
                    .background(Color.green03, in: Circle())
                    .frame(width: 32, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(food.name) 추가")
        }
        .foregroundStyle(Color.black01)
        .padding(.vertical, 12)
        .frame(minHeight: 77)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.gray02.opacity(0.7))
                .frame(height: 1)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.pretendardSemiBold(13))
            .foregroundStyle(Color.gray04)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .padding(.bottom, 4)
    }

    private func highlightedName(_ name: String) -> Text {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty,
              let range = name.range(of: trimmedQuery, options: .caseInsensitive)
        else {
            return Text(name).foregroundColor(Color.black01)
        }

        return Text(String(name[..<range.lowerBound])).foregroundColor(Color.black01)
            + Text(String(name[range])).foregroundColor(Color.green03)
            + Text(String(name[range.upperBound...])).foregroundColor(Color.black01)
    }

    private func updateSearchResults() async {
        isSearching = true
        searchFailed = false
        searchResults = []
        showsAllProducts = false
        do {
            try await Task.sleep(for: .milliseconds(200))
            try Task.checkCancellation()
            let results = try await catalog.search(query: query)
            try Task.checkCancellation()
            searchResults = results
            isSearching = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            searchFailed = true
            isSearching = false
        }
    }

    private func save(food: FoodCatalogItem, selection: FoodAmountSelection) {
        do {
            try mealRecordStore.insert(
                food: food,
                selection: selection,
                mealType: mealType,
                recordedAt: recordedAt,
                kakaoUserID: profile.kakaoUserID
            )
            shouldDismissAfterSaving = true
            selectedFood = nil
        } catch {
            return
        }
    }

    private func finishQuantitySelection() {
        guard shouldDismissAfterSaving else { return }

        shouldDismissAfterSaving = false
        onSaved()
        dismiss()
    }
}
