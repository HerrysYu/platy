import Foundation
import UIKit

#if canImport(MLXLMCommon) && canImport(MLXLLM) && canImport(MLXHuggingFace) && canImport(HuggingFace) && canImport(Tokenizers)
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
#endif

struct MLXSmartMenuTextFilter: SmartMenuTextFiltering {
    static var isAvailable: Bool {
        #if canImport(MLXLMCommon) && canImport(MLXLLM) && canImport(MLXHuggingFace) && canImport(HuggingFace) && canImport(Tokenizers)
        true
        #else
        false
        #endif
    }

    static var isModelReady: Bool {
        #if canImport(MLXLMCommon) && canImport(MLXLLM) && canImport(MLXHuggingFace) && canImport(HuggingFace) && canImport(Tokenizers)
        MLXSmartMenuTextFilterRuntime.shared.isModelReady
        #else
        false
        #endif
    }

    static func prepareModel(progressHandler: @Sendable @escaping (Progress) -> Void) async throws {
        #if canImport(MLXLMCommon) && canImport(MLXLLM) && canImport(MLXHuggingFace) && canImport(HuggingFace) && canImport(Tokenizers)
        _ = try await MLXSmartMenuTextFilterRuntime.shared.prepareModel(progressHandler: progressHandler)
        #else
        throw SmartMenuTextFilterError.mlxUnavailable
        #endif
    }

    static func downloadModel(progressHandler: @Sendable @escaping (Progress) -> Void) async throws {
        #if canImport(MLXLMCommon) && canImport(MLXLLM) && canImport(MLXHuggingFace) && canImport(HuggingFace) && canImport(Tokenizers)
        try await MLXSmartMenuTextFilterRuntime.shared.downloadModel(progressHandler: progressHandler)
        #else
        throw SmartMenuTextFilterError.mlxUnavailable
        #endif
    }

    func filter(_ results: [OCRResult], imageSize: CGSize) async -> SmartMenuTextFilterResult {
        guard !results.isEmpty else {
            return SmartMenuTextFilterResult(kept: [], dropped: [], uncertain: [])
        }

        #if canImport(MLXLMCommon) && canImport(MLXLLM) && canImport(MLXHuggingFace) && canImport(HuggingFace) && canImport(Tokenizers)
        do {
            return try await MLXSmartMenuTextFilterRuntime.shared.filter(results, imageSize: imageSize)
        } catch {
            print("⚠️ MLX smart filter failed: \(error.localizedDescription)")
            return SmartMenuTextFilterResult(kept: results, dropped: [], uncertain: [])
        }
        #else
        return SmartMenuTextFilterResult(kept: results, dropped: [], uncertain: [])
        #endif
    }
}

#if canImport(MLXLMCommon) && canImport(MLXLLM) && canImport(MLXHuggingFace) && canImport(HuggingFace) && canImport(Tokenizers)
private actor MLXSmartMenuTextFilterRuntime {
    static let shared = MLXSmartMenuTextFilterRuntime()
    private static let modelRepoID = "mlx-community/gemma-3-1b-it-qat-4bit"
    private static let modelDownloadPatterns = ["*.safetensors", "*.json", "*.jinja", "*.model"]

    private var container: ModelContainer?
    private let configuration = LLMRegistry.gemma3_1B_qat_4bit
    private let generateParameters = GenerateParameters(maxTokens: 768, temperature: 0)
    private let batchSize = 48
    private let readyKey = SmartMenuTextFilter.modelReadyKey

    nonisolated var isModelReady: Bool {
        let isCached = Self.cachedModelLooksComplete()
        UserDefaults.standard.set(isCached, forKey: SmartMenuTextFilter.modelReadyKey)
        return isCached
    }

    func filter(_ results: [OCRResult], imageSize: CGSize) async throws -> SmartMenuTextFilterResult {
        let model = try await prepareModel()

        var kept: [OCRResult] = []
        var dropped: [OCRResult] = []
        var uncertain: [OCRResult] = []

        for chunkStart in stride(from: 0, to: results.count, by: batchSize) {
            let chunkEnd = min(chunkStart + batchSize, results.count)
            let chunk = Array(results[chunkStart..<chunkEnd])
            let session = ChatSession(
                model,
                instructions: Self.instructions,
                generateParameters: generateParameters
            )

            let prompt = try Self.prompt(for: chunk, imageSize: imageSize, idOffset: chunkStart)
            var response = ""
            for try await item in session.streamResponse(to: prompt) {
                response += item
            }

            let decision = try Self.parseDecision(from: response)
            let chunkResult = Self.apply(decision: decision, to: chunk, idOffset: chunkStart)
            kept.append(contentsOf: chunkResult.kept)
            dropped.append(contentsOf: chunkResult.dropped)
            uncertain.append(contentsOf: chunkResult.uncertain)
        }

        return SmartMenuTextFilterResult(kept: kept, dropped: dropped, uncertain: uncertain)
    }

    func downloadModel(progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }) async throws {
        if Self.cachedModelLooksComplete() {
            markModelReady()
            progressHandler(Self.completeProgress())
            return
        }

        guard let repoID = Repo.ID(rawValue: Self.modelRepoID) else {
            throw SmartMenuTextFilterError.invalidModelRepository
        }

        _ = try await HubClient().downloadSnapshot(
            of: repoID,
            revision: "main",
            matching: Self.modelDownloadPatterns,
            progressHandler: { @MainActor progress in
                progressHandler(progress)
            }
        )

        guard Self.cachedModelLooksComplete() else {
            throw SmartMenuTextFilterError.incompleteModelDownload
        }

        markModelReady()
        progressHandler(Self.completeProgress())
    }

    @discardableResult
    func prepareModel(progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }) async throws -> ModelContainer {
        if let container {
            markModelReady()
            progressHandler(Self.completeProgress())
            return container
        }

        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration,
            progressHandler: progressHandler
        )
        container = loaded
        markModelReady()
        return loaded
    }

    private func markModelReady() {
        UserDefaults.standard.set(true, forKey: readyKey)
    }

    private static func completeProgress() -> Progress {
        let progress = Progress(totalUnitCount: 1)
        progress.completedUnitCount = 1
        return progress
    }

    private static func cachedModelLooksComplete() -> Bool {
        guard let repoID = Repo.ID(rawValue: modelRepoID) else {
            return false
        }

        let snapshotsDirectory = HubCache.default.snapshotsDirectory(repo: repoID, kind: .model)
        guard let snapshotURLs = try? FileManager.default.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        return snapshotURLs.contains { snapshotURL in
            guard let fileURLs = try? FileManager.default.contentsOfDirectory(
                at: snapshotURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return false
            }

            let names = Set(fileURLs.map(\.lastPathComponent))
            let hasWeights = names.contains { $0.hasSuffix(".safetensors") }
            let hasConfig = names.contains("config.json")
            let hasTokenizer = names.contains("tokenizer.json")
                || names.contains("tokenizer_config.json")
                || names.contains("tokenizer.model")
            return hasWeights && hasConfig && hasTokenizer
        }
    }

    private static let instructions = """
    You filter OCR text candidates from restaurant menu images.
    Keep dish names, menu section headers, prices, and food descriptions.
    Drop phone status bar text, app UI text, browser/editor/app labels, random serial numbers, pure symbols, watermarks, and non-menu background text.
    If unsure, mark uncertain instead of dropping.
    Return only compact JSON with integer arrays: {"keep":[...],"drop":[...],"uncertain":[...]}.
    """

    private static func prompt(for results: [OCRResult], imageSize: CGSize, idOffset: Int) throws -> String {
        let candidates = results.enumerated().map { index, result in
            result.asSmartCandidate(id: idOffset + index, imageSize: imageSize)
        }
        let payload = SmartMenuFilterPayload(
            imageWidth: Double(imageSize.width),
            imageHeight: Double(imageSize.height),
            candidates: candidates
        )
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        return """
        Decide which OCR candidates belong to the restaurant menu.
        Use text and normalized box coordinates. Top phone UI/app chrome is usually non-menu, but do not drop real menu text just because it is short or low confidence.
        Preserve all valid candidate IDs. Put every input candidate ID into exactly one output array.
        JSON input:
        \(json)
        JSON output only:
        """
    }

    private static func parseDecision(from response: String) throws -> SmartMenuFilterDecision {
        let json = extractJSONObject(from: response)
        guard let data = json.data(using: .utf8) else {
            throw SmartMenuTextFilterError.invalidModelResponse
        }
        return try JSONDecoder().decode(SmartMenuFilterDecision.self, from: data)
    }

    private static func extractJSONObject(from response: String) -> String {
        guard
            let start = response.firstIndex(of: "{"),
            let end = response.lastIndex(of: "}"),
            start <= end
        else {
            return response
        }
        return String(response[start...end])
    }

    private static func apply(decision: SmartMenuFilterDecision, to results: [OCRResult], idOffset: Int) -> SmartMenuTextFilterResult {
        let keepIDs = Set(decision.keep)
        let dropIDs = Set(decision.drop)
        let uncertainIDs = Set(decision.uncertain)

        var kept: [OCRResult] = []
        var dropped: [OCRResult] = []
        var uncertain: [OCRResult] = []

        for (index, result) in results.enumerated() {
            let id = idOffset + index
            if keepIDs.contains(id) {
                kept.append(result)
            } else if uncertainIDs.contains(id) {
                uncertain.append(result)
            } else if dropIDs.contains(id) {
                dropped.append(result)
            } else {
                uncertain.append(result)
            }
        }

        return SmartMenuTextFilterResult(kept: kept, dropped: dropped, uncertain: uncertain)
    }
}

private struct SmartMenuFilterDecision: Codable {
    let keep: [Int]
    let drop: [Int]
    let uncertain: [Int]
}

#endif

private enum SmartMenuTextFilterError: LocalizedError {
    case mlxUnavailable
    case invalidModelResponse
    case invalidModelRepository
    case incompleteModelDownload

    var errorDescription: String? {
        switch self {
        case .mlxUnavailable:
            return "MLX is not available in this build."
        case .invalidModelResponse:
            return "The local MLX model did not return valid JSON."
        case .invalidModelRepository:
            return "The MLX model repository is invalid."
        case .incompleteModelDownload:
            return "The MLX model download did not finish correctly. Please try again."
        }
    }
}
