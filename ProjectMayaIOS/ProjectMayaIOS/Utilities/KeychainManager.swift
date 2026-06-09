import Foundation
import Security

/// Manages secure storage of sensitive data using iOS Keychain
class KeychainManager {
    
    // MARK: - Singleton
    static let shared = KeychainManager()
    private init() {}
    
    // MARK: - Constants
    private let service = Bundle.main.bundleIdentifier ?? "com.projectmaya.ios"
    
    // MARK: - Public Methods
    
    /// Save password to Keychain
    func savePassword(_ password: String, for account: String) -> Bool {
        let data = password.data(using: .utf8)!
        
        // Check if password already exists
        if getPassword(for: account) != nil {
            // Update existing password
            return updatePassword(password, for: account)
        } else {
            // Add new password
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data
            ]
            
            let status = SecItemAdd(query as CFDictionary, nil)
            return status == errSecSuccess
        }
    }
    
    /// Retrieve password from Keychain
    func getPassword(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            if let data = dataTypeRef as? Data,
               let password = String(data: data, encoding: .utf8) {
                return password
            }
        }
        
        return nil
    }
    
    /// Update existing password in Keychain
    private func updatePassword(_ password: String, for account: String) -> Bool {
        let data = password.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        return status == errSecSuccess
    }
    
    /// Delete password from Keychain
    func deletePassword(for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
    
    /// Clear all stored credentials
    func clearAllCredentials() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Extension for UserDefaults to handle email storage
extension UserDefaults {
    private enum Keys {
        static let savedEmail = "savedEmail"
        static let rememberCredentials = "rememberCredentials"
    }
    
    /// Save email to UserDefaults
    func setSavedEmail(_ email: String) {
        set(email, forKey: Keys.savedEmail)
    }
    
    /// Get saved email from UserDefaults
    func getSavedEmail() -> String? {
        return string(forKey: Keys.savedEmail)
    }
    
    /// Remove saved email from UserDefaults
    func removeSavedEmail() {
        removeObject(forKey: Keys.savedEmail)
    }
    
    /// Set remember credentials preference
    func setRememberCredentials(_ remember: Bool) {
        set(remember, forKey: Keys.rememberCredentials)
    }
    
    /// Get remember credentials preference
    func getRememberCredentials() -> Bool {
        return bool(forKey: Keys.rememberCredentials)
    }
}