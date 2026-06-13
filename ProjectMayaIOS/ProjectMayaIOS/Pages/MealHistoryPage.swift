import SwiftUI

struct MealHistoryPage: View {
    @ObservedObject var authService: AuthService
    @EnvironmentObject private var mealHistoryService: MealHistoryService
    @EnvironmentObject private var orderManager: OrderManager
    @State private var selectedMeal: CompletedMeal?
    @State private var showMealDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PlatyScreenHeader(
                    title: "Meal History",
                    subtitle: "Jump back into translated menus you saved."
                )
                .platyEntrance()

                if mealHistoryService.recentMeals.isEmpty {
                    emptyState
                        .platyEntrance(delay: 0.08)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(mealHistoryService.recentMeals.enumerated()), id: \.element.id) { index, meal in
                            // Delete button is a sibling overlay (not nested in
                            // the open button) so its taps aren't swallowed.
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    selectedMeal = meal
                                    orderManager.loadHistoricalMeal(
                                        images: meal.menuImages,
                                        blocks: meal.menuBlocks,
                                        items: meal.orderedItems
                                    )
                                    showMealDetail = true
                                } label: {
                                    HistoryMealCard(meal: meal)
                                }
                                .buttonStyle(PlatyPressStyle())

                                Button {
                                    withAnimation(PlatyMotion.spring) {
                                        mealHistoryService.deleteMeal(meal)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundStyle(PlatyTheme.textSecondary)
                                        .frame(width: 30, height: 30)
                                        .background(Color.black.opacity(0.55))
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(PlatyTheme.border, lineWidth: 1))
                                }
                                .buttonStyle(PlatyPressStyle())
                                .padding(10)
                            }
                            .platyEntrance(delay: 0.04 * Double(index + 1))
                        }
                    }

                    Text("Only your 5 most recent scans are kept.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(PlatyTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 70)
            .padding(.bottom, 40)
        }
        .background(PlatyTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await mealHistoryService.refreshFromRemoteIfNeeded()
        }
        .navigationDestination(isPresented: $showMealDetail) {
            if let meal = selectedMeal {
                MenuPage(menuImageList: meal.menuImages, menuBlocksList: meal.menuBlocks, authService: authService, saveOnAppear: false)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "menucard")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(PlatyTheme.accent)

            Text("No meal history yet")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(PlatyTheme.textPrimary)

            Text("Scan a menu and Platy will save the translation here.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(PlatyTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 96)
        .padding(.horizontal, 24)
        .background(PlatyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PlatyTheme.border, lineWidth: 1)
        )
    }
}

private struct HistoryMealCard: View {
    let meal: CompletedMeal

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if let image = meal.primaryImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    PlatyTheme.surfaceRaised
                    Image(systemName: "fork.knife")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(PlatyTheme.textSecondary)
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(meal.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PlatyTheme.textPrimary)
                    .lineLimit(1)

                Text(meal.orderedItems.isEmpty ? "Translated menu" : "\(meal.orderedItems.count) dishes saved")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(PlatyTheme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(PlatyTheme.textTertiary)
        }
        .padding(14)
        .background(PlatyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PlatyTheme.border, lineWidth: 1)
        )
    }
}
