//
//  Place.swift
//  Runnit iOS
//
//  A lightweight, Codable location value stored on a Trip. Coordinates are
//  kept as plain doubles because CLLocationCoordinate2D is not Codable.
//  Country / locality are resolved once (reverse geocoded) at save time so
//  the Passport and Map never have to geocode again.
//

import CoreLocation
import MapKit

nonisolated struct Place: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var isoCountryCode: String?
    var country: String?
    var locality: String?

    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String = "",
        latitude: Double,
        longitude: Double,
        isoCountryCode: String? = nil,
        country: String? = nil,
        locality: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.isoCountryCode = isoCountryCode
        self.country = country
        self.locality = locality
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// A short display label, preferring locality then name.
    var displayName: String {
        if !name.isEmpty { return name }
        if let locality, !locality.isEmpty { return locality }
        return country ?? "Unknown"
    }

    /// Flag emoji derived from the ISO country code, e.g. "US" -> 🇺🇸.
    var flag: String? {
        guard let code = isoCountryCode, code.count == 2 else { return nil }
        let base: UInt32 = 127397
        var scalarView = String.UnicodeScalarView()
        for scalar in code.uppercased().unicodeScalars {
            guard let flagScalar = Unicode.Scalar(base + scalar.value) else { return nil }
            scalarView.append(flagScalar)
        }
        return String(scalarView)
    }
}

extension Place {
    /// Resolve country / locality for a coordinate. Best-effort: on failure the
    /// place is returned unchanged so saving a trip never blocks on the network.
    func reverseGeocoded() async -> Place {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(clLocation)
            guard let mark = placemarks.first else { return self }
            var copy = self
            copy.isoCountryCode = mark.isoCountryCode ?? copy.isoCountryCode
            copy.country = mark.country ?? copy.country
            copy.locality = mark.locality ?? mark.administrativeArea ?? copy.locality
            return copy
        } catch {
            return self
        }
    }
}

#if DEBUG
extension Place {
    static let sfo = Place(name: "San Francisco Intl (SFO)", subtitle: "San Francisco, CA",
                           latitude: 37.6213, longitude: -122.3790,
                           isoCountryCode: "US", country: "United States", locality: "San Francisco")
    static let jfk = Place(name: "John F. Kennedy Intl (JFK)", subtitle: "New York, NY",
                           latitude: 40.6413, longitude: -73.7781,
                           isoCountryCode: "US", country: "United States", locality: "New York")
    static let lhr = Place(name: "Heathrow (LHR)", subtitle: "London, UK",
                           latitude: 51.4700, longitude: -0.4543,
                           isoCountryCode: "GB", country: "United Kingdom", locality: "London")
    static let paris = Place(name: "Gare du Nord", subtitle: "Paris, France",
                             latitude: 48.8809, longitude: 2.3553,
                             isoCountryCode: "FR", country: "France", locality: "Paris")
    static let yosemite = Place(name: "Yosemite National Park", subtitle: "California",
                                latitude: 37.8651, longitude: -119.5383,
                                isoCountryCode: "US", country: "United States", locality: "Yosemite Valley")
    static let bigSur = Place(name: "Big Sur", subtitle: "California",
                              latitude: 36.2704, longitude: -121.8081,
                              isoCountryCode: "US", country: "United States", locality: "Big Sur")
}
#endif
