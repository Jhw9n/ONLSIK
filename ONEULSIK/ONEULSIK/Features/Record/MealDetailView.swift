import SwiftUI

struct MealDetailView: View {
    let mealType: MealType
    let dateText: String
    let records: [MealRecord]
    let onClose: () -> Void
    let onDelete: (MealRecord) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack {
                Text(mealType.title)
                    .font(.pretendardSemiBold(18))
                    .foregroundStyle(Color.black01)

                Spacer()

                Text(dateText)
                    .font(.pretendardMedium(18))
                    .foregroundStyle(Color.gray03)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(records) { record in
                        mealRecordRow(record)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Color.gray01)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.black01)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(height: 56)
        .padding(.top, 8)
    }

    private func mealRecordRow(_ record: MealRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.foodName)
                    .font(.pretendardMedium(16))
                    .foregroundStyle(Color.black01)

                Text(record.servingDescription)
                    .font(.pretendardMedium(12))
                    .foregroundStyle(Color.gray03)
            }

            Spacer()

            Text("\(formatted(record.calories))kcal")
                .font(.pretendardMedium(16))
                .foregroundStyle(Color.black01)

            Button {
                onDelete(record)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 20, height: 20)
                    .background(Color.green03, in: Circle())
                    .frame(width: 32, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(record.foodName) 삭제")
        }
        .frame(height: 77)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.gray02.opacity(0.7))
                .frame(height: 1)
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}
