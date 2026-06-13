import SwiftUI

struct PreferencesPage: View {
    @ObservedObject var authService: AuthService

    @State private var selectedAllergens: Set<String> = []
    @State private var selectedDiets: Set<String> = []
    @State private var country = ""
    @State private var menuLanguage = UserLanguagePreferences.defaultMenuLanguage
    @State private var isSaving = false
    @State private var message: String?

    private let client = SupabaseClient()
    private let allergens = ["Gluten", "Dairy", "Nuts", "Peanuts", "Soy", "Eggs", "Shellfish", "Fish"]
    private let diets = ["Vegetarian", "Vegan", "Halal", "Kosher", "Alcohol-Free"]
    private let menuLanguages = ["English", "中文", "日本語", "한국어", "Français", "Español", "Deutsch", "Italiano"]
    private let chipColumns = [GridItem(.adaptive(minimum: 116), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header
                    .platyEntrance()
                chipSection(title: "I am allergic to:", items: allergens, selection: $selectedAllergens)
                    .platyEntrance(delay: 0.06)
                chipSection(title: "I follow these diets:", items: diets, selection: $selectedDiets)
                    .platyEntrance(delay: 0.12)
                textSection
                    .platyEntrance(delay: 0.18)
                languageSection
                    .platyEntrance(delay: 0.24)
                saveButton
                    .platyEntrance(delay: 0.3)
            }
            .padding(.horizontal, 24)
            .padding(.top, 72)
            .padding(.bottom, 40)
        }
        .background(PlatyTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            menuLanguage = UserLanguagePreferences.cachedMenuLanguage(userID: authService.currentUserID)
        }
        .task {
            await loadProfile()
        }
        .alert("Preferences", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preferences")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(PlatyTheme.textPrimary)

            Text("Allergies, diets, and menu language")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(PlatyTheme.textSecondary)
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlatySectionLabel(title: "Cultural Background")

            TextField("", text: $country, prompt: Text("e.g. China, USA...").foregroundStyle(PlatyTheme.textTertiary))
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 18)
                .frame(height: 64)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(PlatyTheme.textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(PlatyTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(PlatyTheme.border, lineWidth: 1)
                        )
                )
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlatySectionLabel(title: "Language")

            PlatyCard {
                menuLanguageRow
            }

            Text("App language follows your iOS system setting.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(PlatyTheme.textTertiary)
        }
    }

    private var saveButton: some View {
        Button {
            Task { await saveProfile() }
        } label: {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.black)
                }
                Text(isSaving ? "Saving" : "Save Preferences")
                    .font(.system(size: 22, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(PlatyTheme.accent)
            .clipShape(Capsule())
        }
        .buttonStyle(PlatyPressStyle())
        .disabled(isSaving)
        .padding(.top, 24)
    }

    private func chipSection(title: LocalizedStringKey, items: [String], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PlatySectionLabel(title: title)

            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 12) {
                ForEach(items, id: \.self) { item in
                    ChipButton(
                        title: item,
                        isSelected: selection.wrappedValue.contains(item)
                    ) {
                        withAnimation(PlatyMotion.spring) {
                            if selection.wrappedValue.contains(item) {
                                selection.wrappedValue.remove(item)
                            } else {
                                selection.wrappedValue.insert(item)
                            }
                        }
                    }
                }
            }
        }
    }

    private var menuLanguageRow: some View {
        HStack(spacing: 16) {
            Text("Menu")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PlatyTheme.textPrimary)
            Spacer()
            Picker("Menu", selection: $menuLanguage) {
                ForEach(menuLanguages, id: \.self) { option in
                    // Language names are endonyms; they stay as-is in every locale.
                    Text(verbatim: option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(PlatyTheme.accent)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
    }

    @MainActor
    private func loadProfile() async {
        guard
            let token = authService.getAuthToken(),
            let userID = authService.currentUserID
        else {
            return
        }

        do {
            guard let profile = try await client.fetchProfile(authToken: token, userID: userID) else { return }
            selectedAllergens = Set(profile.allergies ?? [])
            selectedDiets = Set(profile.dietaryPreferences ?? [])
            country = profile.country ?? ""
            menuLanguage = profile.menuLanguage ?? menuLanguage
            UserLanguagePreferences.cache(
                systemLanguage: UserLanguagePreferences.appLanguage,
                menuLanguage: menuLanguage,
                userID: userID
            )
        } catch {
            print("⚠️ Failed to load profile: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func saveProfile() async {
        guard
            let token = authService.getAuthToken(),
            let userID = authService.currentUserID
        else {
            message = String(localized: "Please sign in before saving preferences.")
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await client.upsertProfile(
                authToken: token,
                userID: userID,
                allergies: Array(selectedAllergens).sorted(),
                dietaryPreferences: Array(selectedDiets).sorted(),
                country: country,
                systemLanguage: UserLanguagePreferences.appLanguage,
                menuLanguage: menuLanguage
            )
            UserLanguagePreferences.cache(
                systemLanguage: UserLanguagePreferences.appLanguage,
                menuLanguage: menuLanguage,
                userID: userID
            )
            message = String(localized: "Preferences saved.")
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Stored values stay English for the backend; display is localized.
            Text(LocalizedStringKey(title))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isSelected ? .black : PlatyTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(isSelected ? PlatyTheme.accent : PlatyTheme.surface)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? PlatyTheme.accent : PlatyTheme.border, lineWidth: 1.2)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(PlatyPressStyle())
    }
}

private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content

    init(items: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            generateContent(in: geometry)
        }
        .frame(minHeight: 96)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(Array(items), id: \.self) { item in
                content(item)
                    .alignmentGuide(.leading) { dimensions in
                        if abs(width - dimensions.width) > geometry.size.width {
                            width = 0
                            height -= dimensions.height + 12
                        }
                        let result = width
                        if let last = items.last, item == last {
                            width = 0
                        } else {
                            width -= dimensions.width + 12
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if let last = items.last, item == last {
                            height = 0
                        }
                        return result
                    }
            }
        }
    }
}
