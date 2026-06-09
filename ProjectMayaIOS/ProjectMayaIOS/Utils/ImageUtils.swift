
import SwiftUI

final class ImageUtils {
    
    /// Fixes the orientation of a UIImage to `.up`.
    ///
    /// - Parameter image: The input UIImage.
    /// - Returns: A new UIImage with orientation fixed to `.up`.
    static func fixedOrientation(of image: UIImage) -> UIImage {
        // If the orientation is already correct, return it
        if image.imageOrientation == .up {
            return image
        }
        
        // Create a graphics context and redraw the image into it
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let fixedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return fixedImage ?? image
    }

    static func preparedForMenuAnalysis(_ image: UIImage) -> UIImage {
        let fixedImage = fixedOrientation(of: image)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: fixedImage.size, format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: fixedImage.size))
            fixedImage.draw(in: CGRect(origin: .zero, size: fixedImage.size))
        }
    }
}
//
//  ImageUtils.swift
//  ProjectMayaIOS
//
//  Created by Herrys Yu on 2025-06-22.
//
