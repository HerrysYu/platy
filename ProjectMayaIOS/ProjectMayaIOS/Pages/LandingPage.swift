import SwiftUI

struct Meal: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let icon: String
}

protocol MealService {
    func fetchRecentMeals() async throws -> [Meal]
}

/// Placeholder service used until the real history service is injected in
/// onAppear; it must stay empty so no invented data flashes on first render.
struct MockMealService: MealService {
    func fetchRecentMeals() async throws -> [Meal] {
        []
    }
}

@MainActor
final class MealListViewModel: ObservableObject {
    @Published private(set) var meals: [Meal] = []
    @Published var isLoading = false
    private var service: MealService

    init(service: MealService = MockMealService()) {
        self.service = service
    }

    func setService(_ newService: MealService) {
        service = newService
    }

    @Sendable
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            meals = try await service.fetchRecentMeals()
        } catch is CancellationError {
        } catch {
            print("[MealListViewModel] fetch failed: \(error)")
        }
    }
}

struct LandingPage: View {
    @StateObject private var vm: MealListViewModel
    @ObservedObject var authService: AuthService
    @EnvironmentObject private var mealHistoryService: MealHistoryService
    @EnvironmentObject private var orderManager: OrderManager
    @State private var toCamera = false
    @State private var showHistory = false
    @State private var showUserCenter = false
    @State private var selectedHistoricalMeal: CompletedMeal?
    @State private var showHistoricalMeal = false

    init(authService: AuthService) {
        self.authService = authService
        _vm = StateObject(wrappedValue: MealListViewModel(service: MockMealService()))
    }

    var body: some View {
        ZStack {
            PlatyTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    topBar
                        .platyEntrance()

                    scanCard
                        .platyEntrance(delay: 0.06)

                    if orderManager.hasOngoingMeal {
                        ongoingCard
                            .platyEntrance(delay: 0.1)
                    }

                    recentSection
                        .platyEntrance(delay: 0.14)
                }
                .padding(.horizontal, 24)
                .padding(.top, 64)
                .padding(.bottom, 44)
            }
        }
        .navigationDestination(isPresented: $toCamera) {
            CameraLandingScreen(authService: authService)
        }
        .navigationDestination(isPresented: $showHistory) {
            MealHistoryPage(authService: authService)
        }
        .navigationDestination(isPresented: $showUserCenter) {
            UserCenterPage(authService: authService)
        }
        .navigationDestination(isPresented: $showHistoricalMeal) {
            if let meal = selectedHistoricalMeal {
                MenuPage(menuImageList: meal.menuImages, menuBlocksList: meal.menuBlocks, authService: authService, saveOnAppear: false)
            }
        }
        .onAppear {
            vm.setService(RealMealService(historyService: mealHistoryService))
        }
        .task {
            await vm.load()
            await mealHistoryService.refreshFromRemoteIfNeeded()
        }
        .onReceive(mealHistoryService.$recentMeals) { _ in
            // Re-render once the remote sync (or a new save) lands, so a cold
            // start doesn't get stuck showing the initial empty snapshot.
            Task { await vm.load() }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            PlatyScreenHeader(title: "Platy", subtitle: "Your translated menus and saved meals")

            HStack(spacing: 10) {
                PlatyIconButton(systemName: "clock.arrow.circlepath", size: 48) {
                    showHistory = true
                }
                PlatyIconButton(systemName: "gearshape.fill", size: 48) {
                    showUserCenter = true
                }
            }
        }
    }

    private var scanCard: some View {
        PlatyCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(PlatyTheme.accent.opacity(0.18))
                            .frame(width: 62, height: 62)
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(PlatyTheme.accent)
                    }
                    .platyFloat(distance: 3, duration: 2.2)

                    Spacer()

                    PlatyScanPreview(height: 100)
                        .frame(maxWidth: 172)
                }

                Text("Menu Lens")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(PlatyTheme.textPrimary)

                PlatyPrimaryButton(title: "Open Camera", systemImage: "camera") {
                    toCamera = true
                }
            }
            .padding(22)
        }
    }

    private var ongoingCard: some View {
        Button {
            selectedHistoricalMeal = CompletedMeal(
                menuImages: orderManager.ongoingMealImages,
                menuBlocks: orderManager.ongoingMealBlocks,
                orderedItems: orderManager.items
            )
            showHistoricalMeal = true
        } label: {
            PlatyCard {
                HStack(spacing: 14) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(PlatyTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(PlatyTheme.surfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Ongoing Meal")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(PlatyTheme.textPrimary)
                        Text("\(orderManager.ongoingMealBlocks.count) pages translated")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(PlatyTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(PlatyTheme.textTertiary)
                }
                .padding(18)
            }
        }
        .buttonStyle(PlatyPressStyle())
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PlatySectionLabel(title: "Recent Meals")
                Spacer()
                if !vm.meals.isEmpty {
                    Button("All") { showHistory = true }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PlatyTheme.accent)
                }
            }

            if vm.meals.isEmpty {
                Text("No saved meals yet.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(PlatyTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(PlatyTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(vm.meals.prefix(3))) { meal in
                        Button {
                            if let completedMeal = mealHistoryService.getCompletedMeal(by: meal.id) {
                                selectedHistoricalMeal = completedMeal
                                orderManager.loadHistoricalMeal(
                                    images: completedMeal.menuImages,
                                    blocks: completedMeal.menuBlocks,
                                    items: completedMeal.orderedItems
                                )
                                showHistoricalMeal = true
                            }
                        } label: {
                            LandingMealRow(meal: meal)
                        }
                        .buttonStyle(PlatyPressStyle())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(PlatyMotion.softSpring, value: vm.meals)
            }
        }
    }
}

private struct LandingMealRow: View {
    let meal: Meal

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "fork.knife")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(PlatyTheme.textSecondary)
                .frame(width: 54, height: 54)
                .background(PlatyTheme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(meal.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PlatyTheme.textPrimary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(PlatyTheme.textTertiary)
        }
        .padding(14)
        .background(PlatyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PlatyTheme.border, lineWidth: 1)
        )
    }
}
