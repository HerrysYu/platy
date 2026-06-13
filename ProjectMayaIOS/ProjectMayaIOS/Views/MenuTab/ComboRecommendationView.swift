import SwiftUI

/// Sheet that runs the cloud combo agent and presents the result.
/// While the agent works it shows a rotating gradient ring with streamed
/// status text; on success it shows the combo card with add-to-order actions.
struct ComboRecommendationView: View {
    let menuItems: [ComboMenuItem]
    let authService: AuthService

    @EnvironmentObject private var orderManager: OrderManager
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case loading
        case loaded(ComboRecommendation)
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var statusMessage = ""
    @State private var addedAll = false
    @State private var runID = UUID()

    var body: some View {
        ZStack {
            PlatyTheme.background.ignoresSafeArea()

            switch phase {
            case .loading:
                ComboThinkingView(statusMessage: statusMessage)
            case .loaded(let combo):
                comboResult(combo)
            case .failed(let message):
                failureState(message)
            }
        }
        .task(id: runID) {
            await runAgent()
        }
    }

    // MARK: - Agent run

    @MainActor
    private func runAgent() async {
        phase = .loading
        addedAll = false
        statusMessage = ""

        guard !menuItems.isEmpty else {
            phase = .failed(String(localized: "No menu data to analyze yet."))
            return
        }

        let token = authService.getAuthToken()
        let userID = authService.currentUserID
        // The combo result language follows the app (iOS system) language.
        let language = UserLanguagePreferences.appLanguage

        var preferences = ComboPreferences(allergies: [], diets: [], country: "", language: language)
        if let token, let userID,
           let profile = try? await SupabaseClient().fetchProfile(authToken: token, userID: userID) {
            preferences = ComboPreferences(
                allergies: profile.allergies ?? [],
                diets: profile.dietaryPreferences ?? [],
                country: profile.country ?? "",
                language: language
            )
        }

        do {
            let combo = try await ComboService(authService: authService).recommendCombo(
                menuItems: menuItems,
                preferences: preferences,
                target: language
            ) { message in
                await MainActor.run {
                    withAnimation(PlatyMotion.ease) {
                        statusMessage = message
                    }
                }
            }

            withAnimation(PlatyMotion.softSpring) {
                phase = .loaded(combo)
            }
        } catch {
            withAnimation(PlatyMotion.ease) {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Result UI

    private func comboResult(_ combo: ComboRecommendation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(PlatyTheme.accentStrong)
                    Text("AI Combo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PlatyTheme.textSecondary)
                        .textCase(.uppercase)
                        .kerning(1.4)
                }
                .platyEntrance()

                Text(combo.theme)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(PlatyTheme.textPrimary)
                    .platyEntrance(delay: 0.05)

                if !combo.summary.isEmpty {
                    Text(combo.summary)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(PlatyTheme.textSecondary)
                        .lineSpacing(4)
                        .platyEntrance(delay: 0.1)
                }

                VStack(spacing: 14) {
                    ForEach(Array(combo.items.enumerated()), id: \.element.id) { index, item in
                        ComboItemCard(item: item)
                            .platyEntrance(delay: 0.16 + Double(index) * 0.07)
                    }
                }

                if let tips = combo.tips, !tips.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(PlatyTheme.accent)
                            .padding(.top, 2)
                        Text(tips)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PlatyTheme.textSecondary)
                            .lineSpacing(3)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PlatyTheme.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .platyEntrance(delay: 0.32)
                }

                actionButtons(combo)
                    .platyEntrance(delay: 0.38)
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 36)
        }
    }

    private func actionButtons(_ combo: ComboRecommendation) -> some View {
        VStack(spacing: 12) {
            Button {
                guard !addedAll else { return }
                for item in combo.items {
                    orderManager.add(
                        dish: DishDetail(
                            name: item.name,
                            description: item.reason,
                            ingredients: nil,
                            tags: [item.role],
                            media: []
                        ),
                        originalName: item.originalName
                    )
                }
                withAnimation(PlatyMotion.spring) {
                    addedAll = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    dismiss()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: addedAll ? "checkmark" : "plus")
                        .font(.system(size: 18, weight: .heavy))
                    Text(addedAll ? "Added!" : "Add Combo to Order")
                        .font(.system(size: 19, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(addedAll ? PlatyTheme.accentStrong : PlatyTheme.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(PlatyPressStyle())

            Button {
                runID = UUID()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .bold))
                    Text("Try Another Combo")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(PlatyTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(PlatyPressStyle())
        }
        .padding(.top, 8)
    }

    // MARK: - Failure UI

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(PlatyTheme.textTertiary)

            Text("Couldn't build a combo")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(PlatyTheme.textPrimary)

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PlatyTheme.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 32)

            Button {
                runID = UUID()
            } label: {
                Text("Retry")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 44)
                    .frame(height: 54)
                    .background(PlatyTheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(PlatyPressStyle())
            .padding(.top, 6)
        }
        .padding(28)
    }
}

// MARK: - Thinking animation

/// Quiet loading state: a single thin arc spinner over a static icon, with
/// the agent's streamed status line below.
private struct ComboThinkingView: View {
    let statusMessage: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 3)
                    .frame(width: 84, height: 84)

                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(PlatyTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 84, height: 84)
                    .rotationEffect(.degrees(spin ? 360 : 0))

                Image(systemName: "fork.knife")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(PlatyTheme.textSecondary)
            }

            VStack(spacing: 10) {
                Text(statusMessage.isEmpty ? String(localized: "Building a combo") : statusMessage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PlatyTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .id(statusMessage)
                    .transition(.opacity)

                Text("Based on this menu and your preferences")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PlatyTheme.textTertiary)
            }
            .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }
}

// MARK: - Item card

private struct ComboItemCard: View {
    let item: ComboRecommendationItem

    private var roleInfo: (icon: String, label: String) {
        switch item.role.lowercased() {
        case "main":
            return ("flame.fill", "Main")
        case "staple":
            return ("fork.knife", "Staple")
        case "side":
            return ("leaf.fill", "Side")
        case "drink":
            return ("cup.and.saucer.fill", "Drink")
        case "dessert":
            return ("birthday.cake.fill", "Dessert")
        default:
            return ("sparkle", item.role.capitalized)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: roleInfo.icon)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(PlatyTheme.accent)
                .frame(width: 46, height: 46)
                .background(PlatyTheme.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(PlatyTheme.textPrimary)
                        .lineLimit(2)

                    Text(LocalizedStringKey(roleInfo.label))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(PlatyTheme.accent)
                        .clipShape(Capsule())
                }

                if item.originalName != item.name {
                    Text(item.originalName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PlatyTheme.textTertiary)
                }

                if !item.reason.isEmpty {
                    Text(item.reason)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PlatyTheme.textSecondary)
                        .lineSpacing(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(PlatyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PlatyTheme.border, lineWidth: 1)
        )
    }
}

#Preview {
    ComboRecommendationView(
        menuItems: [
            ComboMenuItem(name: "剁椒鱼头", translated: "Chopped Chili Fish Head"),
            ComboMenuItem(name: "扬州炒饭", translated: "Yangzhou Fried Rice")
        ],
        authService: AuthService()
    )
    .environmentObject(OrderManager())
}
