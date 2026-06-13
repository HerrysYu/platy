import Foundation

/// Per-dish advisory: does this dish fit the user's allergies, dietary
/// restrictions, and free-form taste notes?
struct DishAdvice: Codable, Equatable {
    enum Verdict: String, Codable {
        case ok
        case caution
        case avoid
    }

    let verdict: Verdict
    let summary: String
    let notes: [String]

    /// True when there is something worth surfacing to the user.
    var hasConcerns: Bool {
        verdict != .ok || !notes.isEmpty
    }

    init(verdict: Verdict, summary: String, notes: [String]) {
        self.verdict = verdict
        self.summary = summary
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? container.decode(String.self, forKey: .verdict)) ?? "ok"
        verdict = Verdict(rawValue: raw) ?? .ok
        summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
        notes = (try? container.decode([String].self, forKey: .notes)) ?? []
    }
}

private struct DishAdviceRequest: Codable {
    let dish: String
    let description: String
    let allergies: [String]
    let diets: [String]
    let preferenceNote: String
    let target: String

    enum CodingKeys: String, CodingKey {
        case dish, description, allergies, diets
        case preferenceNote = "preference_note"
        case target
    }
}

final class DishAdviceService {
    private static let functionSlug = "dish_advice_api"

    private let authService: AuthService
    private let session: URLSession

    init(authService: AuthService, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    /// Returns advice, or `nil` when the user has no preferences to check
    /// against (so callers can simply show nothing).
    func advice(
        dish: String,
        description: String,
        allergies: [String],
        diets: [String],
        preferenceNote: String,
        target: String
    ) async throws -> DishAdvice? {
        guard !allergies.isEmpty || !diets.isEmpty || !preferenceNote.isEmpty else {
            return nil
        }

        guard let authHeader = authService.getAuthHeader() else {
            throw TranslationError.authenticationRequired
        }

        var request = URLRequest(url: PlatyConfig.functionURL(Self.functionSlug))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PlatyConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            DishAdviceRequest(
                dish: dish,
                description: description,
                allergies: allergies,
                diets: diets,
                preferenceNote: preferenceNote,
                target: target
            )
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Dish advice request failed"
            throw TranslationError.serverError(body)
        }

        return try JSONDecoder().decode(DishAdvice.self, from: data)
    }
}
