import SwiftUI

struct UserCenterPage: View {
    @ObservedObject var authService: AuthService
    @StateObject private var settings = UserSettingsViewModel()
    @State private var saveOriginalPhotos = true
    @State private var saveTranslatedMenus = true

    private let allergens = ["Gluten", "Dairy", "Nuts", "Peanuts", "Soy", "Eggs", "Shellfish", "Fish"]
    private let diets = ["Vegetarian", "Vegan", "Halal", "Kosher", "Alcohol-Free"]
    private let menuLanguages = ["English", "中文"]
    private let chipColumns = [GridItem(.adaptive(minimum: 112), spacing: 12)]

    private var userLabel: String {
        if let email = authService.currentUser, !email.isEmpty {
            return email
        }
        if let userID = authService.currentUserID {
            return String(localized: "User ID: \(String(userID.uuidString.prefix(8)))")
        }
        return String(localized: "Signed In")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                profileCard
                    .platyEntrance()

                preferenceNoteSection
                    .platyEntrance(delay: 0.05)

                chipSection(
                    title: "Allergens",
                    items: allergens,
                    selection: $settings.allergens
                )
                .platyEntrance(delay: 0.1)

                chipSection(
                    title: "Dietary",
                    items: diets,
                    selection: $settings.diets
                )
                .platyEntrance(delay: 0.15)

                languageSection
                    .platyEntrance(delay: 0.2)

                saveSection
                    .platyEntrance(delay: 0.25)

                Button(role: .destructive) {
                    authService.signOut()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PlatyTheme.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(PlatyTheme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(PlatyTheme.border, lineWidth: 1))
                }
                .buttonStyle(PlatyPressStyle())
                .padding(.top, 6)
                .platyEntrance(delay: 0.3)
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 42)
        }
        .background(PlatyTheme.background.ignoresSafeArea())
        .navigationTitle("User Center")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if settings.isSaving {
                    ProgressView().tint(PlatyTheme.accent)
                } else if settings.savedRecently {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Saved")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PlatyTheme.accent)
                    .transition(.opacity)
                }
            }
        }
        .task {
            await settings.load(authService: authService)
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { settings.errorMessage != nil },
            set: { if !$0 { settings.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(settings.errorMessage ?? "")
        }
    }

    // MARK: - Profile

    private var profileCard: some View {
        PlatyCard {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(PlatyTheme.surfaceRaised)
                        .frame(width: 76, height: 76)
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(PlatyTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text(userLabel)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(PlatyTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text("Platy Member")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(PlatyTheme.accent)
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)
            }
            .padding(22)
        }
    }

    // MARK: - Free-form preferences (inline)

    private var preferenceNoteSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlatySectionLabel(title: "Your Tastes")

            VStack(alignment: .leading, spacing: 8) {
                Text("Describe your tastes in your own words")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(PlatyTheme.textTertiary)

                TextField(
                    "",
                    text: $settings.preferenceNote,
                    prompt: Text("e.g. no cilantro, love spicy & sour, light on oil, allergic to crab…")
                        .foregroundStyle(PlatyTheme.textTertiary),
                    axis: .vertical
                )
                .lineLimit(3...6)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PlatyTheme.textPrimary)
                .padding(16)
                .background(PlatyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(PlatyTheme.border, lineWidth: 1)
                )
                .onChange(of: settings.preferenceNote) { _, _ in
                    settings.scheduleSave(authService: authService)
                }
            }
        }
    }

    // MARK: - Chips (inline allergens / diets)

    private func chipSection(title: LocalizedStringKey, items: [String], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PlatySectionLabel(title: title)

            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 12) {
                ForEach(items, id: \.self) { item in
                    let isSelected = selection.wrappedValue.contains(item)
                    Button {
                        withAnimation(PlatyMotion.spring) {
                            if isSelected {
                                selection.wrappedValue.remove(item)
                            } else {
                                selection.wrappedValue.insert(item)
                            }
                        }
                        settings.scheduleSave(authService: authService)
                    } label: {
                        Text(LocalizedStringKey(item))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSelected ? .black : PlatyTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(isSelected ? PlatyTheme.accent : PlatyTheme.surface)
                            .overlay(
                                Capsule().stroke(isSelected ? PlatyTheme.accent : PlatyTheme.border, lineWidth: 1.2)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlatyPressStyle())
                }
            }
        }
    }

    // MARK: - Language (inline pickers)

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlatySectionLabel(title: "Language")

            PlatyCard {
                pickerRow(title: "Menu Language", selection: $settings.menuLanguage, options: menuLanguages)
            }

            // The interface language follows the device; only the menu
            // translation target is configurable here.
            Text("App language follows your system settings.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(PlatyTheme.textTertiary)
                .padding(.horizontal, 4)
        }
    }

    private func pickerRow(title: LocalizedStringKey, selection: Binding<String>, options: [String]) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PlatyTheme.textPrimary)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 168)
            .onChange(of: selection.wrappedValue) { _, _ in
                settings.scheduleSave(authService: authService)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
    }

    // MARK: - Save options (local toggles)

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlatySectionLabel(title: "Save Options")

            PlatyCard {
                VStack(spacing: 0) {
                    toggleRow(title: "Save Original Photos", isOn: $saveOriginalPhotos)
                    Divider().overlay(PlatyTheme.divider)
                    toggleRow(title: "Save Translated Menus", isOn: $saveTranslatedMenus)
                }
            }
        }
    }

    private func toggleRow(title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(PlatyTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()
            Toggle("", isOn: isOn.animation(PlatyMotion.spring))
                .labelsHidden()
                .tint(PlatyTheme.accent)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
    }
}

/// Holds the editable profile so debounced auto-save always reads the latest
/// values (a struct View captured into a Task would see a stale snapshot).
@MainActor
final class UserSettingsViewModel: ObservableObject {
    @Published var allergens: Set<String> = []
    @Published var diets: Set<String> = []
    @Published var preferenceNote: String = ""
    @Published var systemLanguage = UserLanguagePreferences.defaultSystemLanguage
    @Published var menuLanguage = UserLanguagePreferences.defaultMenuLanguage
    @Published var isSaving = false
    @Published var savedRecently = false
    @Published var errorMessage: String?

    private let client = SupabaseClient()
    private var loaded = false
    private var saveTask: Task<Void, Never>?

    func load(authService: AuthService) async {
        // The UI language tracks the device, so store the active system
        // language rather than a user-picked one.
        systemLanguage = UserLanguagePreferences.appLanguage
        menuLanguage = UserLanguagePreferences.cachedMenuLanguage(userID: authService.currentUserID)

        guard
            let token = authService.getAuthToken(),
            let userID = authService.currentUserID
        else {
            loaded = true
            return
        }

        do {
            if let profile = try await client.fetchProfile(authToken: token, userID: userID) {
                allergens = Set(profile.allergies ?? [])
                diets = Set(profile.dietaryPreferences ?? [])
                preferenceNote = profile.preferenceNote ?? ""
                menuLanguage = profile.menuLanguage ?? menuLanguage
                UserLanguagePreferences.cache(
                    systemLanguage: systemLanguage,
                    menuLanguage: menuLanguage,
                    userID: userID
                )
            }
        } catch {
            print("⚠️ Failed to load profile: \(error.localizedDescription)")
        }

        loaded = true
    }

    /// Debounced save so rapid chip taps / picker flips coalesce into one write.
    func scheduleSave(authService: AuthService) {
        guard loaded else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await self?.save(authService: authService)
        }
    }

    private func save(authService: AuthService) async {
        guard
            let token = authService.getAuthToken(),
            let userID = authService.currentUserID
        else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await client.upsertProfile(
                authToken: token,
                userID: userID,
                allergies: Array(allergens).sorted(),
                dietaryPreferences: Array(diets).sorted(),
                country: "",
                preferenceNote: preferenceNote.trimmingCharacters(in: .whitespacesAndNewlines),
                systemLanguage: systemLanguage,
                menuLanguage: menuLanguage
            )
            UserLanguagePreferences.cache(
                systemLanguage: systemLanguage,
                menuLanguage: menuLanguage,
                userID: userID
            )
            withAnimation(PlatyMotion.spring) { savedRecently = true }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(PlatyMotion.ease) { savedRecently = false }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
