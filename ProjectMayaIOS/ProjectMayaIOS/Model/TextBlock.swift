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

enum DishNameSanitizer {
    private static let edgeDots = CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: ".。．…⋯․‥·•‧∙⋅・")
    )
    private static let trailingSeparators = CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: ".。．…⋯․‥·•‧∙⋅・-‐‑‒–—―_|｜¦~～:：;；,，")
    )
    private static let trailingMetadataExpressions: [NSRegularExpression] = {
        let amount = #"\d{1,7}(?:[.,]\d{1,2})?"#
        let currencyCodes = #"(?:RMB|CNY|USD|EUR|GBP|JPY|KRW|HKD|TWD|NTD|SGD|AUD|CAD|THB|VND|INR|PHP|MYR|IDR)"#
        let prefixCurrency = #"(?:(?:HK|NT|US|S|AU|CA)?\p{Sc}|"# + currencyCodes + ")"
        let suffixCurrency = #"(?:\p{Sc}|元|圆|圓|块|塊|円|원|บาท|"# + currencyCodes + ")"
        let serving = #"(?:\s*[/／]\s*(?:份|位|例|盘|盤|碟|碗|杯|个|個|只|人|斤|两|兩|克|g|kg|person|pc))?"#
        let qualifier = #"(?:\s*(?:起|以上|up))?"#
        let optionalSeparator = #"[\s.…⋯․‥·•‧∙⋅・:：|｜¦_＿~～‐‑‒–—―-]*"#
        let requiredLeader = #"[\s.…⋯․‥·•‧∙⋅・:：|｜¦_＿~～‐‑‒–—―-]{2,}"#
        let patterns = [
            optionalSeparator + #"(?:时价|時價|market\s*price|m\.?p\.?)\s*$"#,
            optionalSeparator + "(?:(?:" + prefixCurrency + #"\s*"# + amount + ")|(?:" + amount + #"\s*"# + suffixCurrency + "))" + serving + qualifier + #"\s*$"#,
            requiredLeader + "(?:" + prefixCurrency + #"\s*)?"# + amount + #"(?:\s*"# + suffixCurrency + ")?" + serving + qualifier + #"\s*$"#
        ]
        return patterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
    }()

    /// Removes OCR leader dots, trailing separators, and trailing menu prices.
    /// Internal punctuation and a legitimate leading hyphen remain untouched.
    static func clean(_ value: String) -> String {
        var cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: edgeDots)

        trimTrailingSeparators(from: &cleaned)

        for expression in trailingMetadataExpressions {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = expression.stringByReplacingMatches(
                in: cleaned,
                range: range,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        trimTrailingSeparators(from: &cleaned)

        return cleaned
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: edgeDots)
    }

    static func cleanOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = clean(value)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func trimTrailingSeparators(from value: inout String) {
        while let last = value.last,
              last.unicodeScalars.allSatisfy({ trailingSeparators.contains($0) }) {
            value.removeLast()
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
