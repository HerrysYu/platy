import SwiftUI
import UIKit

struct MenuImage: Codable {
    let image: UIImage
    let height: Double
    let width: Double
    let storagePath: String?
    
    init(image: UIImage, height: Double, width: Double, storagePath: String? = nil) {
        self.image = image
        self.height = height
        self.width = width
        self.storagePath = storagePath
    }
    
    func isValid() -> Bool {
        return true
    }
    
    // MARK: - Codable Implementation
    enum CodingKeys: String, CodingKey {
        case imageData, height, width, storagePath
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.storagePath = try container.decodeIfPresent(String.self, forKey: .storagePath)
        self.height = try container.decode(Double.self, forKey: .height)
        self.width = try container.decode(Double.self, forKey: .width)

        if let imageData = try container.decodeIfPresent(Data.self, forKey: .imageData),
           let image = UIImage(data: imageData) {
            self.image = image
        } else {
            self.image = Self.placeholder(width: width, height: height)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // JPEG keeps photo payloads ~10x smaller than PNG, which matters for
        // local persistence and the meals table. Decoding is format-agnostic.
        guard let imageData = image.jpegData(compressionQuality: 0.72) ?? image.pngData() else {
            throw EncodingError.invalidValue(
                image,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unable to encode UIImage data")
            )
        }
        
        try container.encode(imageData, forKey: .imageData)
        try container.encode(height, forKey: .height)
        try container.encode(width, forKey: .width)
        try container.encodeIfPresent(storagePath, forKey: .storagePath)
    }

    func replacingImage(_ newImage: UIImage) -> MenuImage {
        MenuImage(image: newImage, height: height, width: width, storagePath: storagePath)
    }

    private static func placeholder(width: Double, height: Double) -> UIImage {
        let safeWidth = max(1, min(width, 1200))
        let safeHeight = max(1, min(height, 1200))
        let size = CGSize(width: safeWidth, height: safeHeight)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemGray6.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let symbol = UIImage(systemName: "photo")
            let symbolSize = CGSize(width: 72, height: 72)
            let symbolOrigin = CGPoint(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2
            )
            UIColor.systemGray3.setFill()
            symbol?.withTintColor(.systemGray3, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: symbolOrigin, size: symbolSize))
        }
    }
}
