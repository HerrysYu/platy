import Foundation
import SwiftUI

/// Represents a dish added to the current order.
/// Wraps a `DishDetail` model together with a quantity the user
/// intends to order.
struct OrderItem: Identifiable, Equatable, Codable {
    let id = UUID()
    var dish: DishDetail            // translated details
    var originalName: String        // original-language text
    var quantity: Int = 1
    
    static func == (lhs: OrderItem, rhs: OrderItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// A shared (Environment) object that keeps track of all dishes
/// the user has added to the order list.
@MainActor
final class OrderManager: ObservableObject {
    @Published private(set) var items: [OrderItem] = []
    @Published var hasOngoingMeal: Bool = false
    @Published var ongoingMealImages: [MenuImage] = []
    @Published var ongoingMealBlocks: [MenuBlocks] = []
    
    // Reference to meal history service for saving completed meals
    private weak var mealHistoryService: MealHistoryService?
    
    // Track if we're working with current meal vs historical meal
    @Published var isCurrentMeal: Bool = false
    
    // MARK: - Public helpers
    /// Add a dish to the list. If it already exists we increase its quantity by one.
    func add(dish: DishDetail, originalName: String) {
        if let idx = items.firstIndex(where: { $0.dish.name == dish.name }) {
            items[idx].quantity += 1
        } else {
            items.append(OrderItem(dish: dish, originalName: originalName, quantity: 1))
        }
        
        // Update current meal if this is an active session
        updateCurrentMealIfNeeded()
    }
    
    /// Remove a given order item entirely.
    func remove(item: OrderItem) {
        items.removeAll { $0.id == item.id }
        updateCurrentMealIfNeeded()
    }
    
    /// Remove items at the provided offsets (List swipe-to-delete convenience).
    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        updateCurrentMealIfNeeded()
    }
    
    /// Increase the quantity of a given item by one.
    func increment(item: OrderItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].quantity += 1
        updateCurrentMealIfNeeded()
    }
    
    /// Decrease the quantity of a given item by one (never below 1).
    func decrement(item: OrderItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].quantity = max(1, items[idx].quantity - 1)
        updateCurrentMealIfNeeded()
    }
    
    /// Convenience accessor for the total number of dishes in the order.
    var totalCount: Int {
        items.reduce(0) { $0 + $1.quantity }
    }
    
    // MARK: - Ongoing Meal Management
    /// Start an ongoing meal with menu images and blocks
    func startOngoingMeal(images: [MenuImage], blocks: [MenuBlocks]) {
        hasOngoingMeal = true
        ongoingMealImages = images
        ongoingMealBlocks = blocks
        isCurrentMeal = true  // This is a new current meal
    }
    
    /// Clear the ongoing meal
    func clearOngoingMeal() {
        hasOngoingMeal = false
        ongoingMealImages = []
        ongoingMealBlocks = []
        isCurrentMeal = false
    }
    
    /// Set the meal history service reference
    func setMealHistoryService(_ service: MealHistoryService) {
        self.mealHistoryService = service
    }
    
    /// Save the current ongoing meal to history
    func saveMealToHistory() {
        guard hasOngoingMeal, !ongoingMealImages.isEmpty else {
            print("⚠️ No ongoing meal to save")
            return
        }
        
        // Save the meal to history
        mealHistoryService?.addMeal(
            menuImages: ongoingMealImages,
            menuBlocks: ongoingMealBlocks,
            orderedItems: items
        )
        
        print("✅ Meal saved to history")
    }
    
    /// Load a historical meal for viewing (read-only, not ongoing)
    func loadHistoricalMeal(images: [MenuImage], blocks: [MenuBlocks], items: [OrderItem]) {
        // Don't set hasOngoingMeal = true for historical meals
        // Just temporarily store the data for viewing
        ongoingMealImages = images
        ongoingMealBlocks = blocks
        self.items = items
        isCurrentMeal = false  // This is a historical meal, don't update it
        print("📖 Loaded historical meal for viewing (not ongoing)")
    }
    
    /// Update current meal in history if this is an active current meal session
    private func updateCurrentMealIfNeeded() {
        guard isCurrentMeal, hasOngoingMeal else {
            // Only update if this is a current meal, not historical
            return
        }
        
        mealHistoryService?.updateCurrentMeal(orderedItems: items)
    }
}
