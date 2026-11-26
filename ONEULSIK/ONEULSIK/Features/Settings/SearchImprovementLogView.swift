import SwiftUI
import UIKit

/// 설정 > 검색 개선 기록(#51). 기기 안에만 남긴 "못 찾은·바꾼 음식" 기록을 보고, 전체 복사하고, 지운다.
/// 식사 기록(MealRecord)과는 따로 지워진다.
struct SearchImprovementLogView: View {
    let onBack: () -> Void
    var log: SearchImprovementLog = .shared

    @State private var entries: [SearchImprovementEntry] = []
    @State private var isConfirmingClear = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = log.exportText()
                    copied = true
                } label: {
                    Text(copied ? "복사했어요" : "전체 복사")
                        .font(.pretendardSemiBold(14))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.green03, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(entries.isEmpty)

                Button {
                    isConfirmingClear = true
                } label: {
                    Text("기록 지우기")
                        .font(.pretendardSemiBold(14))
                        .foregroundStyle(Color.black01)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.gray02.opacity(0.5), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(entries.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if entries.isEmpty {
                Spacer()
                Text("남은 기록이 없어요")
                    .font(.pretendardMedium(14))
                    .foregroundStyle(Color.gray03)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        Text("이 기기에만 남는 기록이에요. 외부로 보내지 않아요. (경우: a 영양정보 못 찾음, b 비슷한 음식 질문, c 이름 다름, d 제안 거절·다른 항목, e 열량 확인)")
                            .font(.pretendardMedium(12))
                            .foregroundStyle(Color.gray03)
                        ForEach(entries.reversed()) { entry in
                            Text(entry.summary)
                                .font(.pretendardMedium(13))
                                .foregroundStyle(Color.black01)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color.gray01)
        .preferredColorScheme(.light)
        .onAppear { entries = log.entries() }
        .confirmationDialog("검색 개선 기록을 모두 지울까요?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("기록 지우기", role: .destructive) {
                log.clear()
                entries = []
                copied = false
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("식사 기록은 지워지지 않아요.")
        }
    }

    private var header: some View {
        ZStack {
            Text("검색 개선 기록")
                .font(.pretendardSemiBold(16))
                .foregroundStyle(Color.black01)

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.black01)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("뒤로가기")

                Spacer()
            }
            .padding(.leading, 4)
        }
        .frame(height: 56)
    }
}
