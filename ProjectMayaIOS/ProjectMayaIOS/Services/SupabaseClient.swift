import Foundation
import UIKit

private struct SupabaseMealRecord: Codable {
    let id: UUID
    let userID: UUID?
    let createdAt: String?
    let restaurantName: String?
    let menuImages: [MenuImage]?
    let menuBlocks: [MenuBlocks]?
    let orderedItems: [OrderItem]?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case createdAt = "created_at"
        case restaurantName = "restaurant_name"
        case menuImages = "menu_images"
        case menuBlocks = "menu_blocks"
        case orderedItems = "ordered_items"
    }
}

private struct SupabaseMealInsert: Codable {
    let id: UUID
    let restaurantName: String
    let menuImages: [MenuImage]
    let menuBlocks: [MenuBlocks]
    let orderedItems: [OrderItem]

    enum CodingKeys: String, CodingKey {
        case id
        case restaurantName = "restaurant_name"
        case menuImages = "menu_images"
        case menuBlocks = "menu_blocks"
        case orderedItems = "ordered_items"
    }
}

struct SupabaseProfileRecord: Codable {
    let id: UUID
    let allergies: [String]?
    let dietaryPreferences: [String]?
    let country: String?
    let preferenceNote: String?
    let systemLanguage: String?
    let menuLanguage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case allergies
        case dietaryPreferences = "dietary_preferences"
        case country
        case preferenceNote = "preference_note"
        case systemLanguage = "system_language"
        case menuLanguage = "menu_language"
    }
}

final class SupabaseClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchMeals(authToken: String) async throws -> [CompletedMeal] {
        let url = try supabaseRESTURL(path: "meals", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ])

        let data = try await request(url: url, method: "GET", authToken: authToken)
        let records = try JSONDecoder.supabase.decode([SupabaseMealRecord].self, from: data)
        var meals: [CompletedMeal] = []

        for record in records {
            if let meal = try await recordToCompletedMeal(record) {
                meals.append(meal)
            }
        }

        return meals
    }

    func upsertMeal(_ meal: CompletedMeal, authToken: String) async throws {
        let insert = SupabaseMealInsert(
            id: meal.id,
            restaurantName: meal.restaurantName,
            menuImages: meal.menuImages,
            menuBlocks: meal.menuBlocks,
            orderedItems: meal.orderedItems
        )

        let url = try supabaseRESTURL(path: "meals", queryItems: [
            URLQueryItem(name: "on_conflict", value: "id")
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")

        let data = try JSONEncoder.supabase.encode(insert)
        request.httpBody = data
        addAuthHeaders(to: &request, authToken: authToken)

        _ = try await perform(request: request)
    }

    func deleteMeal(id: UUID, authToken: String) async throws {
        let url = try supabaseRESTURL(path: "meals", queryItems: [
            URLQueryItem(name: "id", value: "eq.\(id.uuidString)")
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addAuthHeaders(to: &request, authToken: authToken)
        _ = try await perform(request: request)
    }

    func fetchProfile(authToken: String, userID: UUID) async throws -> SupabaseProfileRecord? {
        let url = try supabaseRESTURL(path: "profiles", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "id", value: "eq.\(userID.uuidString)")
        ])

        let data = try await request(url: url, method: "GET", authToken: authToken)
        let records = try JSONDecoder.supabase.decode([SupabaseProfileRecord].self, from: data)
        return records.first
    }

    func upsertProfile(
        authToken: String,
        userID: UUID,
        allergies: [String],
        dietaryPreferences: [String],
        country: String,
        preferenceNote: String,
        systemLanguage: String,
        menuLanguage: String
    ) async throws {
        let record = SupabaseProfileRecord(
            id: userID,
            allergies: allergies.isEmpty ? nil : allergies,
            dietaryPreferences: dietaryPreferences.isEmpty ? nil : dietaryPreferences,
            country: country.isEmpty ? nil : country,
            preferenceNote: preferenceNote.isEmpty ? nil : preferenceNote,
            systemLanguage: systemLanguage.isEmpty ? nil : systemLanguage,
            menuLanguage: menuLanguage.isEmpty ? nil : menuLanguage
        )

        let url = try supabaseRESTURL(path: "profiles", queryItems: [
            URLQueryItem(name: "on_conflict", value: "id")
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")

        let data = try JSONEncoder.supabase.encode(record)
        request.httpBody = data
        addAuthHeaders(to: &request, authToken: authToken)

        _ = try await perform(request: request)
    }

    private func request(url: URL, method: String, authToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        addAuthHeaders(to: &request, authToken: authToken)
        return try await perform(request: request)
    }

    private func perform(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "Request failed"
            throw TranslationError.serverError(body)
        }

        return data
    }

    private func addAuthHeaders(to request: inout URLRequest, authToken: String) {
        request.setValue(PlatyConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    private func supabaseRESTURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents(url: PlatyConfig.supabaseURL.appendingPathComponent("rest/v1").appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw TranslationError.networkError("Invalid Supabase REST URL")
        }
        return url
    }

    private func recordToCompletedMeal(_ record: SupabaseMealRecord) async throws -> CompletedMeal? {
        guard
            let menuImages = record.menuImages,
            let menuBlocks = record.menuBlocks,
            let orderedItems = record.orderedItems
        else {
            return nil
        }

        let createdAt = record.createdAt.flatMap(Self.parseSupabaseDate)
        let hydratedImages = try await hydrateMenuImages(menuImages)

        return CompletedMeal(
            id: record.id,
            timestamp: createdAt ?? Date(),
            restaurantName: record.restaurantName ?? createdAt.map(Self.displayName(for:)) ?? "Meal",
            menuImages: hydratedImages,
            menuBlocks: menuBlocks,
            orderedItems: orderedItems
        )
    }

    private func hydrateMenuImages(_ menuImages: [MenuImage]) async throws -> [MenuImage] {
        var hydrated: [MenuImage] = []

        for menuImage in menuImages {
            guard let storagePath = menuImage.storagePath else {
                hydrated.append(menuImage)
                continue
            }

            do {
                let url = storageImageURL(path: storagePath)
                let (data, response) = try await session.data(from: url)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    hydrated.append(menuImage)
                    continue
                }

                if let image = UIImage(data: data) {
                    hydrated.append(menuImage.replacingImage(image))
                } else {
                    hydrated.append(menuImage)
                }
            } catch {
                hydrated.append(menuImage)
            }
        }

        return hydrated
    }

    private func storageImageURL(path: String) -> URL {
        PlatyConfig.supabaseURL
            .appendingPathComponent("storage/v1/object/public/meal_images")
            .appendingPathComponent(path)
    }
}

private extension CompletedMeal {
    init(
        id: UUID,
        timestamp: Date,
        restaurantName: String,
        menuImages: [MenuImage],
        menuBlocks: [MenuBlocks],
        orderedItems: [OrderItem]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.restaurantName = restaurantName
        self.menuImages = menuImages
        self.menuBlocks = menuBlocks
        self.orderedItems = orderedItems
    }
}

private extension SupabaseClient {
    static func parseSupabaseDate(_ value: String) -> Date? {
        let isoWithFractionalSeconds = ISO8601DateFormatter()
        isoWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        if let date = isoWithFractionalSeconds.date(from: value) ?? iso.date(from: value) {
            return date
        }

        let postgresFormatter = DateFormatter()
        postgresFormatter.locale = Locale(identifier: "en_US_POSIX")
        postgresFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        postgresFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXXXX"

        return postgresFormatter.date(from: value)
    }

    static func displayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
