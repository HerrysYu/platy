import SwiftUI
import UIKit

// MARK: - Camera Service Factory

enum CameraServiceFactory {
    /// Smart camera service that automatically loads test images in local test environment
    static func createSmartCameraService() -> CameraService {
        if isLocalTestEnvironment {
            let customPhotos = loadCustomPhotos()
            if !customPhotos.isEmpty {
                return StubCameraService(stubPhotos: customPhotos)
            } else {
                return StubCameraService()
            }
        } else {
            return RealCameraService()
        }
    }
    
    /// Automatically detects if running on simulator or real device
    static func createCameraService(stubPhotos: [UIImage] = []) -> CameraService {
        if isSimulator {
            return StubCameraService(stubPhotos: stubPhotos)
        } else {
            return RealCameraService()
        }
    }
    
    /// Manual override for testing
    static func createCameraService(useStub: Bool, stubPhotos: [UIImage] = []) -> CameraService {
        if useStub {
            return StubCameraService(stubPhotos: stubPhotos)
        } else {
            return RealCameraService()
        }
    }
    
    /// Check if running in local test environment (Debug + Simulator)
    private static var isLocalTestEnvironment: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    /// Check if running on iOS Simulator
    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    /// Load custom photos from TestingAssets and fallback options
    private static func loadCustomPhotos() -> [UIImage] {
        var photos: [UIImage] = []
        
        photos = loadAllImagesFromTestingAssets()
        
        if photos.isEmpty {
            return createSampleMenuPhotos()
        }
        return photos
    }
    
    /// Load all images from TestingAssets
    private static func loadAllImagesFromTestingAssets() -> [UIImage] {
        var images: [UIImage] = []
        
        print("Attempting to load test images...")
        let alternativeNames = ["menu", "menu2", "TestingAsset/menu", "TestingAsset/menu2"]
        
        for name in alternativeNames {
            if let image = UIImage(named: name) {
                images.append(image)
                print("✅ Successfully loaded menu image: \(name)")
            } else {
                print("❌ Failed to load image: \(name)")
            }
        }
        
        if images.isEmpty {
            print("⚠️ No test images found, falling back to sample menu photos")
        } else {
            print("✅ Total loaded test images: \(images.count)")
        }

        return images
    }
    
    /// Create sample menu photos as fallback
    private static func createSampleMenuPhotos() -> [UIImage] {
        return [
            createMenuPhoto(
                text: "Spaghetti Carbonara\n$18.99\nClassic Italian pasta with eggs, cheese, and pancetta"
            ),
            createMenuPhoto(
                text: "Margherita Pizza\n$16.99\nFresh mozzarella, tomato sauce, and basil"),
            createMenuPhoto(
                text: "Caesar Salad\n$12.99\nRomaine lettuce, parmesan cheese, croutons"),
            createMenuPhoto(text: "Tiramisu\n$8.99\nItalian dessert with coffee and mascarpone"),
            createMenuPhoto(text: "Bruschetta\n$6.99\nToasted bread with tomatoes and herbs"),
        ]
    }

    /// Create a menu photo with text
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