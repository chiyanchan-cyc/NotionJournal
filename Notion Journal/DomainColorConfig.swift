//
//  DomainColorConfig.swift
//  Notion Journal
//
//  Created by Mac on 2026/02/03.
//

import SwiftUI

enum NJDomainColorConfig {
    // Ordered list of the second-tier domains you want to standardize.
    static let orderedSecondTierDomains: [String] = [
        "me.finance",
        "me.rel",
        "zz.edu",
        "zz.music",
        "zz.sport",
        "zz.adhd",
        "me.dev",
        "me.mind"
    ]

    // Pastel, light colors for each standardized domain.
    // Feel free to tweak these to taste.
    static let pastelByDomain: [String: Color] = [
        "me.finance": Color(red: 0.78, green: 0.92, blue: 0.86),
        "me.rel": Color(red: 0.98, green: 0.86, blue: 0.78),
        "zz.edu": Color(red: 0.86, green: 0.84, blue: 0.96),
        "zz.music": Color(red: 0.80, green: 0.90, blue: 0.98),
        "zz.sport": Color(red: 0.98, green: 0.95, blue: 0.76),
        "zz.adhd": Color(red: 0.98, green: 0.84, blue: 0.88),
        "me.dev": Color(red: 0.78, green: 0.92, blue: 0.95),
        "me.mind": Color(red: 0.90, green: 0.84, blue: 0.94)
    ]

    static func normalizedSecondTierKey(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return "" }
        let parts = t.split(separator: ".")
        if parts.isEmpty { return "" }
        let head = String(parts[0])
        if (head == "zz" || head == "me"), parts.count >= 2 {
            return "\(parts[0]).\(parts[1])"
        }
        return head
    }

    static func color(for raw: String) -> Color? {
        let key = normalizedSecondTierKey(raw)
        if key.isEmpty { return nil }
        if let c = pastelByDomain[key] { return c }
        return fallbackPastel(for: key)
    }

    private static func fallbackPastel(for key: String) -> Color {
        let hueDeg = Double(abs(key.hashValue) % 360)
        return Color(hue: hueDeg / 360.0, saturation: 0.28, brightness: 0.97)
    }
}
