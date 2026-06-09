//
//  config.swift
//  ProjectMayaIOS
//
//  Created by Herrys Yu on 2025-07-15.
//

import Foundation

enum PlatyConfig {
    static let projectRef = "yxsjccowvxzxjiqfhazg"

    static var supabaseURL: URL {
        URL(string: value(
            for: "SUPABASE_URL",
            fallback: "https://\(projectRef).supabase.co"
        ))!
    }

    /// Public mobile/browser key. Keep service-role keys out of the app bundle.
    static var supabasePublishableKey: String {
        value(
            for: "SUPABASE_PUBLISHABLE_KEY",
            fallback: "sb_publishable_B6KCU2Zd4F-nz9xUVODKjQ_3bl3Nzow"
        )
    }

    static var isSupabaseConfigured: Bool {
        !supabasePublishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func authURL(_ path: String) -> URL {
        supabaseURL.appendingPathComponent("auth/v1").appendingPathComponent(path)
    }

    static func functionURL(_ slug: String) -> URL {
        supabaseURL.appendingPathComponent("functions/v1").appendingPathComponent(slug)
    }

    private static func value(for key: String, fallback: String) -> String {
        if let infoValue = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !infoValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return infoValue
        }

        if let envValue = ProcessInfo.processInfo.environment[key],
           !envValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envValue
        }

        return fallback
    }
}

@available(*, deprecated, message: "Use PlatyConfig/Supabase Edge Functions instead.")
var baseurl: String = PlatyConfig.supabaseURL.absoluteString
