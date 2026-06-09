//
//  ProjectMayaIOSApp.swift
//  ProjectMayaIOS
//
//  Created by Hongji Fu on 5/23/25.
//

import SwiftUI

@main
struct ProjectMayaIOSApp: App {
    /// Shared order manager that lives for the whole app lifecycle.
    @StateObject private var orderManager = OrderManager()
    @StateObject private var authService = AuthService()
    @StateObject private var mealHistoryService = MealHistoryService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if authService.isAuthenticated {
                    LandingPage(authService: authService)
                } else {
                    SignInPage(authService: authService)
                }
            }
            .environmentObject(orderManager)
            .environmentObject(mealHistoryService)
            .onAppear {
                // Connect OrderManager to MealHistoryService
                orderManager.setMealHistoryService(mealHistoryService)
                mealHistoryService.configure(authService: authService)
            }
            .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    mealHistoryService.configure(authService: authService)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Cold/warm wake from background: renew the token if it
                // expired while suspended, then pull fresh meal history.
                guard phase == .active, authService.isAuthenticated else { return }
                authService.refreshSessionIfNeeded { success in
                    guard success else { return }
                    Task { await mealHistoryService.refreshFromRemoteIfNeeded() }
                }
            }
        }
    }
}
