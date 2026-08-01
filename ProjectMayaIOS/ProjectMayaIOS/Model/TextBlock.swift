//
//  TextBlock.swift
//  practice
//
//  Created by Herrys Yu on 5/21/25.
//
import Foundation

struct TextBlock: Codable {
    let text: String
    let angle: Double
    let box2D: [CGFloat]
    let translatedText: String?
    let categoryOriginal: String?
    let menuTitleOriginal: String?

    init(
        text: String,
        angle: Double,
        box2D: [CGFloat],
        translatedText: String?,
        categoryOriginal: String? = nil,
        menuTitleOriginal: String? = nil
    ) {
        self.text = text
        self.angle = angle
        self.box2D = box2D
        self.translatedText = translatedText
        self.categoryOriginal = categoryOriginal
        self.menuTitleOriginal = menuTitleOriginal
    }
}
