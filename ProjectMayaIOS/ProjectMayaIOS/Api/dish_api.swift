import Foundation

// MARK: - Dish Detail Models
struct DishMedia: Codable {
    let imageURL: String
    let source: String
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
        case source, timestamp
    }
}

struct DishDetail: Codable {
    let name: String
    let description: String
    let ingredients: [String]?
    let tags: [String]?
    let media: [DishMedia]

    func replacingMedia(_ media: [DishMedia]) -> DishDetail {
        DishDetail(
            name: name,
            description: description,
            ingredients: ingredients,
            tags: tags,
            media: media
        )
    }
}

private struct DishDetailRequest: Codable {
    let dish: String
    let target: String
    let stream: Bool?

    init(dish: String, target: String, stream: Bool? = nil) {
        self.dish = dish
        self.target = target
        self.stream = stream
    }
}

private struct SupabaseDishDetailResponse: Codable {
    let title: String?
    let description: String?
    let thumbil: [String]?
    let source: [String]?
}

private struct DishDetailStreamPayload: Codable {
    let title: String?
    let delta: String?
    let description: String?
    let text: String?
    let message: String?
    let error: String?
}

private struct DishDetailSSEvent {
    let name: String
    let data: String
}

private struct DishImagesResponse: Codable {
    let results: [DishImageSearchResult]
}

private struct DishImageSearchResult: Codable {
    let title: String?
    let pageUrl: String?
    let fullUrl: String?
    let thumbUrl: String?
    let source: String?
}

// MARK: - Dish Service
final class DishService {
    private static let functionSlug = "dish_detail_api_gemini"
    private static let imageFunctionSlug = "get_dish_images"

    private let authService: AuthService
    private let session: URLSession

    init(authService: AuthService, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    /// Fetch dish images from the dedicated image-search function. This stays separate from text detail generation.
    func getDishImages(dishName: String, limit: Int = 6) async throws -> [DishMedia] {
        guard let authHeader = authService.getAuthHeader() else {
            throw TranslationError.authenticationRequired
        }

        var components = URLComponents(
            url: PlatyConfig.functionURL(Self.imageFunctionSlug),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: dishName),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "hl", value: "zh-cn"),
            URLQueryItem(name: "gl", value: "cn")
        ]

        guard let url = components?.url else {
            throw TranslationError.networkError("Invalid image search URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(PlatyConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.networkError("Invalid image search response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Image search request failed"
            throw TranslationError.serverError(body)
        }

        let decoded = try JSONDecoder().decode(DishImagesResponse.self, from: data)
        var seen = Set<String>()

        return decoded.results.compactMap { item in
            guard let imageURL = Self.cleanImageURL(item.thumbUrl ?? item.fullUrl),
                  !seen.contains(imageURL)
            else {
                return nil
            }

            seen.insert(imageURL)
            return DishMedia(
                imageURL: imageURL,
                source: Self.cleanImageURL(item.pageUrl) ?? item.source ?? "serpapi",
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        }
    }

    private static func cleanImageURL(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.range(of: #"^https?://"#, options: .regularExpression) != nil else {
            return nil
        }
        return clean
    }

    /// Fetch dish detail by name and language.
    func getDishDetail(dishName: String, language: String, completion: @escaping (Result<DishDetail, Error>) -> Void) {
        guard let authHeader = authService.getAuthHeader() else {
            completion(.failure(TranslationError.authenticationRequired))
            return
        }

        var request = URLRequest(url: PlatyConfig.functionURL(Self.functionSlug))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(PlatyConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONEncoder().encode(DishDetailRequest(dish: dishName, target: languageName(for: language)))
        } catch {
            completion(.failure(error))
            return
        }

        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(TranslationError.networkError(error.localizedDescription)))
                    return
                }

                guard let data else {
                    completion(.failure(TranslationError.networkError("No data received")))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    let body = String(data: data, encoding: .utf8) ?? "Dish detail request failed"
                    completion(.failure(TranslationError.serverError(body)))
                    return
                }

                do {
                    let response = try Self.decodeDishDetailResponse(from: data, urlResponse: response)
                    completion(.success(Self.mapDishDetail(dishName: dishName, response: response)))
                } catch {
                    completion(.failure(TranslationError.decodingError))
                }
            }
        }.resume()
    }

    /// Stream dish detail text as the cloud function generates it, then return the final detail payload.
    func streamDishDetail(
        dishName: String,
        language: String,
        onTitle: @escaping (String) async -> Void,
        onDelta: @escaping (String) async -> Void,
        onSnapshot: @escaping (String) async -> Void
    ) async throws -> DishDetail {
        guard let authHeader = authService.getAuthHeader() else {
            throw TranslationError.authenticationRequired
        }

        var request = URLRequest(url: PlatyConfig.functionURL(Self.functionSlug))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(PlatyConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            DishDetailRequest(
                dish: dishName,
                target: languageName(for: language),
                stream: true
            )
        )

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.networkError("Invalid server response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = try await Self.collectText(from: bytes)
            throw TranslationError.serverError(body.isEmpty ? "Dish detail request failed" : body)
        }

        let contentType = httpResponse
            .value(forHTTPHeaderField: "Content-Type")?
            .lowercased() ?? ""

        if !contentType.contains("text/event-stream") {
            let body = try await Self.collectText(from: bytes)
            return try Self.decodeNonStreamingDishDetail(
                body,
                dishName: dishName
            )
        }

        var finalResponse: SupabaseDishDetailResponse?
        var streamedTitle: String?
        var streamedDescription = ""

        func handleEvent(_ event: DishDetailSSEvent) async throws {
            guard event.data != "[DONE]",
                  let data = event.data.data(using: .utf8) else {
                return
            }

            switch event.name {
            case "dish_detail_title":
                let payload = try Self.decodeStreamPayload(DishDetailStreamPayload.self, from: data, event: event)
                if let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty {
                    streamedTitle = title
                    await onTitle(title)
                }
            case "dish_detail_delta":
                let payload = try Self.decodeStreamPayload(DishDetailStreamPayload.self, from: data, event: event)
                if let delta = payload.delta, !delta.isEmpty {
                    streamedDescription += delta
                    await onDelta(delta)
                }
            case "dish_detail_snapshot":
                let payload = try Self.decodeStreamPayload(DishDetailStreamPayload.self, from: data, event: event)
                if let description = payload.description ?? payload.text {
                    streamedDescription = description
                    await onSnapshot(description)
                }
            case "dish_detail_done":
                finalResponse = try Self.decodeStreamPayload(SupabaseDishDetailResponse.self, from: data, event: event)
            case "dish_detail_error":
                let payload = try Self.decodeStreamPayload(DishDetailStreamPayload.self, from: data, event: event)
                throw TranslationError.serverError(payload.message ?? payload.error ?? "Dish detail stream failed")
            default:
                if let payload = try? JSONDecoder().decode(DishDetailStreamPayload.self, from: data),
                   let delta = payload.delta, !delta.isEmpty {
                    streamedDescription += delta
                    await onDelta(delta)
                }
            }
        }

        try await Self.consumeServerSentEvents(from: bytes) { event in
            try await handleEvent(event)
        }

        if let finalResponse {
            return Self.mapDishDetail(dishName: dishName, response: finalResponse)
        }

        if !streamedDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DishDetail(
                name: streamedTitle ?? dishName,
                description: streamedDescription,
                ingredients: nil,
                tags: [],
                media: []
            )
        }

        throw TranslationError.decodingError
    }

    private static func mapDishDetail(dishName: String, response: SupabaseDishDetailResponse) -> DishDetail {
        let sources = response.source ?? []
        let images = response.thumbil ?? []
        let normalized = normalizeDishDetailResponse(dishName: dishName, response: response)
        let media = images.enumerated().map { index, imageURL in
            DishMedia(
                imageURL: imageURL,
                source: index < sources.count ? sources[index] : "web",
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        }

        return DishDetail(
            name: normalized.title,
            description: normalized.description,
            ingredients: nil,
            tags: [],
            media: media
        )
    }

    private static func normalizeDishDetailResponse(
        dishName: String,
        response: SupabaseDishDetailResponse
    ) -> (title: String, description: String) {
        var title = cleanString(response.title) ?? dishName
        var description = cleanDishDescription(response.description, fallbackTitle: title)
            ?? "No description is available yet."

        if let parsed = parseDishDetailText(description, fallbackTitle: title) {
            title = parsed.title
            if let parsedDescription = parsed.description {
                description = cleanDishDescription(parsedDescription, fallbackTitle: title)
                    ?? parsedDescription
            }
        }

        if let parsedTitle = extractJSONStringFieldPrefix(description, field: "title"),
           let cleanTitle = cleanString(parsedTitle) {
            title = cleanTitle
        }

        if let parsedDescription = extractJSONStringFieldPrefix(description, field: "description"),
           let cleanDescription = cleanDishDescription(parsedDescription, fallbackTitle: title) {
            description = cleanDescription
        }

        return (title, completeDishDescription(description))
    }

    private static func cleanDishDescription(
        _ value: String?,
        fallbackTitle: String,
        depth: Int = 0
    ) -> String? {
        guard depth < 4, let value = cleanString(value) else {
            return cleanString(value)
        }

        let cleaned = cleanupGeneratedText(value)
        let looksStructured = cleaned.hasPrefix("{") ||
            cleaned.contains(#""description""#) ||
            cleaned.contains(#"\"description\""#)

        guard looksStructured else {
            return cleaned
        }

        if let parsed = parseDishDetailText(cleaned, fallbackTitle: fallbackTitle),
           let description = parsed.description {
            return cleanDishDescription(description, fallbackTitle: parsed.title, depth: depth + 1)
        }

        if let description = extractJSONStringFieldPrefix(cleaned, field: "description") {
            return cleanDishDescription(description, fallbackTitle: fallbackTitle, depth: depth + 1)
        }

        let stripped = cleaned
            .replacingOccurrences(
                of: #"^\{\s*"title"\s*:\s*"[^"]*"\s*,\s*"description"\s*:\s*""#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #""\s*\}\s*$"#,
                with: "",
                options: .regularExpression
            )

        return cleanString(stripped)
    }

    private static func parseDishDetailText(
        _ text: String,
        fallbackTitle: String
    ) -> (title: String, description: String?)? {
        let cleaned = cleanupGeneratedText(text)

        if let data = cleaned.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let title = cleanString(object["title"] as? String) ?? fallbackTitle
            let description = cleanString(object["description"] as? String)
            return (title, description)
        }

        let title = cleanString(extractJSONStringFieldPrefix(cleaned, field: "title")) ?? fallbackTitle
        if let description = extractJSONStringFieldPrefix(cleaned, field: "description") {
            return (title, cleanString(description))
        }

        return nil
    }

    private static func extractJSONStringFieldPrefix(_ text: String, field: String) -> String? {
        let pattern = #""\#(NSRegularExpression.escapedPattern(for: field))"\s*:\s*""#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
            ),
            let matchRange = Range(match.range, in: text)
        else {
            return nil
        }

        var index = matchRange.upperBound
        var output = ""

        while index < text.endIndex {
            let character = text[index]

            if character == "\"" {
                return output
            }

            if character == "\\" {
                let nextIndex = text.index(after: index)
                guard nextIndex < text.endIndex else {
                    return output
                }

                let next = text[nextIndex]
                switch next {
                case "\"", "\\", "/":
                    output.append(next)
                    index = text.index(after: nextIndex)
                case "n":
                    output.append("\n")
                    index = text.index(after: nextIndex)
                case "r":
                    output.append("\r")
                    index = text.index(after: nextIndex)
                case "t":
                    output.append("\t")
                    index = text.index(after: nextIndex)
                default:
                    output.append(next)
                    index = text.index(after: nextIndex)
                }
                continue
            }

            output.append(character)
            index = text.index(after: index)
        }

        return output.isEmpty ? nil : output
    }

    private static func cleanString(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private static func completeDishDescription(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let last = trimmed.last,
            !"。.!！？?".contains(last)
        else {
            return trimmed
        }

        let clipped = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "，,、；;：: "))
        let containsCJK = clipped.range(of: #"\p{Han}"#, options: .regularExpression) != nil
        return clipped + (containsCJK ? "。" : ".")
    }

    private static func decodeNonStreamingDishDetail(_ body: String, dishName: String) throws -> DishDetail {
        guard let data = body.data(using: .utf8) else {
            throw TranslationError.decodingError
        }

        do {
            let response = try JSONDecoder().decode(SupabaseDishDetailResponse.self, from: data)
            return mapDishDetail(dishName: dishName, response: response)
        } catch {
            if let message = decodeServerMessage(from: data) {
                throw TranslationError.serverError(message)
            }

            let snippet = body
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(300)
            throw TranslationError.serverError("Unexpected dish detail response: \(snippet)")
        }
    }

    private static func decodeStreamPayload<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        event: DishDetailSSEvent
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let snippet = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(300) ?? "<non-UTF8 payload>"
            throw TranslationError.serverError("Invalid stream event \(event.name): \(snippet)")
        }
    }

    private static func decodeServerMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }

        if let error = object["error"] as? String, !error.isEmpty {
            return error
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        return nil
    }

    private static func consumeServerSentEvents(
        from bytes: URLSession.AsyncBytes,
        onEvent: (DishDetailSSEvent) async throws -> Void
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

    private static func decodeSSEEvent(from data: Data) -> DishDetailSSEvent? {
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

        return DishDetailSSEvent(
            name: eventName,
            data: dataLines.joined(separator: "\n")
        )
    }

    private static func collectText(from bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func languageName(for code: String) -> String {
        switch code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "en", "english":
            return "English"
        case "zh", "zh-hans", "cn", "chinese", "中文":
            return "中文"
        case "ja", "japanese", "日本語":
            return "Japanese"
        default:
            return code
        }
    }

    private static func decodeDishDetailResponse(
        from data: Data,
        urlResponse: URLResponse?
    ) throws -> SupabaseDishDetailResponse {
        let contentType = (urlResponse as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?
            .lowercased() ?? ""
        let text = String(data: data, encoding: .utf8) ?? ""

        if contentType.contains("text/event-stream") || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("data:") {
            return try decodeStreamingDishDetailResponse(from: text)
        }

        return try JSONDecoder().decode(SupabaseDishDetailResponse.self, from: data)
    }

    private static func decodeStreamingDishDetailResponse(from text: String) throws -> SupabaseDishDetailResponse {
        var directResponse: SupabaseDishDetailResponse?
        var generatedText = ""

        for payload in ssePayloads(from: text) {
            if payload == "[DONE]" { continue }
            guard let payloadData = payload.data(using: .utf8) else { continue }

            if let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                if let message = errorMessage(from: object) {
                    throw TranslationError.serverError(message)
                }

                if looksLikeDishDetailResponse(object),
                   let response = try? JSONDecoder().decode(SupabaseDishDetailResponse.self, from: payloadData) {
                    directResponse = response
                    continue
                }

                generatedText += extractGeneratedText(from: object)
            }
        }

        if let directResponse {
            return directResponse
        }

        let clean = cleanupGeneratedText(generatedText)
        guard !clean.isEmpty else {
            throw TranslationError.decodingError
        }

        return parseGeneratedDishDetailText(clean)
    }

    private static func ssePayloads(from text: String) -> [String] {
        var payloads: [String] = []
        var currentLines: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty {
                if !currentLines.isEmpty {
                    payloads.append(currentLines.joined(separator: "\n"))
                    currentLines.removeAll()
                }
                continue
            }

            if line.hasPrefix("data:") {
                currentLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
            }
        }

        if !currentLines.isEmpty {
            payloads.append(currentLines.joined(separator: "\n"))
        }

        return payloads
    }

    private static func looksLikeDishDetailResponse(_ object: [String: Any]) -> Bool {
        object["title"] != nil || object["description"] != nil || object["thumbil"] != nil || object["source"] != nil
    }

    private static func errorMessage(from object: [String: Any]) -> String? {
        if let error = object["error"] as? String {
            return error
        }

        if let message = object["message"] as? String {
            return message
        }

        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String
            let code = error["code"] as? String
            return [code, message]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ": ")
        }

        return nil
    }

    private static func extractGeneratedText(from object: [String: Any]) -> String {
        var output = ""

        if let candidates = object["candidates"] as? [[String: Any]] {
            for candidate in candidates {
                if let content = candidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]] {
                    for part in parts {
                        if part["thought"] as? Bool == true { continue }
                        if let text = part["text"] as? String {
                            output += text
                        }
                    }
                }
            }
        }

        if let choices = object["choices"] as? [[String: Any]] {
            for choice in choices {
                if let delta = choice["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    output += content
                }
                if let message = choice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    output += content
                }
            }
        }

        if let text = object["text"] as? String {
            output += text
        }

        return output
    }

    private static func parseGeneratedDishDetailText(_ text: String) -> SupabaseDishDetailResponse {
        let clean = cleanupGeneratedText(text)
        let jsonText = extractJSONObjectText(from: clean) ?? clean

        if let data = jsonText.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return SupabaseDishDetailResponse(
                title: stringValue(object["title"]),
                description: stringValue(object["description"]),
                thumbil: stringArrayValue(object["thumbil"]),
                source: stringArrayValue(object["source"])
            )
        }

        return SupabaseDishDetailResponse(
            title: nil,
            description: clean,
            thumbil: [],
            source: []
        )
    }

    private static func cleanupGeneratedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^```json\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^```\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONObjectText(from text: String) -> String? {
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}"),
            start <= end
        else {
            return nil
        }

        return String(text[start...end])
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private static func stringArrayValue(_ value: Any?) -> [String]? {
        guard let values = value as? [String] else { return nil }
        let clean = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return clean.isEmpty ? nil : clean
    }
}
