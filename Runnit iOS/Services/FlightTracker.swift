//
//  FlightTracker.swift
//  Runnit iOS
//
//  The single choke point for Flightradar24 calls. Views never touch the client
//  directly — they read cached `FlightStatusRecord`s and ask the tracker to
//  refresh. Fetches are still cache-first and freeze on landing, because a landed
//  flight's facts never change again.
//
//  FR24 has no schedule feed: a leg is invisible to the API until it actually
//  flies. `isWithinTrackingReach` encodes that — it opens at departure time and
//  stays open into the past, which is the mirror image of the old AviationStack
//  rule (same-day only, nothing historical).
//

import Foundation
import Observation
import SwiftData

/// What a refresh attempt did — surfaced to the UI for messaging.
enum RefreshOutcome: Equatable {
    case updated              // fetched fresh data
    case noData               // API answered but knows nothing about this flight
    case frozen               // already landed/diverted; nothing to do
    case notTrackable         // missing/unparseable flight number
    case notYetTrackable      // real flight, but it hasn't flown yet — FR24 has no schedules
    case noKey                // no API token configured
    case insufficientCredits  // FR24 returned 402
    case skippedFresh         // cache still fresh; no call made
    case failed               // transport/decoding error
}

/// One flight, assembled from the FR24 endpoints that each hold a piece of it.
struct FR24Snapshot: Equatable {
    var phase: FlightPhase
    var flightIata: String?
    var airlineName: String?
    var takeoff: Date?
    var landed: Date?
    var eta: Date?
    /// Present only while airborne — the sole source of telemetry.
    var position: FR24Position?
}

@MainActor
@Observable
final class FlightTracker {
    private let client: FR24Client
    private let statics: FR24StaticCache

    init(client: FR24Client = FR24Client(), statics: FR24StaticCache? = nil) {
        self.client = client
        self.statics = statics ?? FR24StaticCache()
    }

    // MARK: Lookup (for auto-fill when adding/editing a flight)

    /// The raw facts a flight-number lookup returns. Times carry the API's
    /// instants; the airport timezones let the caller stamp them onto a chosen
    /// travel date correctly.
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
        case insufficientCredits
        case failed

        static func == (l: FlightLookupOutcome, r: FlightLookupOutcome) -> Bool {
            switch (l, r) {
            case (.notFound, .notFound), (.invalidNumber, .invalidNumber),
                 (.noKey, .noKey), (.insufficientCredits, .insufficientCredits),
                 (.failed, .failed):
                return true
            case (.success, .success): return true
            default: return false
            }
        }
    }

    /// How far back to look for a previous operation of a flight number. FR24
    /// caps a summary query at a 14-day span; a week comfortably covers daily and
    /// most weekly services while keeping the response small.
    private static let lookbackDays = 7

    /// Look up a flight by number to auto-fill trip details.
    ///
    /// FR24 publishes no forward schedules, so there is nothing to ask about a
    /// flight that hasn't happened yet. Instead we take the most recent completed
    /// operation of that number and use *its* route and actual times as the
    /// prefill. For a regular scheduled service that's a good approximation — but
    /// they are last week's actual times, not a published schedule, so they can be
    /// off by minutes.
    func lookup(flightNumber: String) async -> FlightLookupOutcome {
        guard let iata = FlightIdentityParser.normalizedFlightIata(from: flightNumber) else {
            return .invalidNumber
        }
        guard Secrets.hasFlightRadarToken else { return .noKey }

        do {
            let now = Date()
            let window = TimeInterval(Self.lookbackDays * 24 * 3600)
            let summaries = try await client.summaries(
                flightIata: iata,
                from: now.addingTimeInterval(-window),
                to: now
            )

            // Only a leg that actually departed tells us anything about the route.
            guard let best = summaries
                .filter({ $0.datetimeTakeoff != nil })
                .max(by: { ($0.firstSeen ?? "") < ($1.firstSeen ?? "") })
            else { return .notFound }

            // Use the *filed* destination, not `dest_iata_actual`: if last week's
            // flight diverted, the traveler is still booked to where it was going.
            let depIata = best.origIata
            let arrIata = best.destIata

            async let depAirport = statics.airport(code: depIata)
            async let arrAirport = statics.airport(code: arrIata)
            async let airline = statics.airlineName(icao: best.paintedAs ?? best.operatingAs)
            let (dep, arr, airlineName) = await (depAirport, arrAirport, airline)

            return .success(FlightLookupResult(
                airlineName: airlineName,
                flightIata: best.flight ?? iata,
                departureAirportName: dep?.name,
                departureIata: depIata,
                departureTimeZone: dep?.timezone?.name,
                departureScheduled: FR24Date.parse(best.datetimeTakeoff),
                arrivalAirportName: arr?.name,
                arrivalIata: arrIata,
                arrivalTimeZone: arr?.timezone?.name,
                arrivalScheduled: FR24Date.parse(best.datetimeLanded)
            ))
        } catch FR24Error.insufficientCredits {
            return .insufficientCredits
        } catch FR24Error.noToken {
            return .noKey
        } catch {
            return .failed
        }
    }

    // MARK: Flight path (the actual flown track, for the map)

    /// The real path this flight flew, as map coordinates, or `nil` when it can't
    /// be drawn (no token, unparseable number, hasn't flown yet, or FR24 has no
    /// track). Resolves the leg's FR24 id from the summaries — the same matching
    /// the status snapshot uses — then pulls its positional trail. Works for
    /// historical flights, so Past Trips draw their true route.
    func flightPath(for segment: TripSegment) async -> [RoutePoint]? {
        guard Secrets.hasFlightRadarToken else { return nil }
        guard let identity = FlightIdentityParser.resolve(segment) else { return nil }
        // FR24 only has a track once the flight has actually flown.
        guard Self.isWithinTrackingReach(segment) else { return nil }

        do {
            let summaries = try await client.summaries(
                flightIata: identity.flightIata,
                from: segment.departureDate.addingTimeInterval(-24 * 3600),
                to: min(segment.departureDate.addingTimeInterval(48 * 3600), Date())
            )
            guard let summary = bestSummary(summaries, identity: identity, target: segment.departureDate),
                  let fr24ID = summary.fr24ID
            else { return nil }

            let points = try await client.flightTracks(flightID: fr24ID)
            let coords = points.compactMap { point -> RoutePoint? in
                guard let lat = point.lat, let lon = point.lon else { return nil }
                return RoutePoint(latitude: lat, longitude: lon)
            }
            return coords.count >= 2 ? coords : nil
        } catch {
            return nil
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

    /// User-initiated refresh for one leg. Honors the freeze on landed flights.
    @discardableResult
    func refresh(_ segment: TripSegment, in context: ModelContext) async -> RefreshOutcome {
        await fetch(segment, in: context, respectFreshness: false)
    }

    // MARK: Smart Auto

    /// Called on detail open when Smart Auto is enabled. Only fetches for a leg
    /// that has actually flown, has no fresh cache, and isn't already final.
    @discardableResult
    func autoRefreshIfNeeded(_ segment: TripSegment, in context: ModelContext, enabled: Bool) async -> RefreshOutcome {
        guard enabled, Secrets.hasFlightRadarToken else { return .skippedFresh }
        guard FlightIdentityParser.canTrack(segment) else { return .notTrackable }

        let existing = record(for: segment, in: context)
        if existing?.isFinal == true { return .frozen }
        guard Self.isWithinTrackingReach(segment) else { return .notYetTrackable }
        if let existing, !isStale(existing) { return .skippedFresh }

        return await fetch(segment, in: context, respectFreshness: true)
    }

    // MARK: Core fetch

    private func fetch(_ segment: TripSegment, in context: ModelContext, respectFreshness: Bool) async -> RefreshOutcome {
        guard Secrets.hasFlightRadarToken else { return .noKey }
        guard let identity = FlightIdentityParser.resolve(segment) else { return .notTrackable }

        let existing = record(for: segment, in: context)
        if existing?.isFinal == true { return .frozen }
        // FR24 only knows about flights that have flown. Calling before departure
        // is guaranteed to return nothing, so don't spend the credit.
        guard Self.isWithinTrackingReach(segment) else { return .notYetTrackable }
        if respectFreshness, let existing, !isStale(existing) { return .skippedFresh }

        do {
            let snapshot = try await resolveSnapshot(identity: identity, segment: segment)

            let rec = existing ?? {
                let r = FlightStatusRecord(segmentID: segment.id)
                context.insert(r)
                return r
            }()

            if let snapshot {
                rec.apply(snapshot, for: segment)
                try? context.save()
                return .updated
            } else {
                rec.markEmpty()
                try? context.save()
                return .noData
            }
        } catch FR24Error.insufficientCredits {
            return .insufficientCredits
        } catch FR24Error.noToken {
            return .noKey
        } catch {
            return .failed
        }
    }

    /// Compose one flight from the two endpoints that each hold half of it:
    /// positions carry telemetry but exist only while airborne; the summary
    /// carries actual takeoff/landing but no telemetry. Both are queried because a
    /// flight in the air still has a takeoff time worth showing, and neither
    /// endpoint alone can tell "hasn't departed" apart from "already landed".
    private func resolveSnapshot(identity: FlightIdentity, segment: TripSegment) async throws -> FR24Snapshot? {
        async let positionsTask = client.livePositions(flightIata: identity.flightIata)
        async let summariesTask = client.summaries(
            flightIata: identity.flightIata,
            from: segment.departureDate.addingTimeInterval(-24 * 3600),
            to: min(segment.departureDate.addingTimeInterval(48 * 3600), Date())
        )
        let (positions, summaries) = try await (positionsTask, summariesTask)

        let position = bestPosition(positions, identity: identity)
        let summary = bestSummary(summaries, identity: identity, target: segment.departureDate)

        // Neither endpoint has heard of this flight — a genuine "no data".
        guard position != nil || summary != nil else { return nil }

        let airlineICAO = position?.paintedAs ?? position?.operatingAs
            ?? summary?.paintedAs ?? summary?.operatingAs
        let airlineName = await statics.airlineName(icao: airlineICAO)

        return FR24Snapshot(
            phase: phase(position: position, summary: summary),
            flightIata: position?.flight ?? summary?.flight ?? identity.flightIata,
            airlineName: airlineName,
            takeoff: FR24Date.parse(summary?.datetimeTakeoff),
            landed: FR24Date.parse(summary?.datetimeLanded),
            eta: FR24Date.parse(position?.eta),
            position: position
        )
    }

    /// FR24 exposes no status field. The phase is inferred from which endpoint
    /// answered: airborne beats landed beats "known, but not departed yet".
    /// `.cancelled` is unreachable — FR24 publishes no cancellation data at all.
    private func phase(position: FR24Position?, summary: FR24Summary?) -> FlightPhase {
        if position != nil { return .active }
        guard let summary else { return .unknown }
        guard summary.datetimeLanded != nil else { return .scheduled }
        // Landing somewhere other than the filed destination is a diversion.
        if let planned = summary.destIata, let actual = summary.destIataActual,
           planned.uppercased() != actual.uppercased() {
            return .diverted
        }
        return .landed
    }

    /// Disambiguate codeshares: prefer the aircraft flying this leg's own route.
    private func bestPosition(_ positions: [FR24Position], identity: FlightIdentity) -> FR24Position? {
        guard !positions.isEmpty else { return nil }
        if let dep = identity.departureIata,
           let match = positions.first(where: { $0.origIata?.uppercased() == dep.uppercased() }) {
            return match
        }
        return positions.first
    }

    /// Pick the leg closest to the one the traveler actually booked: matching
    /// route first, then whichever first appeared nearest the planned departure.
    private func bestSummary(_ summaries: [FR24Summary], identity: FlightIdentity, target: Date) -> FR24Summary? {
        guard !summaries.isEmpty else { return nil }

        var pool = summaries
        if let dep = identity.departureIata {
            let matches = pool.filter { $0.origIata?.uppercased() == dep.uppercased() }
            if !matches.isEmpty { pool = matches }
        }

        return pool.min { a, b in
            let da = FR24Date.parse(a.firstSeen).map { abs($0.timeIntervalSince(target)) } ?? .greatestFiniteMagnitude
            let db = FR24Date.parse(b.firstSeen).map { abs($0.timeIntervalSince(target)) } ?? .greatestFiniteMagnitude
            return da < db
        }
    }

    // MARK: Policy helpers

    /// Whether FR24 can meaningfully answer for this leg.
    ///
    /// Where AviationStack's free tier served only today, FR24 is the opposite:
    /// strong on history (summaries back to 2022-06-01) and blind to the future —
    /// a flight doesn't exist in the API until it's in the air. So the window opens
    /// shortly before the planned departure (the hour of slack absorbs early
    /// pushbacks, and the fact that this departure time is whatever the user typed)
    /// and then never closes.
    nonisolated static func isWithinTrackingReach(_ segment: TripSegment, now: Date = Date()) -> Bool {
        guard segment.departureDate >= FR24Client.summaryFloor else { return false }
        return now >= segment.departureDate.addingTimeInterval(-3600)
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
