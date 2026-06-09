import Foundation
import UIKit
import Vision

// MARK: - OCR Result Models
struct OCRResult: Codable {
    let text: String
    let confidence: Float
    let boundingBox: OCRBoundingBox
    let angle: Double
}

struct OCRBoundingBox: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    
    var box2D: [CGFloat] { [y, x, y + height, x + width] }
}

struct OCRImageResult: Codable {
    let imageWidth: CGFloat
    let imageHeight: CGFloat
    let ocrResults: [OCRResult]
}

private struct OCRPassResult {
    let results: [OCRResult]
    let offset: CGPoint
}

// MARK: - Local OCR Service (iOS)
class LocalOCRService {
    static func performOCR(on image: UIImage, completion: @escaping (OCRImageResult?) -> Void) {
        // Use Vision directly for better control over bounding boxes and confidence
        visionOCR(image, completion: completion)
    }
    
    // Vision OCR implementation
    private static func visionOCR(_ image: UIImage, completion: @escaping (OCRImageResult?) -> Void) {
        let normalizedImage = ImageUtils.preparedForMenuAnalysis(image)
        guard let cg = normalizedImage.cgImage else { completion(nil); return }
        let imageSize = CGSize(width: cg.width, height: cg.height)

        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        let req = VNRecognizeTextRequest { r, error in
            if error != nil { completion(nil); return }
            let obs = r.results as? [VNRecognizedTextObservation] ?? []
            let baseResults = process(obs, imageSize: imageSize)

            if imageSize.width > imageSize.height * 1.18 {
                recognizeHorizontalTiles(in: cg, imageSize: imageSize, baseResults: baseResults) { merged in
                    completion(OCRImageResult(imageWidth: imageSize.width, imageHeight: imageSize.height, ocrResults: merged))
                }
            } else {
                completion(OCRImageResult(imageWidth: imageSize.width, imageHeight: imageSize.height, ocrResults: baseResults))
            }
        }
        req.recognitionLevel = VNRequestTextRecognitionLevel.accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        req.minimumTextHeight = 0
        DispatchQueue.global(qos: .userInitiated).async { try? handler.perform([req]) }
    }

    private static func recognizeHorizontalTiles(
        in cgImage: CGImage,
        imageSize: CGSize,
        baseResults: [OCRResult],
        completion: @escaping ([OCRResult]) -> Void
    ) {
        let tiles = horizontalTileRects(imageSize: imageSize)
        let group = DispatchGroup()
        var tilePasses = Array<OCRPassResult?>(repeating: nil, count: tiles.count)

        for (index, rect) in tiles.enumerated() {
            guard let cropped = cgImage.cropping(to: rect.integral) else { continue }

            group.enter()
            let handler = VNImageRequestHandler(cgImage: cropped, orientation: .up)
            let request = VNRecognizeTextRequest { r, _ in
                let obs = r.results as? [VNRecognizedTextObservation] ?? []
                let localResults = process(obs, imageSize: rect.size).map { result in
                    OCRResult(
                        text: result.text,
                        confidence: result.confidence,
                        boundingBox: OCRBoundingBox(
                            x: result.boundingBox.x + rect.minX,
                            y: result.boundingBox.y + rect.minY,
                            width: result.boundingBox.width,
                            height: result.boundingBox.height
                        ),
                        angle: result.angle
                    )
                }
                tilePasses[index] = OCRPassResult(results: localResults, offset: rect.origin)
                group.leave()
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.minimumTextHeight = 0
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    group.leave()
                }
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            let tileResults = tilePasses.flatMap { $0?.results ?? [] }
            let merged = mergeOCRResults(baseResults + tileResults, imageSize: imageSize)
            completion(merged)
        }
    }

    private static func horizontalTileRects(imageSize: CGSize) -> [CGRect] {
        let overlap = imageSize.width * 0.08
        let tileWidth = imageSize.width * 0.56
        let left = CGRect(x: 0, y: 0, width: min(imageSize.width, tileWidth), height: imageSize.height)
        let rightX = max(0, imageSize.width - tileWidth)
        let right = CGRect(x: rightX, y: 0, width: min(imageSize.width, tileWidth + overlap), height: imageSize.height)
        let centerWidth = imageSize.width * 0.64
        let center = CGRect(x: (imageSize.width - centerWidth) / 2, y: 0, width: centerWidth, height: imageSize.height)
        return [left, center, right]
    }

    private static func process(_ obs: [VNRecognizedTextObservation], imageSize: CGSize) -> [OCRResult] {
        obs.compactMap { ob in
            guard let candidate = ob.topCandidates(1).first else { return nil }
            let bb = Self.convert(box: ob.boundingBox, imageSize: imageSize)
            return OCRResult(text: candidate.string, confidence: candidate.confidence, boundingBox: bb, angle: 0)
        }.sorted { $0.boundingBox.y < $1.boundingBox.y }
    }

    private static func normalizeText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[\s]{2,}"#, with: " ", options: .regularExpression)
    }

    private static func mergeOCRResults(_ results: [OCRResult], imageSize: CGSize) -> [OCRResult] {
        var accepted: [OCRResult] = []

        for result in results.sorted(by: { score($0, imageSize: imageSize) > score($1, imageSize: imageSize) }) {
            let rect = CGRect(
                x: result.boundingBox.x,
                y: result.boundingBox.y,
                width: result.boundingBox.width,
                height: result.boundingBox.height
            )

            let duplicate = accepted.contains { existing in
                let existingRect = CGRect(
                    x: existing.boundingBox.x,
                    y: existing.boundingBox.y,
                    width: existing.boundingBox.width,
                    height: existing.boundingBox.height
                )
                return intersectionOverUnion(rect, existingRect) > 0.48
                    || (normalizeText(existing.text) == normalizeText(result.text) && rect.intersects(existingRect.insetBy(dx: -12, dy: -8)))
            }

            if !duplicate {
                accepted.append(result)
            }
        }

        return accepted.sorted { lhs, rhs in
            if abs(lhs.boundingBox.y - rhs.boundingBox.y) > imageSize.height * 0.018 {
                return lhs.boundingBox.y < rhs.boundingBox.y
            }
            return lhs.boundingBox.x < rhs.boundingBox.x
        }
    }

    private static func score(_ result: OCRResult, imageSize: CGSize) -> CGFloat {
        let area = (result.boundingBox.width * result.boundingBox.height) / max(1, imageSize.width * imageSize.height)
        return CGFloat(result.confidence) + min(0.28, area * 18)
    }

    private static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private static func convert(box: CGRect, imageSize: CGSize) -> OCRBoundingBox {
        let x = box.origin.x * imageSize.width
        let width = box.width * imageSize.width
        let y = (1 - box.origin.y - box.height) * imageSize.height
        let height = box.height * imageSize.height
        return OCRBoundingBox(x: x, y: y, width: width, height: height)
    }
}
