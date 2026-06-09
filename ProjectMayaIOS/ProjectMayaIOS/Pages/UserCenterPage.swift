import SwiftUI

struct UserCenterPage: View {
    @ObservedObject var authService: AuthService
    @State private var navigateToPreferences = false
    @State private var saveOriginalPhotos = true
    @State private var saveTranslatedMenus = true
    @AppStorage(SmartMenuTextFilter.isEnabledKey) private var smartMenuFilterEnabled = false
    @StateObject private var smartFilterDownload = SmartMenuFilterDownloadModel()
    @State private var smartFilterModelReady = false
    @State private var systemLanguage = UserLanguagePreferences.defaultSystemLanguage
    @State private var menuLanguage = UserLanguagePreferences.defaultMenuLanguage

    private var userLabel: String {
        if let email = authService.currentUser, !email.isEmpty {
            return email
        }
        if let userID = authService.currentUserID {
            return "User ID: \(String(userID.uuidString.prefix(8)))"
        }
        return "Signed In"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                profileCard
                    .platyEntrance()

                settingsSection(
                    title: "Personal Info",
                    rows: [
                        SettingsRow(title: "Region", value: "Select Country", icon: "globe.asia.australia"),
                        SettingsRow(title: "Dietary", value: "Edit Preferences", icon: "fork.knife"),
                        SettingsRow(title: "Allergens", value: "Manage", icon: "exclamationmark.shield")
                    ],
                    action: { navigateToPreferences = true }
                )
                .platyEntrance(delay: 0.07)

                settingsSection(
                    title: "Language",
                    rows: [
                        SettingsRow(title: "System Language", value: systemLanguage, icon: "character.bubble"),
                        SettingsRow(title: "Menu Language", value: menuLanguage, icon: "textformat")
                    ],
                    action: { navigateToPreferences = true }
                )
                .platyEntrance(delay: 0.14)

                saveSection
                    .platyEntrance(delay: 0.21)

                scanSection
                    .platyEntrance(delay: 0.28)

                Button(role: .destructive) {
                    authService.signOut()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(PlatyTheme.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(PlatyTheme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(PlatyTheme.border, lineWidth: 1))
                }
                .buttonStyle(PlatyPressStyle())
                .padding(.top, 6)
                .platyEntrance(delay: 0.35)
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 42)
        }
        .background(PlatyTheme.background.ignoresSafeArea())
        .navigationTitle("User Center")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $navigateToPreferences) {
            PreferencesPage(authService: authService)
        }
        .task {
            refreshCachedLanguagePreferences()
            await refreshSmartFilterReadiness()
            await refreshRemoteLanguagePreferences()
        }
        .onChange(of: navigateToPreferences) { _, isPresented in
            if !isPresented {
                refreshCachedLanguagePreferences()
                Task { await refreshRemoteLanguagePreferences() }
            }
        }
        .sheet(isPresented: smartFilterDownloadSheetBinding) {
            SmartFilterModelDownloadSheet(
                phase: smartFilterDownload.phase,
                progress: smartFilterDownload.progress,
                onCancel: {
                    smartFilterDownload.cancel()
                },
                onDownload: {
                smartFilterDownload.beginDownload(
                    isEnabled: $smartMenuFilterEnabled,
                    onReady: {
                        smartFilterModelReady = true
                    }
                )
                }
            )
            .presentationDetents([.height(356)])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
        }
    }

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
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(PlatyTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text("Platy Member")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
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

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlatySectionLabel(title: "Scanning")

            PlatyCard {
                VStack(spacing: 0) {
                    toggleRow(
                        title: "Smart Menu Filter",
                        subtitle: smartFilterSubtitle,
                        isOn: smartFilterBinding,
                        isDisabled: smartFilterDownload.isBusy
                    )
                }
            }
        }
    }

    private var smartFilterBinding: Binding<Bool> {
        Binding(
            get: { smartMenuFilterEnabled },
            set: { newValue in
                if newValue {
                    smartFilterDownload.requestEnable(
                        isEnabled: $smartMenuFilterEnabled,
                        modelReady: smartFilterModelReady
                    )
                } else {
                    withAnimation(PlatyMotion.spring) {
                        smartMenuFilterEnabled = false
                    }
                }
            }
        )
    }

    private var smartFilterDownloadSheetBinding: Binding<Bool> {
        Binding(
            get: { smartFilterDownload.isPresented },
            set: { isPresented in
                if !isPresented {
                    smartFilterDownload.cancel()
                }
            }
        )
    }

    private var smartFilterSubtitle: String {
        if !SmartMenuTextFilter.isAvailable {
            return "MLX package required"
        }
        switch smartFilterDownload.phase {
        case .downloading:
            return "Downloading \(Int(smartFilterDownload.progress * 100))%"
        case .preparing:
            return "Preparing local model"
        case .idle, .confirming, .ready, .failed:
            break
        }
        if smartFilterModelReady {
            return "MLX model downloaded"
        }
        return "Download local MLX model"
    }

    private func refreshSmartFilterReadiness() async {
        guard SmartMenuTextFilter.isAvailable else {
            smartFilterModelReady = false
            return
        }

        let isReady = await Task.detached(priority: .utility) {
            SmartMenuTextFilter.isModelReady
        }.value
        smartFilterModelReady = isReady
    }

    private func refreshCachedLanguagePreferences() {
        systemLanguage = UserLanguagePreferences.cachedSystemLanguage(userID: authService.currentUserID)
        menuLanguage = UserLanguagePreferences.cachedMenuLanguage(userID: authService.currentUserID)
    }

    @MainActor
    private func refreshRemoteLanguagePreferences() async {
        let resolvedSystemLanguage = await UserLanguagePreferences.resolveSystemLanguage(
            authToken: authService.getAuthToken(),
            userID: authService.currentUserID
        )
        let resolvedMenuLanguage = await UserLanguagePreferences.resolveMenuLanguage(
            authToken: authService.getAuthToken(),
            userID: authService.currentUserID
        )

        systemLanguage = resolvedSystemLanguage
        menuLanguage = resolvedMenuLanguage
    }

    private func settingsSection(title: String, rows: [SettingsRow], action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PlatySectionLabel(title: title)

            PlatyCard {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button(action: action) {
                            settingsRow(row)
                        }
                        .buttonStyle(PlatyPressStyle())

                        if index < rows.count - 1 {
                            Divider().overlay(PlatyTheme.divider)
                        }
                    }
                }
            }
        }
    }

    private func settingsRow(_ row: SettingsRow) -> some View {
        HStack(spacing: 14) {
            Image(systemName: row.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(PlatyTheme.accent)
                .frame(width: 28)

            Text(row.title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(PlatyTheme.textPrimary)

            Spacer()

            Text(row.value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(PlatyTheme.textSecondary)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(PlatyTheme.textTertiary)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .contentShape(Rectangle())
    }

    private func toggleRow(title: String, subtitle: String? = nil, isOn: Binding<Bool>, isDisabled: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(PlatyTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(PlatyTheme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer()
            Toggle("", isOn: isOn.animation(PlatyMotion.spring))
                .labelsHidden()
                .tint(PlatyTheme.accent)
                .disabled(isDisabled)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .opacity(isDisabled ? 0.72 : 1)
    }
}

private struct SettingsRow: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
}

private struct SmartFilterModelDownloadSheet: View {
    let phase: SmartMenuFilterDownloadModel.Phase
    let progress: Double
    let onCancel: () -> Void
    let onDownload: () -> Void

    @State private var isGlowing = false

    private var title: String {
        switch phase {
        case .failed:
            return "Download Failed"
        default:
            return "Smart Filter Model"
        }
    }

    private var subtitle: String {
        switch phase {
        case .downloading:
            return "Downloading Gemma 3 1B 4-bit"
        case .preparing:
            return "Preparing local model"
        case .failed(let message):
            return message
        default:
            return "Download the local MLX model for menu cleanup."
        }
    }

    private var progressText: String {
        "\(Int(min(max(progress, 0), 1) * 100))%"
    }

    var body: some View {
        ZStack {
            PlatyTheme.background.ignoresSafeArea()

            VStack(spacing: 22) {
                modelGlyph

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(PlatyTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(subtitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(phase.isFailure ? PlatyTheme.danger : PlatyTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if phase.isBusy {
                    progressBar
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text(phase.isFailure ? "Close" : "Cancel")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(PlatyTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(PlatyTheme.surfaceRaised)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(PlatyTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(PlatyPressStyle())

                    Button(action: onDownload) {
                        HStack(spacing: 8) {
                            if phase.isBusy {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.black)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }

                            Text(phase.isFailure ? "Retry" : "Download")
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(PlatyTheme.accent.opacity(phase.isBusy ? 0.58 : 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlatyPressStyle())
                    .disabled(phase.isBusy)
                }
            }
            .padding(24)
        }
        .onAppear {
            withAnimation(PlatyMotion.scan.repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
    }

    private var modelGlyph: some View {
        ZStack {
            Circle()
                .fill(PlatyTheme.accent.opacity(isGlowing ? 0.26 : 0.1))
                .frame(width: 86, height: 86)
                .blur(radius: isGlowing ? 10 : 3)

            Circle()
                .fill(PlatyTheme.surface)
                .frame(width: 74, height: 74)
                .overlay(Circle().stroke(PlatyTheme.border, lineWidth: 1))

            Image(systemName: phase.isFailure ? "exclamationmark.triangle.fill" : "sparkles")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(phase.isFailure ? PlatyTheme.danger : PlatyTheme.accent)
                .symbolEffect(.pulse, options: .repeating, value: phase.isBusy)
        }
    }

    private var progressBar: some View {
        VStack(spacing: 9) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PlatyTheme.surfaceRaised)

                    Capsule()
                        .fill(PlatyTheme.accent)
                        .frame(width: max(10, geometry.size.width * min(max(progress, 0), 1)))
                        .shadow(color: PlatyTheme.accent.opacity(0.32), radius: 10)
                        .animation(PlatyMotion.ease, value: progress)
                }
            }
            .frame(height: 11)

            Text(progressText)
                .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(PlatyTheme.textSecondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 2)
    }
}

private extension SmartMenuFilterDownloadModel.Phase {
    var isBusy: Bool {
        switch self {
        case .downloading, .preparing:
            return true
        case .idle, .confirming, .ready, .failed:
            return false
        }
    }

    var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}
