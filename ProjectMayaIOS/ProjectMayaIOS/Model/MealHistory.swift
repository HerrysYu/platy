import Foundation
import SwiftUI

/// Represents a completed meal with menu images, OCR data, and ordered items
struct CompletedMeal: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let restaurantName: String
    let menuImages: [MenuImage]
    let menuBlocks: [MenuBlocks]
    var orderedItems: [OrderItem]  // Made mutable for updates
    
    init(menuImages: [MenuImage], menuBlocks: [MenuBlocks], orderedItems: [OrderItem]) {
        self.id = UUID()
        self.timestamp = Date()
        // Use timestamp as restaurant name
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        self.restaurantName = formatter.string(from: self.timestamp)
        self.menuImages = menuImages
        self.menuBlocks = menuBlocks
        self.orderedItems = orderedItems
    }
    
    /// Get the first menu image for display
    var primaryImage: UIImage? {
        menuImages.first?.image
    }
    
    /// Get a display name for the meal (using the formatted timestamp)
    var displayName: String {
        return restaurantName // This is now the formatted timestamp
    }
    
    /// Get an appropriate emoji icon for the meal
    var icon: String {
        // Use first ordered item's category or default to generic food emoji
        if let firstItem = orderedItems.first {
            let dishName = firstItem.dish.name.lowercased()
            if dishName.contains("noodle") || dishName.contains("pasta") || dishName.contains("ramen") {
                return "🍜"
            } else if dishName.contains("rice") || dishName.contains("fried rice") {
                return "🍚"
            } else if dishName.contains("fish") || dishName.contains("seafood") {
                return "🐟"
            } else if dishName.contains("meat") || dishName.contains("beef") || dishName.contains("pork") {
                return "🥩"
            } else if dishName.contains("chicken") {
                return "🍗"
            } else if dishName.contains("vegetable") || dishName.contains("salad") {
                return "🥗"
            } else if dishName.contains("soup") {
                return "🍲"
            }
        }
        return "🍽️"
    }
}

/// Service for managing meal history with persistence
@MainActor
final class MealHistoryService: ObservableObject {
    @Published private(set) var recentMeals: [CompletedMeal] = []
    
    private let userDefaults = UserDefaults.standard
    private let mealsKey = "saved_meals"
    private let supabaseClient = SupabaseClient()
    /// Server storage is limited, so keep only the most recent few scans.
    private let maxMeals = 5

    /// Meals carry full image data, which blows past the ~4MB UserDefaults
    /// cap and silently fails to persist. Store them as a file instead.
    private static var mealsFileURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("saved_meals.json")
    }
    private weak var authService: AuthService?
    private var isRefreshingFromRemote = false
    private var lastRemoteRefreshDate: Date?
    private let remoteRefreshThrottle: TimeInterval = 45
    
    init() {
        loadMeals()
    }

    func configure(authService: AuthService) {
        self.authService = authService

        if authService.isAuthenticated {
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await refreshFromRemoteIfNeeded()
            }
        }
    }

    func refreshFromRemoteIfNeeded(force: Bool = false) async {
        guard !isRefreshingFromRemote else { return }
        if !force,
           let lastRemoteRefreshDate,
           Date().timeIntervalSince(lastRemoteRefreshDate) < remoteRefreshThrottle {
            return
        }
        await refreshFromRemote()
    }

    func refreshFromRemote() async {
        guard let token = authService?.getAuthToken() else { return }
        guard !isRefreshingFromRemote else { return }

        do {
            isRefreshingFromRemote = true
            defer {
                isRefreshingFromRemote = false
                lastRemoteRefreshDate = Date()
            }

            let remoteMeals = try await supabaseClient.fetchMeals(authToken: token)

            // Merge instead of overwrite so locally-saved meals that never
            // made it to Supabase aren't dropped from the UI.
            let remoteIDs = Set(remoteMeals.map(\.id))
            let localOnly = recentMeals.filter { !remoteIDs.contains($0.id) }
            let merged = (remoteMeals + localOnly)
                .sorted { $0.timestamp > $1.timestamp }

            // Enforce the storage cap: drop (and remotely delete) the overflow.
            if merged.count > maxMeals {
                for old in merged.suffix(from: maxMeals) {
                    deleteMealRemote(old.id)
                }
                recentMeals = Array(merged.prefix(maxMeals))
            } else {
                recentMeals = merged
            }
            saveMeals()
            print("☁️ Synced \(remoteMeals.count) meals from Supabase (kept \(localOnly.count) local-only)")
        } catch {
            print("⚠️ Supabase meal sync failed: \(error.localizedDescription)")
        }
    }
    
    /// Add a new completed meal to history
    func addMeal(menuImages: [MenuImage], menuBlocks: [MenuBlocks], orderedItems: [OrderItem]) {
        let meal = CompletedMeal(
            menuImages: menuImages,
            menuBlocks: menuBlocks,
            orderedItems: orderedItems
        )
        
        recentMeals.insert(meal, at: 0) // Add to beginning for most recent first

        // Keep only the most recent `maxMeals`; delete the overflow from the
        // server too so its storage stays bounded.
        if recentMeals.count > maxMeals {
            for old in recentMeals.suffix(from: maxMeals) {
                deleteMealRemote(old.id)
            }
            recentMeals = Array(recentMeals.prefix(maxMeals))
        }

        saveMeals()
        syncMealToRemote(meal)
        print("✅ Added new meal to history: \(meal.displayName)")
    }

    /// Remove a meal the user no longer wants (local + remote).
    func deleteMeal(_ meal: CompletedMeal) {
        recentMeals.removeAll { $0.id == meal.id }
        saveMeals()
        deleteMealRemote(meal.id)
        print("🗑️ Deleted meal: \(meal.displayName)")
    }

    func deleteMeals(at offsets: IndexSet) {
        let targets = offsets.map { recentMeals[$0] }
        recentMeals.remove(atOffsets: offsets)
        saveMeals()
        for meal in targets {
            deleteMealRemote(meal.id)
        }
    }

    private func deleteMealRemote(_ id: UUID) {
        guard let token = authService?.getAuthToken() else { return }
        Task {
            do {
                try await supabaseClient.deleteMeal(id: id, authToken: token)
                print("☁️ Removed meal from Supabase: \(id)")
            } catch {
                print("⚠️ Supabase meal delete failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Load meals from local storage (file first, legacy UserDefaults as
    /// one-time migration fallback).
    private func loadMeals() {
        let decoder = JSONDecoder()

        if let data = try? Data(contentsOf: Self.mealsFileURL),
           let meals = try? decoder.decode([CompletedMeal].self, from: data) {
            recentMeals = meals
            print("📱 Loaded \(meals.count) meals from disk")
            return
        }

        // Migrate any legacy UserDefaults payload, then clear the old key.
        if let data = userDefaults.data(forKey: mealsKey) {
            if let meals = try? decoder.decode([CompletedMeal].self, from: data) {
                recentMeals = meals
                print("📱 Migrated \(meals.count) meals from UserDefaults")
                saveMeals()
            }
            userDefaults.removeObject(forKey: mealsKey)
            return
        }

        print("📱 No saved meals found locally")
    }

    /// Save meals to disk (atomic write).
    private func saveMeals() {
        do {
            let data = try JSONEncoder().encode(recentMeals)
            try data.write(to: Self.mealsFileURL, options: .atomic)
            print("💾 Saved \(recentMeals.count) meals to disk")
        } catch {
            print("❌ Failed to save meals to disk: \(error)")
        }
    }
    
    /// Convert completed meals to the format expected by LandingPage
    func getMealsForDisplay() async -> [Meal] {
        return recentMeals.map { completedMeal in
            Meal(
                id: completedMeal.id,
                name: completedMeal.displayName,
                icon: completedMeal.icon
            )
        }
    }
    
    /// Get a completed meal by its ID
    func getCompletedMeal(by id: UUID) -> CompletedMeal? {
        return recentMeals.first { $0.id == id }
    }
    
    /// Update the most recent (current) meal's ordered items
    func updateCurrentMeal(orderedItems: [OrderItem]) {
        guard !recentMeals.isEmpty else {
            print("⚠️ No current meal to update")
            return
        }
        
        recentMeals[0].orderedItems = orderedItems
        saveMeals()
        syncMealToRemote(recentMeals[0])
        print("✅ Updated current meal: \(recentMeals[0].displayName)")
    }

    private func syncMealToRemote(_ meal: CompletedMeal) {
        guard let token = authService?.getAuthToken() else { return }

        Task {
            do {
                try await supabaseClient.upsertMeal(meal, authToken: token)
                print("☁️ Synced meal to Supabase: \(meal.displayName)")
            } catch {
                print("⚠️ Supabase meal save failed: \(error.localizedDescription)")
            }
        }
    }
}

/// Updated MealService implementation using real data
struct RealMealService: MealService {
    let historyService: MealHistoryService
    
    func fetchRecentMeals() async throws -> [Meal] {
        return await historyService.getMealsForDisplay()
    }
}
