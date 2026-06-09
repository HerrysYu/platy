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
    let translatedText:String?
}

