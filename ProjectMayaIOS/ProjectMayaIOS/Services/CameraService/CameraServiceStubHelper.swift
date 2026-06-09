import SwiftUI
import UIKit

class CameraServiceStubHelper {
    static func createSmartCameraService() -> CameraService {
        let customPhotos = loadCustomPhotos()
        if !customPhotos.isEmpty {
            return CameraServiceFactory.createCameraService(useStub: true, stubPhotos: customPhotos)
        } else {

            return CameraServiceFactory.createCameraService()
        }
    }

    private static func loadCustomPhotos() -> [UIImage] {
        var photos: [UIImage] = []

        photos = loadAllImagesFromTestingAssets()

        if photos.isEmpty {
            return createSampleMenuPhotos()
        }
        return photos
    }

    private static func loadAllImagesFromTestingAssets() -> [UIImage] {
        var images: [UIImage] = []
        if images.isEmpty {
            print("Trying alternative naming patterns...")
            let alternativeNames = ["menu", "menu2", "TestingAsset/menu", "TestingAsset/menu2"]
            
            for name in alternativeNames {
                if let image = UIImage(named: name) {
                    images.append(image)
                    print("Loaded menu image with alternative name: \(name)")
                }
            }
        }

        return images
    }
    
    private static func createSampleMenuPhotos() -> [UIImage] {
        return [
            createMenuPhoto(
                text:
                    "Spaghetti Carbonara\n$18.99\nClassic Italian pasta with eggs, cheese, and pancetta"
            ),
            createMenuPhoto(
                text: "Margherita Pizza\n$16.99\nFresh mozzarella, tomato sauce, and basil"),
            createMenuPhoto(
                text: "Caesar Salad\n$12.99\nRomaine lettuce, parmesan cheese, croutons"),
            createMenuPhoto(text: "Tiramisu\n$8.99\nItalian dessert with coffee and mascarpone"),
            createMenuPhoto(text: "Bruschetta\n$6.99\nToasted bread with tomatoes and herbs"),
        ]
    }

    private static func createMenuPhoto(text: String) -> UIImage {
        let size: CGSize = CGSize(width: 1080, height: 1920)
        let renderer: UIGraphicsImageRenderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in

            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor.systemGray5.setFill()
            context.fill(CGRect(x: 50, y: 100, width: size.width - 100, height: size.height - 200))

            let lines: [String] = text.components(separatedBy: "\n")
            let font: UIFont = UIFont.systemFont(ofSize: 32, weight: .medium)
            let textColor: UIColor = UIColor.label

            var yPosition: CGFloat = 200

            for line: String in lines {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor,
                ]

                let textSize: CGSize = line.size(withAttributes: attributes)
                let textRect: CGRect = CGRect(
                    x: (size.width - textSize.width) / 2,
                    y: yPosition,
                    width: textSize.width,
                    height: textSize.height
                )

                line.draw(in: textRect, withAttributes: attributes)
                yPosition += textSize.height + 20
            }

            UIColor.systemGray3.setStroke()
            context.stroke(
                CGRect(x: 50, y: 100, width: size.width - 100, height: size.height - 200))
        }
    }
}
