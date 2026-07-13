//
//  LocationSearchService.swift
//  Runnit iOS
//
//  Wraps MKLocalSearchCompleter to provide live autocomplete suggestions, and
//  resolves a chosen suggestion into a full Place (with coordinates). Used by
//  LocationSearchField.
//

import Foundation
import MapKit
import Observation

@Observable
@MainActor
final class LocationSearchService: NSObject, MKLocalSearchCompleterDelegate {
    var query: String = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var suggestions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Airports, stations, addresses and POIs all make sense here.
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func clear() {
        query = ""
        suggestions = []
    }

    /// Resolve a completion into a Place with coordinates. Country/locality are
    /// filled from the search result when available; otherwise the caller can
    /// reverse-geocode.
    func resolve(_ completion: MKLocalSearchCompletion) async -> Place? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else { return nil }
            let coordinate = item.placemark.coordinate
            return Place(
                name: completion.title,
                subtitle: completion.subtitle,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                isoCountryCode: item.placemark.isoCountryCode,
                country: item.placemark.country,
                locality: item.placemark.locality ?? item.placemark.administrativeArea
            )
        } catch {
            return nil
        }
    }

    /// Resolve an airport (by name and/or IATA) into a Place with coordinates,
    /// using Apple's local search (free — no aviation-API cost). The returned
    /// Place embeds the IATA in its name, matching the app's convention.
    func resolveAirport(name: String?, iata: String?) async -> Place? {
        let queryName = name?.trimmingCharacters(in: .whitespaces)
        let terms = [queryName, iata].compactMap { $0 }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        // "<airport name> airport" reliably resolves the airport POI.
        request.naturalLanguageQuery = (queryName.map { "\($0) airport" }) ?? "\(iata!) airport"
        request.resultTypes = [.pointOfInterest, .address]

        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return nil }

        let coordinate = item.placemark.coordinate
        let base = queryName ?? item.name ?? (iata ?? "Airport")
        let displayName = iata.map { "\(base) (\($0))" } ?? base
        return Place(
            name: displayName,
            subtitle: item.placemark.locality ?? item.placemark.administrativeArea ?? "",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            isoCountryCode: item.placemark.isoCountryCode,
            country: item.placemark.country,
            locality: item.placemark.locality ?? item.placemark.administrativeArea
        )
    }

    // MARK: MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.suggestions = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
        }
    }
}
