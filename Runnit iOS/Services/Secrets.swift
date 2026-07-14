//
//  Secrets.swift
//  Runnit iOS
//
//  Reads local, uncommitted secrets (currently just the AviationStack API key)
//  from a bundled `Secrets.plist`. That file is gitignored; a committed
//  `Secrets.example.plist` template documents the format. When the key is
//  missing or left as the placeholder, live flight tracking is simply disabled.
//

import Foundation

enum Secrets {
    private static let placeholder = "PASTE_YOUR_KEY_HERE"

    /// The AviationStack API key, or `nil` when unconfigured.
    static var aviationStackKey: String? {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let raw = dict["AviationStackAPIKey"] as? String
        else { return nil }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != placeholder else { return nil }
        return trimmed
    }

    /// Whether a usable API key is present.
    static var hasAviationStackKey: Bool { aviationStackKey != nil }
}
