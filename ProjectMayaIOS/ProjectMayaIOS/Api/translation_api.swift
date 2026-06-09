//
//  translation_api.swift
//  ProjectMayaIOS
//
//  Supabase-backed translation bridge.
//

import Foundation
import UIKit

// MARK: - Translation Response Models
struct TranslationResponse: Codable {
    let imageId: String
    let originalImageWidth: Int
    let originalImageHeight: Int
    let boxes: [TextBox]
    let targetLanguage: String
    let processingTime: Double

    enum CodingKeys: String, CodingKey {
        case imageId = "image_id"
        case originalImageWidth = "original_image_width"
        case originalImageHeight = "original_image_height"
        case boxes
        case targetLanguage = "target_language"
        case processingTime = "processing_time"
    }
}

struct TextBox: Codable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let rotation: Int
    let originalText: String
    let translatedText: String
    let language: String

    enum CodingKeys: String, CodingKey {
        case x, y, width, height, rotation
        case originalText = "original_text"
        case translatedText = "translated_text"
        case language
    }
}

// MARK: - Translation Error
enum TranslationError: Error, LocalizedError {
    case authenticationRequired
    case invalidImage
    case networkError(String)
    case decodingError
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Authentication required"
        case .invalidImage:
            return "Invalid image data"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError:
            return "Failed to decode response"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

// MARK: - Array chunk helper
extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }

        var chunks: [[Element]] = []
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index += size
        }
        return chunks
    }
}

// MARK: - OCR Processing Request/Response Models
struct OCRProcessingRequest: Codable {
    let imageWidth: CGFloat
    let imageHeight: CGFloat
    let ocrResults: [OCRResult]
}

struct OCRProcessingResponse: Codable {
    let imageId: String
    let originalImageWidth: Int
    let originalImageHeight: Int
    let boxes: [TranslatedTextBox]
    let targetLanguage: String
    let processingTime: Double

    enum CodingKeys: String, CodingKey {
        case imageId = "image_id"
        case originalImageWidth = "original_image_width"
        case originalImageHeight = "original_image_height"
        case boxes
        case targetLanguage = "target_language"
        case processingTime = "processing_time"
    }
}

struct TranslatedTextBox: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let rotation: Double
    let originalText: String
    let translatedText: String
    let language: String

    enum CodingKeys: String, CodingKey {
        case x, y, width, height, rotation
        case originalText = "original_text"
        case translatedText = "translated_text"
        case language
    }
}

private struct SupabaseTranslationRequest: Codable {
    let words: [String]
    let targetLang: String
}

private struct SupabaseTranslationResponse: Codable {
    let count: Int?
    let original: [String]?
    let translations: [SupabaseTranslatedWord]
}

private struct SupabaseTranslatedWord: Codable {
    let detectedSourceLang: String?
    let text: String
}

private struct SupabaseFunctionError: Codable {
    let error: String?
    let message: String?
    let detail: String?

    var displayMessage: String {
        [error, message, detail]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ": ")
    }
}

// MARK: - Translation Service
final class TranslationService: ObservableObject {
    private let authService: AuthService
    private let session: URLSession

    init(authService: AuthService, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    // MARK: - Single Image Translation
    func translateImage(image: UIImage, targetLanguage: String, completion: @escaping (Result<TranslationResponse, Error>) -> Void) {
        LocalOCRService.performOCR(on: image) { [weak self] ocrImageResult in
            guard let self else { return }

            guard let ocrImageResult else {
                completion(.failure(TranslationError.invalidImage))
                return
            }

            self.processOCRResults(ocrImageResult: ocrImageResult, targetLanguage: targetLanguage) { result in
                switch result {
                case .success(let response):
                    let boxes = response.boxes.map {
                        TextBox(
                            x: Int($0.x),
                            y: Int($0.y),
                            width: Int($0.width),
                            height: Int($0.height),
                            rotation: Int($0.rotation),
                            originalText: $0.originalText,
                            translatedText: $0.translatedText,
                            language: $0.language
                        )
                    }
                    completion(.success(TranslationResponse(
                        imageId: response.imageId,
                        originalImageWidth: response.originalImageWidth,
                        originalImageHeight: response.originalImageHeight,
                        boxes: boxes,
                        targetLanguage: response.targetLanguage,
                        processingTime: response.processingTime
                    )))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Multiple Images Translation
    func translateImages(images: [UIImage], targetLanguage: String, completion: @escaping (Result<[TranslationResponse], Error>) -> Void) {
        let group = DispatchGroup()
        var results = Array<TranslationResponse?>(repeating: nil, count: images.count)
        var firstError: Error?

        for (index, image) in images.enumerated() {
            group.enter()
            translateImage(image: image, targetLanguage: targetLanguage) { result in
                switch result {
                case .success(let response):
                    results[index] = response
                case .failure(let error):
                    if firstError == nil {
                        firstError = error
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(results.compactMap { $0 }))
            }
        }
    }

    // MARK: - OCR Results Processing
    func processOCRResults(
        ocrImageResult: OCRImageResult,
        targetLanguage: String,
        batchSize: Int = 50,
        completion: @escaping (Result<OCRProcessingResponse, Error>) -> Void
    ) {
        let startedAt = Date()
        let batches = ocrImageResult.ocrResults.chunked(size: batchSize)

        guard !batches.isEmpty else {
            completion(.success(OCRProcessingResponse(
                imageId: UUID().uuidString,
                originalImageWidth: Int(ocrImageResult.imageWidth),
                originalImageHeight: Int(ocrImageResult.imageHeight),
                boxes: [],
                targetLanguage: targetLanguage,
                processingTime: 0
            )))
            return
        }

        let group = DispatchGroup()
        var translatedBatches = Array<[TranslatedTextBox]?>(repeating: nil, count: batches.count)
        var firstError: Error?

        for (batchIndex, batch) in batches.enumerated() {
            group.enter()
            translateOCRBatch(batch, targetLanguage: targetLanguage) { result in
                switch result {
                case .success(let boxes):
                    translatedBatches[batchIndex] = boxes
                case .failure(let error):
                    if firstError == nil {
                        firstError = error
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
                return
            }

            completion(.success(OCRProcessingResponse(
                imageId: UUID().uuidString,
                originalImageWidth: Int(ocrImageResult.imageWidth),
                originalImageHeight: Int(ocrImageResult.imageHeight),
                boxes: translatedBatches.flatMap { $0 ?? [] },
                targetLanguage: targetLanguage,
                processingTime: Date().timeIntervalSince(startedAt)
            )))
        }
    }

    private func translateOCRBatch(
        _ ocrResults: [OCRResult],
        targetLanguage: String,
        completion: @escaping (Result<[TranslatedTextBox], Error>) -> Void
    ) {
        let words = ocrResults.map(\.text)

        invokeTranslationFunction(words: words, targetLanguage: deeplCode(for: targetLanguage)) { result in
            switch result {
            case .success(let response):
                let boxes = ocrResults.enumerated().map { index, result in
                    let translated = index < response.translations.count
                        ? response.translations[index]
                        : SupabaseTranslatedWord(detectedSourceLang: nil, text: result.text)

                    return TranslatedTextBox(
                        x: Double(result.boundingBox.x),
                        y: Double(result.boundingBox.y),
                        width: Double(result.boundingBox.width),
                        height: Double(result.boundingBox.height),
                        rotation: result.angle,
                        originalText: result.text,
                        translatedText: translated.text,
                        language: translated.detectedSourceLang ?? "auto"
                    )
                }
                completion(.success(boxes))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func invokeTranslationFunction(
        words: [String],
        targetLanguage: String,
        completion: @escaping (Result<SupabaseTranslationResponse, Error>) -> Void
    ) {
        guard let authHeader = authService.getAuthHeader() else {
            completion(.failure(TranslationError.authenticationRequired))
            return
        }

        var request = URLRequest(url: PlatyConfig.functionURL("translation_service"))
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(PlatyConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONEncoder().encode(SupabaseTranslationRequest(words: words, targetLang: targetLanguage))
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
                    completion(.failure(TranslationError.serverError(Self.decodeFunctionError(from: data))))
                    return
                }

                do {
                    completion(.success(try JSONDecoder().decode(SupabaseTranslationResponse.self, from: data)))
                } catch {
                    completion(.failure(TranslationError.decodingError))
                }
            }
        }.resume()
    }

    private static func decodeFunctionError(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(SupabaseFunctionError.self, from: data) {
            let message = decoded.displayMessage
            if !message.isEmpty {
                return message
            }
        }

        return String(data: data, encoding: .utf8) ?? "Function request failed"
    }

    private func deeplCode(for language: String) -> String {
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "english", "en":
            return "EN"
        case "chinese", "中文", "zh", "zh-hans", "simplified chinese":
            return "ZH"
        case "japanese", "日本語", "ja":
            return "JA"
        case "korean", "한국어", "ko":
            return "KO"
        case "french", "français", "fr":
            return "FR"
        case "spanish", "español", "es":
            return "ES"
        case "german", "deutsch", "de":
            return "DE"
        default:
            return language.uppercased()
        }
    }
}
