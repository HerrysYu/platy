//
//  MenuTextLanguageDetector.swift
//  ProjectMayaIOS
//
//  Detects OCR text that is already written in the user's target menu
//  language so the translation pipeline can skip it entirely (no DeepL
//  call, no overlay box).
//

import Foundation
import NaturalLanguage

enum MenuTextLanguageDetector {

    /// Returns true when `text` is already written in the target menu
    /// language (e.g. the English lines on a Chinese menu when the user
    /// translates to English). Mixed-language blocks are NOT skipped.
    static func isText(_ text: String, alreadyIn targetLanguage: String) -> Bool {
        guard let target = normalizedTarget(for: targetLanguage) else { return false }

        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }

        switch target {
        case .chinese:
            return letters.allSatisfy(isHan)
        case .japanese:
            let allJapanese = letters.allSatisfy { isHan($0) || isKana($0) }
            if allJapanese && letters.contains(where: isKana) { return true }
            // Kanji-only words are ambiguous with Chinese; ask the recognizer.
            return allJapanese && dominantLanguage(of: text, among: [.japanese, .simplifiedChinese, .traditionalChinese]) == .japanese
        case .korean:
            return letters.allSatisfy(isHangul)
        case .latin(let language):
            guard letters.allSatisfy(isLatin) else { return false }
            let candidates: [NLLanguage] = [.english, .french, .spanish, .german, .italian, .portuguese, .dutch]
            let dominant = dominantLanguage(of: text, among: candidates, boosting: language)
            if dominant == language { return true }
            // Short menu words often defeat the recognizer; on a non-Latin
            // menu a pure-Latin block is almost always the English line.
            return language == .english && dominant == nil
        }
    }

    /// True when DeepL reports the source language of a block to be the
    /// same as the translation target (last-resort filter for blocks the
    /// local detector let through).
    static func detectedSource(_ detectedSourceLang: String?, matchesDeepLTarget targetCode: String) -> Bool {
        guard let detected = detectedSourceLang?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !detected.isEmpty else {
            return false
        }
        let targetPrefix = String(targetCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(2))
        guard targetPrefix.count == 2 else { return false }
        return detected.hasPrefix(targetPrefix)
    }

    // MARK: - Target language mapping

    private enum Target {
        case chinese
        case japanese
        case korean
        case latin(NLLanguage)
    }

    private static func normalizedTarget(for language: String) -> Target? {
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "english", "en":
            return .latin(.english)
        case "chinese", "中文", "zh", "zh-hans", "zh-hant", "simplified chinese":
            return .chinese
        case "japanese", "日本語", "ja":
            return .japanese
        case "korean", "한국어", "ko":
            return .korean
        case "french", "français", "fr":
            return .latin(.french)
        case "spanish", "español", "es":
            return .latin(.spanish)
        case "german", "deutsch", "de":
            return .latin(.german)
        case "italian", "italiano", "it":
            return .latin(.italian)
        default:
            return nil
        }
    }

    // MARK: - Recognition helpers

    private static func dominantLanguage(
        of text: String,
        among candidates: [NLLanguage],
        boosting boosted: NLLanguage? = nil
    ) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates
        if let boosted {
            recognizer.languageHints = [boosted: 1.4]
        }
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    // MARK: - Script helpers

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF:
            return true
        default:
            return false
        }
    }

    private static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F:
            return true
        default:
            return false
        }
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F:
            return true
        default:
            return false
        }
    }
}
