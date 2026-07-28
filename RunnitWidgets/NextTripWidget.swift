//
//  NextTripWidget.swift
//  RunnitWidgets
//
//  The Home Screen and Lock Screen widget: the trip that matters next, with a live
//  countdown. Data comes from the App Group snapshot the app publishes
//  (WidgetSnapshotWriter) — the widget never touches SwiftData.
//

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct NextTripEntry: TimelineEntry {
    let date: Date
    let snapshot: TripWidgetSnapshot

    /// The trip to feature at this entry's moment: an underway trip wins, else the
    /// soonest one that hasn't departed yet, else whatever's first.
    var featured: TripWidgetSnapshot.Entry? {
        if let live = snapshot.trips.first(where: \.isUnderway) { return live }
        if let next = snapshot.trips.first(where: { $0.departureDate > date }) { return next }
        return snapshot.trips.first
    }
}

struct NextTripProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextTripEntry {
        NextTripEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextTripEntry) -> Void) {
        completion(NextTripEntry(date: Date(), snapshot: TripWidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextTripEntry>) -> Void) {
        let snapshot = TripWidgetSnapshot.load()
        let now = Date()

        // Refresh points: now, plus each future departure/arrival so the featured
        // trip rolls forward as legs come and go. Countdowns between these update
        // themselves via live Text, so a sparse timeline is plenty.
        var dates: Set<Date> = [now]
        for trip in snapshot.trips {
            if trip.departureDate > now { dates.insert(trip.departureDate) }
            if let arrival = trip.arrivalDate, arrival > now { dates.insert(arrival) }
        }
        let sorted = dates.sorted().prefix(12)
        let entries = sorted.map { NextTripEntry(date: $0, snapshot: snapshot) }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget

struct NextTripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RunnitNextTrip", provider: NextTripProvider()) { entry in
            NextTripView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Trip")
        .description("Your next trip and a live countdown.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryCircular, .accessoryInline
        ])
    }
}

// MARK: - Views

struct NextTripView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextTripEntry

    var body: some View {
        if let trip = entry.featured {
            switch family {
            case .systemSmall:         small(trip)
            case .systemMedium:        medium(trip)
            case .accessoryRectangular: rectangular(trip)
            case .accessoryCircular:    circular(trip)
            case .accessoryInline:      inline(trip)
            default:                    small(trip)
            }
        } else {
            emptyState
        }
    }

    // MARK: System (Home Screen)

    private func small(_ trip: TripWidgetSnapshot.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: trip.mode.symbol)
                    .font(.headline).foregroundStyle(trip.mode.color)
                Spacer()
                if trip.isUnderway {
                    Text("LIVE").font(.caption2.weight(.black)).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 0)
            Text("\(trip.originCode) → \(trip.destinationCode)")
                .font(.headline.weight(.bold))
                .minimumScaleFactor(0.7).lineLimit(1)
            statusLine(trip).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ trip: TripWidgetSnapshot.Entry) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: trip.mode.symbol).foregroundStyle(trip.mode.color)
                    Text(trip.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Text("\(trip.originName) → \(trip.destinationName)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                statusLine(trip).font(.callout.weight(.semibold)).foregroundStyle(trip.mode.color)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(trip.originCode).font(.title3.weight(.heavy))
                Image(systemName: "arrow.down").font(.caption2).foregroundStyle(.secondary)
                Text(trip.destinationCode).font(.title3.weight(.heavy))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Accessory (Lock Screen)

    private func rectangular(_ trip: TripWidgetSnapshot.Entry) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text("\(trip.originCode) → \(trip.destinationCode)").fontWeight(.semibold)
            } icon: {
                Image(systemName: trip.mode.symbol)
            }
            .font(.caption)
            statusLine(trip).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func circular(_ trip: TripWidgetSnapshot.Entry) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: trip.mode.symbol).font(.caption)
                if trip.isUnderway {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 8))
                } else {
                    Text(trip.departureDate, style: .relative)
                        .font(.system(size: 9)).minimumScaleFactor(0.5).lineLimit(1)
                }
            }
        }
    }

    private func inline(_ trip: TripWidgetSnapshot.Entry) -> some View {
        Label {
            if trip.isUnderway {
                Text("\(trip.originCode)→\(trip.destinationCode) · \(trip.headline ?? "Underway")")
            } else {
                Text("\(trip.originCode)→\(trip.destinationCode) · \(trip.departureDate, style: .relative)")
            }
        } icon: {
            Image(systemName: trip.mode.symbol)
        }
    }

    // MARK: Shared

    @ViewBuilder
    private func statusLine(_ trip: TripWidgetSnapshot.Entry) -> some View {
        if trip.isUnderway {
            Text(trip.headline ?? "Underway")
        } else if trip.departureDate > entry.date {
            Text("in ") + Text(trip.departureDate, style: .relative)
        } else {
            Text(trip.departureDate, style: .date)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "airplane.departure").font(.title3).foregroundStyle(.secondary)
            Text("No upcoming trips").font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Placeholder data

extension TripWidgetSnapshot {
    static let placeholder = TripWidgetSnapshot(
        generatedAt: Date(),
        trips: [
            Entry(tripID: "placeholder",
                  title: "Weekend in New York",
                  originCode: "SFO", destinationCode: "JFK",
                  originName: "San Francisco", destinationName: "New York",
                  mode: .flight,
                  departureDate: Date().addingTimeInterval(3 * 24 * 3600),
                  arrivalDate: Date().addingTimeInterval(3 * 24 * 3600 + 6 * 3600),
                  isUnderway: false, headline: nil)
        ]
    )
}
