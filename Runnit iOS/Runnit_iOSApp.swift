//
//  Runnit_iOSApp.swift
//  Runnit iOS
//
//  Created by Shreyas Vasist Chandramouli on 7/11/26.
//

import SwiftUI
import SwiftData

@main
struct Runnit_iOSApp: App {
    let container: ModelContainer
    @State private var flightTracker: FlightTracker

    init() {
        do {
            container = try ModelContainer(for: Trip.self, TripSegment.self, FlightStatusRecord.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        SampleSeeder.seedIfNeeded(container.mainContext)
        SampleSeeder.backfillSegmentsIfNeeded(container.mainContext)
        SampleSeeder.seedConnectionIfNeeded(container.mainContext)
        SampleSeeder.seedFlightPathSampleIfNeeded(container.mainContext)

        _flightTracker = State(initialValue: FlightTracker())
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(flightTracker)
        }
        .modelContainer(container)
    }
}

/// Seeds a handful of sample trips on first launch so the app isn't empty.
enum SampleSeeder {
    private static let didSeedKey = "runnit.didSeedSamples.v1"
    private static let didBackfillKey = "runnit.didBackfillSegments.v1"
    private static let didSeedConnectionKey = "runnit.didSeedConnection.v1"
    private static let didSeedFlightPathKey = "runnit.didSeedFlightPathSample.v1"

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didSeedKey) else { return }

        // Only seed into a genuinely empty store.
        let count = (try? context.fetchCount(FetchDescriptor<Trip>())) ?? 0
        if count == 0 {
            for trip in SampleSeeder.starterTrips() {
                context.insert(trip)
            }
            try? context.save()
        }
        defaults.set(true, forKey: didSeedKey)
    }

    /// Additive one-time step: add the sample connecting trip (and the live
    /// snapshots that make its risk visible). Separate from `seedIfNeeded` and
    /// keyed on its own flag, because installs seeded before connections existed
    /// have already tripped that flag and would otherwise never see this trip.
    @MainActor
    static func seedConnectionIfNeeded(_ context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didSeedConnectionKey) else { return }

        let ohare = Place(name: "Chicago O'Hare (ORD)", subtitle: "Chicago, IL",
                          latitude: 41.9742, longitude: -87.9073,
                          isoCountryCode: "US", country: "United States", locality: "Chicago",
                          timeZoneIdentifier: "America/Chicago")
        let sfo = Place(name: "San Francisco Intl (SFO)", subtitle: "San Francisco, CA",
                        latitude: 37.6213, longitude: -122.3790,
                        isoCountryCode: "US", country: "United States", locality: "San Francisco",
                        timeZoneIdentifier: "America/Los_Angeles")
        let jfk = Place(name: "John F. Kennedy Intl (JFK)", subtitle: "New York, NY",
                        latitude: 40.6413, longitude: -73.7781,
                        isoCountryCode: "US", country: "United States", locality: "New York",
                        timeZoneIdentifier: "America/New_York")

        let sample = Trip.makeSampleConnection(origin: sfo, connectingAt: ohare, destination: jfk)
        context.insert(sample.trip)
        for record in sample.records {
            context.insert(record)
        }
        try? context.save()
        defaults.set(true, forKey: didSeedConnectionKey)
    }

    /// Additive one-time step: a real, recently-flown long-haul so the flown-track
    /// map feature is testable out of the box. SQ 22 (Singapore → Newark) is a
    /// daily ultra-long-haul whose near-polar great-circle path curves dramatically
    /// away from the straight airport-to-airport line — the clearest possible demo
    /// that the map is drawing the *actual* route from Flightradar24. Its own flag,
    /// so installs that already seeded still get it.
    @MainActor
    static func seedFlightPathSampleIfNeeded(_ context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didSeedFlightPathKey) else { return }

        let sin = Place(name: "Singapore Changi (SIN)", subtitle: "Singapore",
                        latitude: 1.3644, longitude: 103.9915,
                        isoCountryCode: "SG", country: "Singapore", locality: "Singapore",
                        timeZoneIdentifier: "Asia/Singapore")
        let ewr = Place(name: "Newark Liberty (EWR)", subtitle: "Newark, NJ",
                        latitude: 40.6895, longitude: -74.1745,
                        isoCountryCode: "US", country: "United States", locality: "Newark",
                        timeZoneIdentifier: "America/New_York")

        // A week ago, so FR24 has already tracked it (and it clears the 2022 floor).
        let departure = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        let trip = Trip.make(title: "Flight Path Test", segments: [
            TripSegment(
                type: .flight, origin: sin, destination: ewr,
                departureDate: departure,
                arrivalDate: departure.addingTimeInterval(18.5 * 3600),
                operatorName: "Singapore Airlines", vehicleNumber: "SQ 22"
            )
        ])
        context.insert(trip)
        for segment in trip.segments { context.insert(segment) }
        try? context.save()
        defaults.set(true, forKey: didSeedFlightPathKey)
    }

    /// One-time upgrade: give any legacy Trip (stored before multi-modal legs
    /// existed) a single segment built from its flat fields, so every trip has
    /// at least one leg going forward. Idempotent and gated by a flag.
    @MainActor
    static func backfillSegmentsIfNeeded(_ context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didBackfillKey) else { return }

        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        for trip in trips where trip.segments.isEmpty {
            let segment = TripSegment(
                type: trip.type,
                origin: trip.origin,
                destination: trip.destination,
                departureDate: trip.departureDate,
                arrivalDate: trip.arrivalDate,
                operatorName: trip.operatorName,
                vehicleNumber: trip.vehicleNumber,
                boardingPoint: trip.boardingPoint,
                seat: trip.seat,
                confirmation: trip.confirmation,
                order: 0
            )
            context.insert(segment)
            segment.trip = trip
            trip.refreshSummary()
        }
        try? context.save()
        defaults.set(true, forKey: didBackfillKey)
    }

    /// Starter trips shipped for a friendly first run. Uses well-known
    /// coordinates with country/locality prefilled so no geocoding is needed.
    private static func starterTrips() -> [Trip] {
        let sfo = Place(name: "San Francisco Intl (SFO)", subtitle: "San Francisco, CA",
                        latitude: 37.6213, longitude: -122.3790,
                        isoCountryCode: "US", country: "United States", locality: "San Francisco",
                        timeZoneIdentifier: "America/Los_Angeles")
        let jfk = Place(name: "John F. Kennedy Intl (JFK)", subtitle: "New York, NY",
                        latitude: 40.6413, longitude: -73.7781,
                        isoCountryCode: "US", country: "United States", locality: "New York",
                        timeZoneIdentifier: "America/New_York")
        let lhr = Place(name: "Heathrow (LHR)", subtitle: "London, UK",
                        latitude: 51.4700, longitude: -0.4543,
                        isoCountryCode: "GB", country: "United Kingdom", locality: "London",
                        timeZoneIdentifier: "Europe/London")
        let bigSur = Place(name: "Big Sur", subtitle: "California",
                           latitude: 36.2704, longitude: -121.8081,
                           isoCountryCode: "US", country: "United States", locality: "Big Sur",
                           timeZoneIdentifier: "America/Los_Angeles")
        let cdg = Place(name: "Paris–Charles de Gaulle (CDG)", subtitle: "Paris, France",
                        latitude: 49.0097, longitude: 2.5479,
                        isoCountryCode: "FR", country: "France", locality: "Paris",
                        timeZoneIdentifier: "Europe/Paris")
        let hnd = Place(name: "Tokyo Haneda (HND)", subtitle: "Tokyo, Japan",
                        latitude: 35.5494, longitude: 139.7798,
                        isoCountryCode: "JP", country: "Japan", locality: "Tokyo",
                        timeZoneIdentifier: "Asia/Tokyo")

        func daysFromNow(_ d: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: d, to: Date()) ?? Date()
        }
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
        }
        let thisYear = Calendar.current.component(.year, from: Date())

        // Upcoming — spanning this year and next, so the year pills appear.
        let upcomingFlight = Trip.make(segments: [
            TripSegment(
                type: .flight, origin: sfo, destination: jfk,
                departureDate: daysFromNow(6),
                arrivalDate: daysFromNow(6).addingTimeInterval(6 * 3600),
                operatorName: "United", vehicleNumber: "UA 523",
                boardingPoint: "Gate B12", seat: "14A", confirmation: "ABC123"
            )
        ])
        let upcomingRoadTrip = Trip.make(title: "Coast Weekend", segments: [
            TripSegment(type: .roadTrip, origin: sfo, destination: bigSur,
                        departureDate: daysFromNow(15))
        ])

        // A genuinely multi-modal trip: fly to London, train to Paris, drive around.
        let europeDep = daysFromNow(30)
        let multiModal = Trip.make(title: "Euro Loop", segments: [
            TripSegment(
                type: .flight, origin: sfo, destination: lhr,
                departureDate: europeDep,
                arrivalDate: europeDep.addingTimeInterval(10 * 3600),
                operatorName: "British Airways", vehicleNumber: "BA 286"
            ),
            TripSegment(
                type: .train, origin: lhr, destination: cdg,
                departureDate: europeDep.addingTimeInterval(24 * 3600),
                arrivalDate: europeDep.addingTimeInterval(24 * 3600 + 2.5 * 3600),
                operatorName: "Eurostar", vehicleNumber: "ES 9024"
            ),
            TripSegment(
                type: .roadTrip, origin: cdg, destination: bigSur,
                departureDate: europeDep.addingTimeInterval(4 * 24 * 3600)
            )
        ])

        let upcomingNextYear = Trip.make(title: "Cherry Blossoms", segments: [
            TripSegment(type: .flight, origin: sfo, destination: hnd,
                        departureDate: date(thisYear + 1, 4, 2),
                        arrivalDate: date(thisYear + 1, 4, 3),
                        operatorName: "ANA", vehicleNumber: "NH 7")
        ])

        // Past — spanning a few prior years.
        let pastFlight = Trip.make(segments: [
            TripSegment(type: .flight, origin: jfk, destination: lhr,
                        departureDate: daysFromNow(-40),
                        arrivalDate: daysFromNow(-40).addingTimeInterval(7 * 3600),
                        operatorName: "British Airways", vehicleNumber: "BA 178")
        ])
        let pastLastYear = Trip.make(segments: [
            TripSegment(type: .flight, origin: sfo, destination: cdg,
                        departureDate: date(thisYear - 1, 9, 12),
                        arrivalDate: date(thisYear - 1, 9, 13),
                        operatorName: "Air France", vehicleNumber: "AF 83")
        ])
        let pastTwoYearsAgo = Trip.make(title: "Alps Getaway", segments: [
            TripSegment(type: .train, origin: cdg, destination: lhr,
                        departureDate: date(thisYear - 2, 6, 20),
                        arrivalDate: date(thisYear - 2, 6, 20).addingTimeInterval(2.5 * 3600),
                        operatorName: "Eurostar", vehicleNumber: "ES 9024")
        ])

        return [upcomingFlight, upcomingRoadTrip, multiModal, upcomingNextYear,
                pastFlight, pastLastYear, pastTwoYearsAgo]
    }
}
