import AVFoundation
import Combine
import SwiftUI

final class StubCameraService: CameraService {

    private let stubPhotos: [UIImage]
    private var currentPhotoIndex = 0

    init(stubPhotos: [UIImage] = []) {
        self.stubPhotos = stubPhotos.isEmpty ? Self.defaultStubPhotos : stubPhotos
    }

    override func start() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    override func capture() {

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            if !stubPhotos.isEmpty {
                self.latestPhoto = stubPhotos[currentPhotoIndex]
                currentPhotoIndex = (currentPhotoIndex + 1) % stubPhotos.count
            } else {

                self.latestPhoto = Self.createPlaceholderImage()
            }
        }
    }

    private static func createPlaceholderImage() -> UIImage {
        let size: CGSize = CGSize(width: 1080, height: 1920)
        let renderer: UIGraphicsImageRenderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let colors: [UIColor] = [
                .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemRed,
            ]
            let randomColor = colors.randomElement() ?? .systemBlue

            randomColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let text = "Stub Photo"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: UIColor.white,
            ]

            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )

            text.draw(in: textRect, withAttributes: attributes)
        }
    }

    private static var defaultStubPhotos: [UIImage] {

        return (0..<5).map { index in
            let size = CGSize(width: 1080, height: 1920)
            let renderer: UIGraphicsImageRenderer = UIGraphicsImageRenderer(size: size)

            return renderer.image { context in
                let colors: [UIColor] = [
                    .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemRed,
                ]
                let color: UIColor = colors[index % colors.count]

                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))

                let text: String = "Stub Photo \(index + 1)"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                    .foregroundColor: UIColor.white,
                ]

                let textSize: CGSize = text.size(withAttributes: attributes)
                let textRect: CGRect = CGRect(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                )

                text.draw(in: textRect, withAttributes: attributes)
            }
        }
    }
}
