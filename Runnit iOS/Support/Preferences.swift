//
//  Preferences.swift
//  Runnit iOS
//
//  User-facing app preferences (appearance + distance units), stored in
//  UserDefaults and surfaced on the Account page.
//

import SwiftUI

enum PrefKey {
    static let appearance = "pref.appearance"
    static let distanceUnit = "pref.distanceUnit"
    static let displayName = "pref.displayName"
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

enum DistanceUnit: String, CaseIterable, Identifiable {
    case automatic, kilometers, miles
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic:  return "Automatic"
        case .kilometers: return "Kilometers"
        case .miles:      return "Miles"
        }
    }

    /// The unit currently selected in UserDefaults (used by Format).
    static var current: DistanceUnit {
        let raw = UserDefaults.standard.string(forKey: PrefKey.distanceUnit) ?? DistanceUnit.automatic.rawValue
        return DistanceUnit(rawValue: raw) ?? .automatic
    }
}
