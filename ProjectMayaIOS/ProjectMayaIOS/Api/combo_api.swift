import Foundation

// MARK: - Combo Recommendation Models

struct ComboRecommendationItem: Codable, Identifiable, Equatable {
    let name: String
    let originalName: String
    let role: String
    let reason: String

    var id: String { originalName + "|" + name }

    enum CodingKeys: String, CodingKey {
        case name
        case originalName = "original_name"
        case role, reason
    }
}

struct ComboRecommendation: Codable, Equatable {
    let theme: String
    let summary: String
    let items: [ComboRecommendationItem]
    let tips: String?
}

struct ComboMenuItem: Codable {
    let name: String
    let translated: String?
}

struct ComboPreferences: Codable {
    let allergies: [String]
    let diets: [String]
    let country: String
    let preferenceNote: String
    let language: String

    enum CodingKeys: String, CodingKey {
        case allergies, diets, country
        case preferenceNote = "preference_note"
        case language
    }
}

private struct ComboRequest: Codable {
    let menuItems: [ComboMenuItem]
    let preferences: ComboPreferences
    let target: String
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case menuItems = "menu_items"
        case preferences, target, stream
    }
}

private struct ComboStatusPayload: Codable {
    let stage: String?
    let message: String?
}

private struct ComboErrorPayload: Codable {
    let message: String?
    let error: String?
}

// MARK: - Combo Service

/// Calls the `combo_recommend_api` edge function. The cloud side runs a Gemini
/// agent (menu reader + preference reader + web search tools) and streams
/// status events before the final combo JSON.
final class ComboService {
    private static let functionSlug = "combo_recommend_api"

    private let authService: AuthService
    private let session: URLSession

    init(authService: AuthService, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    /// Stream a combo recommendation. `onStatus` fires with localized progress
    /// text as the agent works (drives the thinking animation).
    func recommendCombo(
        menuItems: [ComboMenuItem],
        preferences: ComboPreferences,
        target: String,
        onStatus: @escaping (String) async -> Void
    ) async throws -> ComboRecommendation {
        guard let authHeader = authService.getAuthHeader() else {
            throw TranslationError.authenticationRequired
        }

        var request = URLRequest(url: PlatyConfig.functionURL(Self.functionSlug))
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(PlatyConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ComboRequest(
                menuItems: menuItems,
                preferences: preferences,
                target: target,
                stream: true
            )
        )

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.networkError("Invalid server response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = try await Self.collectText(from: bytes)
            throw TranslationError.serverError(body.isEmpty ? "Combo request failed" : body)
        }

        let contentType = httpResponse
            .value(forHTTPHeaderField: "Content-Type")?
            .lowercased() ?? ""

        if !contentType.contains("text/event-stream") {
            let body = try await Self.collectText(from: bytes)
            guard let data = body.data(using: .utf8) else {
                throw TranslationError.decodingError
            }
            return try JSONDecoder().decode(ComboRecommendation.self, from: data)
        }

        var result: ComboRecommendation?

        try await Self.consumeServerSentEvents(from: bytes) { event in
            guard event.data != "[DONE]",
                  let data = event.data.data(using: .utf8) else {
                return
            }

            switch event.name {
            case "combo_status":
                if let payload = try? JSONDecoder().decode(ComboStatusPayload.self, from: data),
                   let message = payload.message, !message.isEmpty {
                    await onStatus(message)
                }
            case "combo_done":
                result = try JSONDecoder().decode(ComboRecommendation.self, from: data)
            case "combo_error":
                let payload = try? JSONDecoder().decode(ComboErrorPayload.self, from: data)
                throw TranslationError.serverError(
                    payload?.message ?? payload?.error ?? "Combo recommendation failed"
                )
            default:
                break
            }
        }

        guard let result else {
            throw TranslationError.decodingError
        }

        return result
    }

    // MARK: - SSE plumbing

    private struct SSEvent {
        let name: String
        let data: String
    }

    private static func consumeServerSentEvents(
        from bytes: URLSession.AsyncBytes,
        onEvent: (SSEvent) async throws -> Void
    ) async throws {
        var buffer = Data()

        for try await byte in bytes {
            buffer.append(byte)

            while let boundary = firstSSEBoundary(in: buffer) {
                let eventData = buffer.subdata(in: buffer.startIndex..<boundary.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<boundary.upperBound)

                if let event = decodeSSEEvent(from: eventData) {
                    try await onEvent(event)
                }
            }
        }

        if !buffer.isEmpty, let event = decodeSSEEvent(from: buffer) {
            try await onEvent(event)
        }
    }

    private static func firstSSEBoundary(in data: Data) -> Range<Data.Index>? {
        let boundaries = [
            data.range(of: Data([0x0A, 0x0A])),
            data.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A]))
        ].compactMap { $0 }

        return boundaries.min { $0.lowerBound < $1.lowerBound }
    }

    private static func decodeSSEEvent(from data: Data) -> SSEvent? {
        let text = String(decoding: data, as: UTF8.self)
        var eventName = "message"
        var dataLines: [String] = []

        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine
            if line.last == "\r" {
                line.removeLast()
            }

            if line.isEmpty || line.hasPrefix(":") {
                continue
            }

            if line.hasPrefix("event:") {
                let name = String(line.dropFirst("event:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                eventName = name.isEmpty ? "message" : name
            } else if line.hasPrefix("data:") {
                dataLines.append(
                    String(line.dropFirst("data:".count))
                        .trimmingCharacters(in: .whitespaces)
                )
            }
        }

        guard !dataLines.isEmpty else {
            return nil
        }

        return SSEvent(name: eventName, data: dataLines.joined(separator: "\n"))
    }

    private static func collectText(from bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
