//
//  Preferences.swift
//  Runnit iOS
//
//  User-facing app preferences (appearance + distance units), stored in
//  UserDefaults and surfaced on the Account page.
//

import SwiftUI

enum PrefKey {
    // NOTE: keys must not contain a dot — UserDefaults KVO treats a dotted key
    // as a key path, which breaks @AppStorage live updates across views.
    static let appearance = "prefAppearance"
    static let distanceUnit = "prefDistanceUnit"
    static let displayName = "prefDisplayName"
    /// The traveler's @handle, home base, and contact — the editable identity
    /// surfaced on the Account tab.
    static let username = "prefUsername"
    static let homeBase = "prefHomeBase"
    static let email = "prefEmail"
    /// Which accent the profile avatar and hero use, so the card feels personal.
    static let avatarTint = "prefAvatarTint"
    /// Smart Auto: allow one automatic flight-status fetch when opening a
    /// day-of / in-air flight. Off by default to conserve the API budget.
    static let flightAutoRefresh = "prefFlightAutoRefresh"
}

/// The palette a traveler can pick for their profile avatar and hero card.
/// Mirrors the mode/section accents used across the app so the choice always
/// looks at home next to the Trips and Passport screens.
enum ProfileAccent: String, CaseIterable, Identifiable {
    case cyan, blue, indigo, purple, pink, orange, green, teal

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .cyan:   return .cyan
        case .blue:   return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink:   return .pink
        case .orange: return .orange
        case .green:  return .green
        case .teal:   return .teal
        }
    }

    /// The accent currently saved in UserDefaults, defaulting to the app tint.
    static var current: ProfileAccent {
        let raw = UserDefaults.standard.string(forKey: PrefKey.avatarTint) ?? ProfileAccent.cyan.rawValue
        return ProfileAccent(rawValue: raw) ?? .cyan
    }
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
