//
//  FlightIdentity.swift
//  Runnit iOS
//
//  Derives the identifiers an aviation API needs (flight IATA code, departure
//  airport IATA) from the loosely-typed fields the user entered. Airports carry
//  their code inline in `Place.name`, e.g. "San Francisco Intl (SFO)"; flight
//  numbers live in `TripSegment.vehicleNumber`, e.g. "UA 523".
//

import Foundation

/// The minimal identity needed to look a flight up. `nil` from `resolve`
/// means the leg can't be tracked (missing/unparseable flight number).
struct FlightIdentity: Equatable {
    /// Normalized flight code, e.g. "UA523".
    let flightIata: String
    /// Departure airport IATA (3 letters) when known, else `nil`.
    let departureIata: String?
    /// Arrival airport IATA when known, else `nil`.
    let arrivalIata: String?
}

enum FlightIdentityParser {
    /// Extract a 3-letter IATA code from a place name's trailing "(XXX)".
    static func iataCode(from place: Place) -> String? {
        iataCode(fromText: place.name) ?? iataCode(fromText: place.subtitle)
    }

    static func iataCode(fromText text: String) -> String? {
        // Prefer a parenthesized code like "(SFO)".
        if let range = text.range(of: #"\(([A-Za-z]{3})\)"#, options: .regularExpression) {
            let inner = text[range].dropFirst().dropLast()
            return inner.uppercased()
        }
        return nil
    }

    /// Turn a user-typed flight number like "UA 523" / "ua-523" into "UA523".
    /// Requires an airline prefix (letters/digits) followed by a flight number.
    static func normalizedFlightIata(from raw: String?) -> String? {
        guard let raw else { return nil }
        // Keep only alphanumerics, uppercased.
        let compact = raw.uppercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init)
        let s = String(compact)
        // Must contain at least two leading letters/alnum for the airline code
        // and at least one digit for the flight number.
        guard s.count >= 3, s.contains(where: \.isNumber), s.contains(where: \.isLetter) else {
            return nil
        }
        return s
    }

    /// Full identity for a segment, or `nil` when it can't be tracked.
    static func resolve(_ segment: TripSegment) -> FlightIdentity? {
        guard segment.type == .flight,
              let flightIata = normalizedFlightIata(from: segment.vehicleNumber)
        else { return nil }
        return FlightIdentity(
            flightIata: flightIata,
            departureIata: iataCode(from: segment.origin),
            arrivalIata: iataCode(from: segment.destination)
        )
    }

    /// Whether a segment is eligible for live tracking at all.
    static func canTrack(_ segment: TripSegment) -> Bool {
        resolve(segment) != nil
    }
}
