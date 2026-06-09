import Foundation

private struct SupabaseUser: Codable {
    let id: String?
    let email: String?
}

private struct SupabaseAuthResponse: Codable {
    let accessToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let expiresAt: Int?
    let refreshToken: String?
    let user: SupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case refreshToken = "refresh_token"
        case user
    }
}

private struct SupabaseAuthErrorResponse: Codable {
    let error: String?
    let errorDescription: String?
    let msg: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case msg
        case message
    }

    var displayMessage: String {
        errorDescription ?? message ?? msg ?? error ?? "Authentication request failed"
    }
}

private struct SupabaseVerifyRequest: Codable {
    let type: String
    let email: String
    let token: String
}

private struct SupabaseResendRequest: Codable {
    let type: String
    let email: String
}

final class AuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: String?
    @Published var currentUserID: UUID?
    @Published var isLoading = false

    private enum StorageKey {
        static let accessToken = "platy.supabase.accessToken"
        static let refreshToken = "platy.supabase.refreshToken"
        static let tokenExpiry = "platy.supabase.tokenExpiry"
        static let currentUser = "platy.supabase.currentUser"
    }

    private var authToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?

    init() {
        restoreSession()
    }

    func signIn(email: String, password: String, completion: @escaping (Result<String, Error>) -> Void) {
        let endpoint = PlatyConfig.authURL("token")
        let url = endpoint.appending(queryItems: [
            URLQueryItem(name: "grant_type", value: "password")
        ])
        let body = [
            "email": email,
            "password": password
        ]

        performAuthRequest(url: url, body: body) { [weak self] result in
            switch result {
            case .success(let response):
                guard let token = response.accessToken else {
                    completion(.failure(AuthError.decodingError))
                    return
                }

                self?.applySession(response, fallbackEmail: email)
                completion(.success(token))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func signUp(email: String, password: String, completion: @escaping (Result<String, Error>) -> Void) {
        let body = [
            "email": email,
            "password": password
        ]

        performAuthRequest(url: PlatyConfig.authURL("signup"), body: body) { [weak self] result in
            switch result {
            case .success(let response):
                if response.accessToken != nil {
                    self?.applySession(response, fallbackEmail: email)
                    completion(.success("Account created. You are signed in."))
                } else {
                    completion(.success("Account created. Check your email for verification."))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func confirmSignUp(email: String, code: String, completion: @escaping (Result<String, Error>) -> Void) {
        let body = SupabaseVerifyRequest(type: "signup", email: email, token: code)

        performAuthRequest(url: PlatyConfig.authURL("verify"), body: body) { [weak self] result in
            switch result {
            case .success(let response):
                if response.accessToken != nil {
                    self?.applySession(response, fallbackEmail: email)
                }
                completion(.success("Account verified successfully"))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func resendConfirmationCode(email: String, completion: @escaping (Result<String, Error>) -> Void) {
        let body = SupabaseResendRequest(type: "signup", email: email)

        performAuthRequest(url: PlatyConfig.authURL("resend"), body: body) { result in
            switch result {
            case .success:
                completion(.success("Verification code sent successfully"))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func signOut() {
        authToken = nil
        refreshToken = nil
        tokenExpiry = nil
        isAuthenticated = false
        currentUser = nil
        currentUserID = nil
        KeychainManager.shared.deletePassword(for: StorageKey.accessToken)
        KeychainManager.shared.deletePassword(for: StorageKey.refreshToken)
        UserDefaults.standard.removeObject(forKey: StorageKey.tokenExpiry)
        UserDefaults.standard.removeObject(forKey: StorageKey.currentUser)
    }

    func getAuthToken() -> String? {
        guard isTokenValid() else {
            return nil
        }
        return authToken
    }

    func isTokenValid() -> Bool {
        guard let authToken, !authToken.isEmpty, let tokenExpiry else {
            return false
        }
        return Date() < tokenExpiry
    }

    func getAuthHeader() -> String? {
        guard let token = getAuthToken() else {
            return nil
        }
        return "Bearer \(token)"
    }

    private func performAuthRequest<T: Encodable>(
        url: URL,
        body: T,
        completion: @escaping (Result<SupabaseAuthResponse, Error>) -> Void
    ) {
        guard PlatyConfig.isSupabaseConfigured else {
            completion(.failure(AuthError.notConfigured))
            return
        }

        isLoading = true

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(PlatyConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue(PlatyConfig.supabasePublishableKey, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            isLoading = false
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error {
                    completion(.failure(AuthError.serverError(error.localizedDescription)))
                    return
                }

                guard let data else {
                    completion(.failure(AuthError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    let message = Self.decodeErrorMessage(from: data)
                    completion(.failure(AuthError.serverError(message)))
                    return
                }

                do {
                    completion(.success(try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)))
                } catch {
                    completion(.failure(AuthError.decodingError))
                }
            }
        }.resume()
    }

    private static func decodeErrorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(SupabaseAuthErrorResponse.self, from: data) {
            return decoded.displayMessage
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }

        return "Authentication request failed"
    }

    private func applySession(_ response: SupabaseAuthResponse, fallbackEmail: String) {
        guard let accessToken = response.accessToken else { return }

        let expiry: Date
        if let expiresAt = response.expiresAt {
            expiry = Date(timeIntervalSince1970: TimeInterval(expiresAt))
        } else if let expiresIn = response.expiresIn {
            expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        } else {
            expiry = Date().addingTimeInterval(3600)
        }

        authToken = accessToken
        refreshToken = response.refreshToken
        tokenExpiry = expiry
        currentUser = response.user?.email ?? fallbackEmail
        currentUserID = response.user?.id.flatMap(UUID.init(uuidString:)) ?? decodeUserID(from: accessToken)
        isAuthenticated = true

        KeychainManager.shared.savePassword(accessToken, for: StorageKey.accessToken)
        if let refreshToken = response.refreshToken {
            KeychainManager.shared.savePassword(refreshToken, for: StorageKey.refreshToken)
        }
        UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: StorageKey.tokenExpiry)
        UserDefaults.standard.set(currentUser, forKey: StorageKey.currentUser)
    }

    private func restoreSession() {
        guard
            let storedToken = KeychainManager.shared.getPassword(for: StorageKey.accessToken),
            !storedToken.isEmpty
        else {
            return
        }

        let expiryTimestamp = UserDefaults.standard.double(forKey: StorageKey.tokenExpiry)
        let expiry = expiryTimestamp > 0
            ? Date(timeIntervalSince1970: expiryTimestamp)
            : Date.distantPast
        let storedRefreshToken = KeychainManager.shared.getPassword(for: StorageKey.refreshToken)

        guard Date() < expiry else {
            // Access token expired (common after a long background stay).
            // Keep the user signed in and renew with the refresh token
            // instead of dumping them to the sign-in screen.
            if let storedRefreshToken, !storedRefreshToken.isEmpty {
                refreshToken = storedRefreshToken
                currentUser = UserDefaults.standard.string(forKey: StorageKey.currentUser)
                currentUserID = decodeUserID(from: storedToken)
                isAuthenticated = true
                refreshSession()
            } else {
                signOut()
            }
            return
        }

        authToken = storedToken
        refreshToken = storedRefreshToken
        tokenExpiry = expiry
        currentUser = UserDefaults.standard.string(forKey: StorageKey.currentUser)
        currentUserID = decodeUserID(from: storedToken)
        isAuthenticated = true
    }

    /// Renew the session when the access token is expired (or about to be).
    /// `completion` fires on the main queue once a valid token is available,
    /// or with `false` when renewal failed.
    func refreshSessionIfNeeded(completion: ((Bool) -> Void)? = nil) {
        if isTokenValid() {
            completion?(true)
            return
        }
        refreshSession(completion: completion)
    }

    private func refreshSession(completion: ((Bool) -> Void)? = nil) {
        guard let refreshToken, !refreshToken.isEmpty else {
            signOut()
            completion?(false)
            return
        }

        let url = PlatyConfig.authURL("token").appending(queryItems: [
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ])
        let body = ["refresh_token": refreshToken]

        performAuthRequest(url: url, body: body) { [weak self] result in
            switch result {
            case .success(let response):
                if response.accessToken != nil {
                    self?.applySession(response, fallbackEmail: self?.currentUser ?? "")
                    print("🔐 Session refreshed")
                    completion?(true)
                } else {
                    self?.signOut()
                    completion?(false)
                }
            case .failure(let error):
                print("⚠️ Session refresh failed: \(error.localizedDescription)")
                self?.signOut()
                completion?(false)
            }
        }
    }

    private func decodeUserID(from token: String) -> UUID? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard
            let data = Data(base64Encoded: payload),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sub = json["sub"] as? String
        else {
            return nil
        }

        return UUID(uuidString: sub)
    }
}

enum AuthError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case serverError(String)
    case userNotConfirmed(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .decodingError:
            return "Failed to decode response"
        case .serverError(let message):
            return message
        case .userNotConfirmed:
            return "Account not verified. Please check your email for verification code."
        case .notConfigured:
            return "Supabase is not configured"
        }
    }
}
