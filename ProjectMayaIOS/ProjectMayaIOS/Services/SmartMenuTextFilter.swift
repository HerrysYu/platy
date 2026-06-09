import Foundation
import UIKit
import SwiftUI

struct SmartMenuTextCandidate: Codable, Identifiable {
    let id: Int
    let text: String
    let confidence: Float
    let box: NormalizedTextBox
}

struct NormalizedTextBox: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct SmartMenuTextFilterResult {
    let kept: [OCRResult]
    let dropped: [OCRResult]
    let uncertain: [OCRResult]

    var overlayResults: [OCRResult] {
        kept + uncertain
    }
}

protocol SmartMenuTextFiltering {
    func filter(_ results: [OCRResult], imageSize: CGSize) async -> SmartMenuTextFilterResult
}

enum SmartMenuTextFilter {
    static let isEnabledKey = "platy.smartMenuFilter.enabled"
    static let modelReadyKey = "platy.smartMenuFilter.modelReady"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    static var isAvailable: Bool {
        MLXSmartMenuTextFilter.isAvailable
    }

    static var isModelReady: Bool {
        MLXSmartMenuTextFilter.isModelReady
    }

    static func prepareModel(progressHandler: @Sendable @escaping (Progress) -> Void) async throws {
        try await MLXSmartMenuTextFilter.prepareModel(progressHandler: progressHandler)
    }

    static func downloadModel(progressHandler: @Sendable @escaping (Progress) -> Void) async throws {
        try await MLXSmartMenuTextFilter.downloadModel(progressHandler: progressHandler)
    }

    static func current() -> SmartMenuTextFiltering {
        if isEnabled && isModelReady {
            return MLXSmartMenuTextFilter()
        }
        return KeepAllMenuTextFilter()
    }
}

struct KeepAllMenuTextFilter: SmartMenuTextFiltering {
    func filter(_ results: [OCRResult], imageSize: CGSize) async -> SmartMenuTextFilterResult {
        SmartMenuTextFilterResult(kept: results, dropped: [], uncertain: [])
    }
}

@MainActor
final class SmartMenuFilterDownloadModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case confirming
        case downloading
        case preparing
        case ready
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var progress: Double = 0
    private var downloadTask: Task<Void, Never>?
    private var activeDownloadID: UUID?

    var isPresented: Bool {
        switch phase {
        case .confirming, .downloading, .preparing, .failed:
            return true
        case .idle, .ready:
            return false
        }
    }

    var isBusy: Bool {
        switch phase {
        case .downloading, .preparing:
            return true
        case .idle, .confirming, .ready, .failed:
            return false
        }
    }

    func requestEnable(isEnabled: Binding<Bool>, modelReady: Bool) {
        guard SmartMenuTextFilter.isAvailable else {
            phase = .failed("MLX package is not available in this build.")
            isEnabled.wrappedValue = false
            return
        }

        if modelReady {
            withAnimation(PlatyMotion.spring) {
                phase = .ready
                progress = 1
                isEnabled.wrappedValue = true
            }
        } else {
            withAnimation(PlatyMotion.spring) {
                progress = 0
                phase = .confirming
                isEnabled.wrappedValue = false
            }
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        activeDownloadID = nil

        withAnimation(PlatyMotion.spring) {
            progress = 0
            phase = .idle
        }
    }

    func beginDownload(isEnabled: Binding<Bool>, onReady: @escaping @MainActor () -> Void = {}) {
        guard !isBusy else { return }

        let downloadID = UUID()
        activeDownloadID = downloadID
        downloadTask?.cancel()
        withAnimation(PlatyMotion.spring) {
            progress = 0.02
            phase = .downloading
            isEnabled.wrappedValue = false
        }

        downloadTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await SmartMenuTextFilter.downloadModel { [weak self] progress in
                    let fraction = progress.totalUnitCount > 0
                        ? progress.fractionCompleted
                        : (progress.isFinished ? 1 : 0)

                    Task { @MainActor in
                        guard let self, self.activeDownloadID == downloadID else { return }
                        withAnimation(PlatyMotion.ease) {
                            self.progress = min(max(fraction, self.progress), 0.995)
                            if fraction >= 0.999 || progress.isFinished {
                                self.phase = .preparing
                            }
                        }
                    }
                }

                try Task.checkCancellation()
                guard activeDownloadID == downloadID else { return }

                withAnimation(PlatyMotion.spring) {
                    self.progress = 1
                    self.phase = .ready
                    onReady()
                    isEnabled.wrappedValue = true
                }

                try? await Task.sleep(nanoseconds: 420_000_000)
                guard activeDownloadID == downloadID else { return }
                downloadTask = nil
                activeDownloadID = nil
                withAnimation(PlatyMotion.spring) {
                    self.phase = .idle
                }
            } catch is CancellationError {
                guard activeDownloadID == downloadID else { return }
                downloadTask = nil
                activeDownloadID = nil
                withAnimation(PlatyMotion.spring) {
                    self.progress = 0
                    self.phase = .idle
                    isEnabled.wrappedValue = false
                }
            } catch {
                guard activeDownloadID == downloadID else { return }
                downloadTask = nil
                activeDownloadID = nil
                withAnimation(PlatyMotion.spring) {
                    self.progress = 0
                    self.phase = .failed(error.localizedDescription)
                    isEnabled.wrappedValue = false
                }
            }
        }
    }
}

struct SmartMenuFilterPayload: Codable {
    let imageWidth: Double
    let imageHeight: Double
    let candidates: [SmartMenuTextCandidate]
}

extension OCRImageResult {
    func applying(results filteredResults: [OCRResult]) -> OCRImageResult {
        OCRImageResult(imageWidth: imageWidth, imageHeight: imageHeight, ocrResults: filteredResults)
    }
}

extension OCRResult {
    func asSmartCandidate(id: Int, imageSize: CGSize) -> SmartMenuTextCandidate {
        SmartMenuTextCandidate(
            id: id,
            text: text,
            confidence: confidence,
            box: NormalizedTextBox(
                x: Double(boundingBox.x / max(1, imageSize.width)),
                y: Double(boundingBox.y / max(1, imageSize.height)),
                width: Double(boundingBox.width / max(1, imageSize.width)),
                height: Double(boundingBox.height / max(1, imageSize.height))
            )
        )
    }
}
