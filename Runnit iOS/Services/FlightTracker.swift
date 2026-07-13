//
//  FlightTracker.swift
//  Runnit iOS
//
//  The single choke point for AviationStack calls. Views never touch the client
//  directly — they read cached `FlightStatusRecord`s and ask the tracker to
//  refresh. Every network path here is gated to protect the 100-call/month free
//  tier: cache-first, freeze-on-final, quota checks, and negative caching so a
//  "no data" answer isn't retried in a loop.
//

import Foundation
import Observation
import SwiftData

/// What a refresh attempt did — surfaced to the UI for messaging.
enum RefreshOutcome: Equatable {
    case updated          // fetched fresh live data
    case noData           // API answered but had no matching flight
    case frozen           // already landed/cancelled; nothing to do
    case notTrackable     // missing/unparseable flight number
    case notYetTrackable  // real flight, but not within the free tier's real-time reach yet
    case noKey            // no API key configured
    case quotaExceeded    // monthly budget spent
    case skippedFresh     // cache still fresh; no call made
    case failed           // transport/decoding error
}

@MainActor
@Observable
final class FlightTracker {
    let usage: APIUsageTracker
    private let client: AviationStackClient

    init(usage: APIUsageTracker, client: AviationStackClient = AviationStackClient()) {
        self.usage = usage
        self.client = client
    }

    // MARK: Lookup (for auto-fill when adding/editing a flight)

    /// The raw facts a flight-number lookup returns. Times carry the API's
    /// scheduled instants; the airport timezones let the caller stamp them onto a
    /// chosen travel date correctly.
    struct FlightLookupResult {
        var airlineName: String?
        var flightIata: String?
        var departureAirportName: String?
        var departureIata: String?
        var departureTimeZone: String?
        var departureScheduled: Date?
        var arrivalAirportName: String?
        var arrivalIata: String?
        var arrivalTimeZone: String?
        var arrivalScheduled: Date?
    }

    enum FlightLookupOutcome: Equatable {
        case success(FlightLookupResult)
        case notFound
        case invalidNumber
        case noKey
        case quotaExceeded
        case failed

        static func == (l: FlightLookupOutcome, r: FlightLookupOutcome) -> Bool {
            switch (l, r) {
            case (.notFound, .notFound), (.invalidNumber, .invalidNumber),
                 (.noKey, .noKey), (.quotaExceeded, .quotaExceeded), (.failed, .failed):
                return true
            case (.success, .success): return true
            default: return false
            }
        }
    }

    /// Look up a flight by number to auto-fill trip details. Spends one call.
    /// The free tier only serves today's flights, so this returns today's instance
    /// of the number (route/airline/times are stable enough to prefill a future
    /// trip); `.notFound` when the flight isn't operating today.
    func lookup(flightNumber: String) async -> FlightLookupOutcome {
        guard let iata = FlightIdentityParser.normalizedFlightIata(from: flightNumber) else {
            return .invalidNumber
        }
        guard Secrets.hasAviationStackKey else { return .noKey }
        guard usage.canSpend else { return .quotaExceeded }

        do {
            let flight = try await client.fetch(flightIata: iata, departureIata: nil, target: nil)
            usage.record()
            guard let flight else { return .notFound }
            return .success(FlightLookupResult(
                airlineName: flight.airline?.name,
                flightIata: flight.flight?.iata ?? iata,
                departureAirportName: flight.departure?.airport,
                departureIata: flight.departure?.iata,
                departureTimeZone: flight.departure?.timezone,
                departureScheduled: ASDate.parse(flight.departure?.scheduled),
                arrivalAirportName: flight.arrival?.airport,
                arrivalIata: flight.arrival?.iata,
                arrivalTimeZone: flight.arrival?.timezone,
                arrivalScheduled: ASDate.parse(flight.arrival?.scheduled)
            ))
        } catch AviationStackError.quotaExceeded {
            usage.markLimitReached()
            return .quotaExceeded
        } catch AviationStackError.noKey {
            return .noKey
        } catch {
            return .failed
        }
    }

    // MARK: Cache reads

    /// The cached snapshot for a segment, if any.
    func record(for segment: TripSegment, in context: ModelContext) -> FlightStatusRecord? {
        let id = segment.id
        let descriptor = FetchDescriptor<FlightStatusRecord>(
            predicate: #Predicate { $0.segmentID == id }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: Manual refresh

    /// User-initiated refresh for one leg. Honors freeze + quota, always counts
    /// as a call when it actually reaches the network.
    @discardableResult
    func refresh(_ segment: TripSegment, in context: ModelContext) async -> RefreshOutcome {
        await fetch(segment, in: context, respectFreshness: false)
    }

    // MARK: Smart Auto

    /// Called on detail open when Smart Auto is enabled. Only spends a call for a
    /// leg that is relevant *today* / airborne, has no fresh cache, and is under
    /// quota. Otherwise does nothing.
    @discardableResult
    func autoRefreshIfNeeded(_ segment: TripSegment, in context: ModelContext, enabled: Bool) async -> RefreshOutcome {
        guard enabled, Secrets.hasAviationStackKey, usage.canSpend else { return .skippedFresh }
        guard FlightIdentityParser.canTrack(segment) else { return .notTrackable }

        let existing = record(for: segment, in: context)
        if existing?.isFinal == true { return .frozen }
        guard isRelevantNow(segment, record: existing) else { return .skippedFresh }
        if let existing, !isStale(existing) { return .skippedFresh }

        return await fetch(segment, in: context, respectFreshness: true)
    }

    // MARK: Core fetch

    private func fetch(_ segment: TripSegment, in context: ModelContext, respectFreshness: Bool) async -> RefreshOutcome {
        guard Secrets.hasAviationStackKey else { return .noKey }
        guard let identity = FlightIdentityParser.resolve(segment) else { return .notTrackable }

        let existing = record(for: segment, in: context)
        if existing?.isFinal == true { return .frozen }
        // The free tier only serves real-time data (no historical/future lookups),
        // so a call is only meaningful when the flight is departing today or is
        // currently airborne. Otherwise flight_iata returns some OTHER day's
        // instance of the same number — don't spend a call, don't mislead.
        guard Self.isWithinRealtimeReach(segment) else { return .notYetTrackable }
        if respectFreshness, let existing, !isStale(existing) { return .skippedFresh }
        guard usage.canSpend else { return .quotaExceeded }

        do {
            let flight = try await client.fetch(
                flightIata: identity.flightIata,
                departureIata: identity.departureIata,
                target: segment.departureDate
            )
            // A response came back and counted against the budget.
            usage.record()

            let rec = existing ?? {
                let r = FlightStatusRecord(segmentID: segment.id)
                context.insert(r)
                return r
            }()

            if let flight {
                rec.apply(flight)
                try? context.save()
                return .updated
            } else {
                rec.markEmpty()
                try? context.save()
                return .noData
            }
        } catch AviationStackError.quotaExceeded {
            usage.markLimitReached()
            return .quotaExceeded
        } catch AviationStackError.noKey {
            return .noKey
        } catch {
            // Transport / decoding / HTTP: no reliable proof a request was billed,
            // so don't decrement the user's budget for it.
            return .failed
        }
    }

    // MARK: Policy helpers

    /// Whether the free tier's real-time endpoint can meaningfully answer for this
    /// leg: it must be departing today or currently in the air. Outside this window
    /// the API can only return a different day's instance of the same flight number.
    nonisolated static func isWithinRealtimeReach(_ segment: TripSegment, now: Date = Date()) -> Bool {
        let cal = Calendar.current
        if cal.isDateInToday(segment.departureDate) { return true }
        if let arr = segment.arrivalDate, cal.isDateInToday(arr) { return true }
        let end = (segment.arrivalDate ?? segment.departureDate).addingTimeInterval(2 * 3600)
        return now >= segment.departureDate && now <= end
    }

    /// Whether this leg is worth spending a call on right now (day-of or airborne).
    private func isRelevantNow(_ segment: TripSegment, record: FlightStatusRecord?) -> Bool {
        if record?.phase == .active { return true }
        return Self.isWithinRealtimeReach(segment)
    }

    /// Cache staleness by phase — the only thing that permits an auto-refetch.
    private func isStale(_ record: FlightStatusRecord) -> Bool {
        let age = Date().timeIntervalSince(record.fetchedAt)
        if !record.didFindData { return age > 6 * 3600 }   // negative cache
        switch record.phase {
        case .active:              return age > 30 * 60
        case .scheduled, .unknown: return age > 3 * 3600
        default:                   return false             // final states
        }
    }
}
