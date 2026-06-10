import Foundation

enum UserLanguagePreferences {
    static let defaultSystemLanguage = "中文"
    static let defaultMenuLanguage = "English"

    /// The app UI language now follows the iOS system language instead of an
    /// in-app setting. This maps the active localization to the value the
    /// backend (profiles table, combo agent) expects.
    static var appLanguage: String {
        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        return preferred.lowercased().hasPrefix("zh") ? "中文" : "English"
    }

    private enum StorageKey {
        static let systemLanguage = "systemLanguage"
        static let menuLanguage = "menuLanguage"
    }

    static func cachedSystemLanguage(userID: UUID?) -> String {
        cachedValue(for: StorageKey.systemLanguage, userID: userID) ?? defaultSystemLanguage
    }

    static func cachedMenuLanguage(userID: UUID?) -> String {
        cachedValue(for: StorageKey.menuLanguage, userID: userID) ?? defaultMenuLanguage
    }

    static func cache(systemLanguage: String, menuLanguage: String, userID: UUID?) {
        cacheValue(systemLanguage, for: StorageKey.systemLanguage, userID: userID)
        cacheValue(menuLanguage, for: StorageKey.menuLanguage, userID: userID)
    }

    static func cache(profile: SupabaseProfileRecord, userID: UUID?) {
        cache(
            systemLanguage: profile.systemLanguage ?? defaultSystemLanguage,
            menuLanguage: profile.menuLanguage ?? defaultMenuLanguage,
            userID: userID
        )
    }

    static func resolveSystemLanguage(authToken: String?, userID: UUID?) async -> String {
        if let cached = cachedValue(for: StorageKey.systemLanguage, userID: userID) {
            return cached
        }

        if let profile = await fetchProfile(authToken: authToken, userID: userID) {
            cache(profile: profile, userID: userID)
            return profile.systemLanguage ?? defaultSystemLanguage
        }

        return defaultSystemLanguage
    }

    static func resolveMenuLanguage(authToken: String?, userID: UUID?) async -> String {
        if let cached = cachedValue(for: StorageKey.menuLanguage, userID: userID) {
            return cached
        }

        if let profile = await fetchProfile(authToken: authToken, userID: userID) {
            cache(profile: profile, userID: userID)
            return profile.menuLanguage ?? defaultMenuLanguage
        }

        return defaultMenuLanguage
    }

    private static func fetchProfile(authToken: String?, userID: UUID?) async -> SupabaseProfileRecord? {
        guard let authToken, let userID else { return nil }

        do {
            return try await SupabaseClient().fetchProfile(authToken: authToken, userID: userID)
        } catch {
            print("⚠️ Failed to resolve language preferences: \(error.localizedDescription)")
            return nil
        }
    }

    private static func cachedValue(for key: String, userID: UUID?) -> String? {
        let defaults = UserDefaults.standard
        let scoped = defaults.string(forKey: storageKey(key, userID: userID))?.trimmedNonEmpty
        if let scoped { return scoped }
        return defaults.string(forKey: storageKey(key, userID: nil))?.trimmedNonEmpty
    }

    private static func cacheValue(_ value: String, for key: String, userID: UUID?) {
        guard let clean = value.trimmedNonEmpty else { return }
        UserDefaults.standard.set(clean, forKey: storageKey(key, userID: userID))
    }

    private static func storageKey(_ key: String, userID: UUID?) -> String {
        if let userID {
            return "platy.preferences.\(userID.uuidString).\(key)"
        }
        return "platy.preferences.\(key)"
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let clean = trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
