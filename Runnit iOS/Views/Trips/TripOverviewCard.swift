//
//  TripOverviewCard.swift
//  Runnit iOS
//
//  The consolidated summary at the top of a trip's detail: the whole journey's
//  route and times in the same boarding-pass language as the list cards, plus a
//  compact row of the metrics that matter most (status, distance, duration, legs).
//

import SwiftUI
import SwiftData

struct TripOverviewCard: View {
    let trip: Trip

    var body: some View {
        VStack(spacing: 16) {
            routeRow
            Divider()
            metricsRow
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: Route

    private var routeRow: some View {
        HStack(alignment: .top, spacing: 10) {
            endpoint(place: trip.startPlace, time: departureTime,
                     date: departureDate, alignment: .leading)
            connector
            endpoint(place: trip.endPlace, time: arrivalTime,
                     date: arrivalDate, alignment: .trailing)
        }
    }

    private func endpoint(place: Place, time: String?, date: String?,
                          alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(place.codeLabel)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let time {
                Text(time).font(.subheadline.weight(.medium))
            }
            if let date {
                Text(date).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private var connector: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                DashedLine().stroke(.tertiary, style: dashStyle).frame(height: 1)
                Image(systemName: trip.type.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(trip.type.accent)
                DashedLine().stroke(.tertiary, style: dashStyle).frame(height: 1)
            }
            .frame(height: 16)
            if let stops = stopsLine {
                Text(stops).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var dashStyle: StrokeStyle { StrokeStyle(lineWidth: 1.5, dash: [2, 3]) }

    // MARK: Metrics

    private var metricsRow: some View {
        HStack(spacing: 8) {
            metric(statusIcon, statusValue, "Status", statusTint)
            metric("ruler", Format.distance(trip.distanceMeters), "Distance", .blue)
            if let duration = durationValue {
                metric("timer", duration, "Duration", .orange)
            }
            if trip.isMultiModal {
                metric("point.topleft.down.to.point.bottomright.curvepath",
                       "\(trip.legCount)", "Legs", trip.type.accent)
            }
        }
    }

    private func metric(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.callout).foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Derived values

    private var departureTime: String? {
        Format.time(trip.startDate, in: trip.startPlace.timeZone)
    }

    private var departureDate: String? {
        Format.date(trip.startDate, in: trip.startPlace.timeZone)
    }

    private var lastArrival: Date? { trip.displaySegments.last?.arrivalDate }

    private var arrivalTime: String? {
        lastArrival.map { Format.time($0, in: trip.endPlace.timeZone) }
    }

    private var arrivalDate: String? {
        lastArrival.map { Format.date($0, in: trip.endPlace.timeZone) }
    }

    private var durationValue: String? {
        guard let arrival = lastArrival, arrival > trip.startDate else { return nil }
        return Format.duration(arrival.timeIntervalSince(trip.startDate))
    }

    private var statusValue: String {
        trip.isPast ? "Completed" : Format.relative(trip.startDate)
    }

    private var statusIcon: String { trip.isPast ? "checkmark.circle" : "clock" }
    private var statusTint: Color { trip.isPast ? .secondary : trip.type.accent }

    /// "1 stop · ORD" for a connecting flight, or "2 stops" for road-trip stops.
    private var stopsLine: String? {
        let pairs = trip.connectionPairs
        if !pairs.isEmpty {
            let count = "\(pairs.count) stop\(pairs.count == 1 ? "" : "s")"
            let airports = pairs.map { $0.outbound.origin.codeLabel }
            return ([count] + airports).joined(separator: " · ")
        }
        let roadStops = trip.displaySegments.reduce(into: 0) { $0 += $1.stops.count }
        return roadStops > 0 ? "\(roadStops) stop\(roadStops == 1 ? "" : "s")" : nil
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 16) {
            TripOverviewCard(trip: .sampleFlight)
            TripOverviewCard(trip: .sampleMultiModal)
        }
        .padding()
    }
    .modelContainer(PreviewData.container)
}
#endif
