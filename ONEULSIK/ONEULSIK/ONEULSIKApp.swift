//
//  ONEULSIKApp.swift
//  ONEULSIK
//
//  Created by 박정환 on 8/5/26.
//

import KakaoSDKAuth
import KakaoSDKCommon
import SwiftData
import SwiftUI

@main
struct ONEULSIKApp: App {
    private let modelContainer: ModelContainer
    @State private var authStore: AuthStore
    private let onboardingStore: OnboardingStore
    private let mealRecordStore: MealRecordStore
    private let weightRecordStore: WeightRecordStore

    init() {
        do {
            let modelContainer = try ModelContainer(
                for: UserProfile.self,
                MealRecord.self,
                WeightRecord.self
            )
            self.modelContainer = modelContainer
            _authStore = State(
                initialValue: AuthStore(modelContext: modelContainer.mainContext)
            )
            onboardingStore = OnboardingStore(modelContext: modelContainer.mainContext)
            mealRecordStore = MealRecordStore(modelContext: modelContainer.mainContext)
            weightRecordStore = WeightRecordStore(modelContext: modelContainer.mainContext)
        } catch {
            fatalError("SwiftData ModelContainer 생성 실패: \(error)")
        }

        MealDebugLog.logBuildInfo()

        if let appKey = AppConfiguration.kakaoNativeAppKey {
            KakaoSDK.initSDK(appKey: appKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authStore)
                .environment(onboardingStore)
                .environment(mealRecordStore)
                .environment(weightRecordStore)
                .onOpenURL { url in
                    if AuthApi.isKakaoTalkLoginUrl(url) {
                        _ = AuthController.handleOpenUrl(url: url)
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
