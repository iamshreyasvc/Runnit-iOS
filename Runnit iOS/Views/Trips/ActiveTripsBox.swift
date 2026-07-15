//
//  ActiveTripsBox.swift
//  Runnit iOS
//
//  The Upcoming tab's "right now" box, sitting under the map. It exists only
//  while something is actually happening — a leg under way, a layover ticking, a
//  departure inside its lead time — and vanishes entirely otherwise, so the tab
//  reads exactly as it did before on any ordinary day.
//
//  Each row is the short form of the trip's live card: what you're doing, when it
//  ends, and how late that is. Tap it to open the trip. Cache-only, like the card
//  itself — it reads snapshots, it never fetches.
//

import SwiftUI
import SwiftData

struct ActiveTripsBox: View {
    let trips: [Trip]
    /// When embedded inside another card (the map card), the box drops its own
    /// glass chrome and attaches with a hairline divider instead.
    var embedded: Bool = false
    let onSelect: (Trip) -> Void

    @Query private var records: [FlightStatusRecord]

    var body: some View {
        // Same slow tick as the detail card: progress creeps, countdowns count,
        // and a trip that ends drops out of the box on its own.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let active = live(at: context.date)
            if !active.isEmpty {
                box(active)
            }
        }
    }

    /// The trips happening now, soonest-ending first, each with its live reading.
    private func live(at now: Date) -> [(trip: Trip, status: TripStatus)] {
        trips
            .compactMap { trip in
                TripStatus(trip: trip, records: records, now: now).map { (trip, $0) }
            }
            .sorted { ($0.status.timeRemaining ?? 0) < ($1.status.timeRemaining ?? 0) }
    }

    @ViewBuilder
    private func box(_ active: [(trip: Trip, status: TripStatus)]) -> some View {
        let content = VStack(alignment: .leading, spacing: 14) {
            if embedded {
                Divider()
            }
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TripType.flight.accent)
                Text("Happening Now")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if active.count > 1 {
                    Text("\(active.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(active.enumerated()), id: \.element.trip.id) { index, entry in
                if index > 0 { Divider() }
                Button {
                    onSelect(entry.trip)
                } label: {
                    row(entry.trip, status: entry.status)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if embedded {
            content
        } else {
            content
                .glassCard(tint: (active.first?.status.tint ?? TripType.flight.accent).opacity(0.25))
        }
    }

    private func row(_ trip: Trip, status: TripStatus) -> some View {
        let ends = status.endpoints
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: status.puckIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(status.tint.gradient, in: .circle)

                VStack(alignment: .leading, spacing: 1) {
                    Text(status.headline)
                        .font(.subheadline.weight(.semibold))
                    Text(trip.displayTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    let (text, color) = status.punctuality
                    Text(text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                    if let countdown = status.countdown {
                        Text(countdown)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            TripProgressTrack(progress: status.progress, icon: status.puckIcon,
                              tint: status.tint, compact: true)

            HStack {
                Text(ends.start.code)
                Spacer()
                if let time = ends.end.time {
                    Text("\(ends.end.title) \(Format.time(time, in: ends.end.zone))")
                        .foregroundStyle(ends.end.isLate ? .orange : .secondary)
                }
                Spacer()
                Text(ends.end.code)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .contentShape(.rect)
    }
}

#if DEBUG
#Preview {
    ScrollView {
        ActiveTripsBox(trips: [.sampleConnection], onSelect: { _ in })
    }
    .modelContainer(PreviewData.container)
}
#endif
