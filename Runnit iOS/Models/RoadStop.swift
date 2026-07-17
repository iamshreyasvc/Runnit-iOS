//
//  RoadStop.swift
//  Runnit iOS
//
//  An intermediate stop along a road-trip leg — a place plus what it's for
//  (food, gas, a scenic overlook…). Stored as a Codable value on TripSegment,
//  so adding stops is an additive, lightweight-migration change.
//

import Foundation

/// What a road-trip stop is for. Drives the stop's icon and tint.
enum StopCategory: String, Codable, CaseIterable, Identifiable {
    case food, coffee, gas, charging, lodging, scenic, sights, shopping, rest, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .food:     return "Food"
        case .coffee:   return "Coffee"
        case .gas:      return "Gas"
        case .charging: return "Charging"
        case .lodging:  return "Lodging"
        case .scenic:   return "Scenic"
        case .sights:   return "Sights"
        case .shopping: return "Shopping"
        case .rest:     return "Rest stop"
        case .other:    return "Stop"
        }
    }

    var symbol: String {
        switch self {
        case .food:     return "fork.knife"
        case .coffee:   return "cup.and.saucer.fill"
        case .gas:      return "fuelpump.fill"
        case .charging: return "bolt.fill"
        case .lodging:  return "bed.double.fill"
        case .scenic:   return "mountain.2.fill"
        case .sights:   return "camera.fill"
        case .shopping: return "bag.fill"
        case .rest:     return "parkingsign"
        case .other:    return "mappin"
        }
    }
}

/// One waypoint along a road trip.
struct RoadStop: Codable, Hashable, Identifiable {
    var id = UUID()
    var place: Place
    private var categoryRaw: String = StopCategory.other.rawValue
    /// An optional short note, e.g. "lunch reservation 1pm".
    var note: String?

    init(id: UUID = UUID(), place: Place, category: StopCategory = .other, note: String? = nil) {
        self.id = id
        self.place = place
        self.categoryRaw = category.rawValue
        self.note = note
    }

    var category: StopCategory {
        get { StopCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// A display label for the stop, preferring the place's own name.
    var displayName: String { place.displayName }
}
