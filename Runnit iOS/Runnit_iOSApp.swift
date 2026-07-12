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

    init() {
        do {
            container = try ModelContainer(for: Trip.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        SampleSeeder.seedIfNeeded(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}

/// Seeds a handful of sample trips on first launch so the app isn't empty.
enum SampleSeeder {
    private static let didSeedKey = "runnit.didSeedSamples.v1"

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

    /// Starter trips shipped for a friendly first run. Uses well-known
    /// coordinates with country/locality prefilled so no geocoding is needed.
    private static func starterTrips() -> [Trip] {
        let sfo = Place(name: "San Francisco Intl (SFO)", subtitle: "San Francisco, CA",
                        latitude: 37.6213, longitude: -122.3790,
                        isoCountryCode: "US", country: "United States", locality: "San Francisco")
        let jfk = Place(name: "John F. Kennedy Intl (JFK)", subtitle: "New York, NY",
                        latitude: 40.6413, longitude: -73.7781,
                        isoCountryCode: "US", country: "United States", locality: "New York")
        let lhr = Place(name: "Heathrow (LHR)", subtitle: "London, UK",
                        latitude: 51.4700, longitude: -0.4543,
                        isoCountryCode: "GB", country: "United Kingdom", locality: "London")
        let bigSur = Place(name: "Big Sur", subtitle: "California",
                           latitude: 36.2704, longitude: -121.8081,
                           isoCountryCode: "US", country: "United States", locality: "Big Sur")
        let cdg = Place(name: "Paris–Charles de Gaulle (CDG)", subtitle: "Paris, France",
                        latitude: 49.0097, longitude: 2.5479,
                        isoCountryCode: "FR", country: "France", locality: "Paris")
        let hnd = Place(name: "Tokyo Haneda (HND)", subtitle: "Tokyo, Japan",
                        latitude: 35.5494, longitude: 139.7798,
                        isoCountryCode: "JP", country: "Japan", locality: "Tokyo")

        func daysFromNow(_ d: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: d, to: Date()) ?? Date()
        }
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
        }
        let thisYear = Calendar.current.component(.year, from: Date())

        // Upcoming — spanning this year and next, so the year pills appear.
        let upcomingFlight = Trip(
            type: .flight, origin: sfo, destination: jfk,
            departureDate: daysFromNow(6),
            arrivalDate: daysFromNow(6).addingTimeInterval(6 * 3600),
            operatorName: "United", vehicleNumber: "UA 523",
            boardingPoint: "Gate B12", seat: "14A", confirmation: "ABC123"
        )
        let upcomingRoadTrip = Trip(
            type: .roadTrip, title: "Coast Weekend",
            origin: sfo, destination: bigSur,
            departureDate: daysFromNow(15)
        )
        let upcomingNextYear = Trip(
            type: .flight, title: "Cherry Blossoms",
            origin: sfo, destination: hnd,
            departureDate: date(thisYear + 1, 4, 2),
            arrivalDate: date(thisYear + 1, 4, 3),
            operatorName: "ANA", vehicleNumber: "NH 7"
        )

        // Past — spanning a few prior years.
        let pastFlight = Trip(
            type: .flight, origin: jfk, destination: lhr,
            departureDate: daysFromNow(-40),
            arrivalDate: daysFromNow(-40).addingTimeInterval(7 * 3600),
            operatorName: "British Airways", vehicleNumber: "BA 178"
        )
        let pastLastYear = Trip(
            type: .flight, origin: sfo, destination: cdg,
            departureDate: date(thisYear - 1, 9, 12),
            arrivalDate: date(thisYear - 1, 9, 13),
            operatorName: "Air France", vehicleNumber: "AF 83"
        )
        let pastTwoYearsAgo = Trip(
            type: .train, title: "Alps Getaway",
            origin: cdg, destination: lhr,
            departureDate: date(thisYear - 2, 6, 20),
            arrivalDate: date(thisYear - 2, 6, 20).addingTimeInterval(2.5 * 3600),
            operatorName: "Eurostar", vehicleNumber: "ES 9024"
        )

        return [upcomingFlight, upcomingRoadTrip, upcomingNextYear,
                pastFlight, pastLastYear, pastTwoYearsAgo]
    }
}
