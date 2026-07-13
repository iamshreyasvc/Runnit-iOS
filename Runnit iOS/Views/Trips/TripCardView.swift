//
//  TripCardView.swift
//  Runnit iOS
//
//  Liquid Glass card summarizing one trip in the list. Multi-modal trips show a
//  mode-icon chain, the overall route, and a leg summary.
//

import SwiftUI

struct TripCardView: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                modeChain

                VStack(alignment: .leading, spacing: 1) {
                    Text(headline)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trip.type.accent)
                    if let sub = subheadline {
                        Text(sub)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                statusPill
            }

            routeRow

            HStack {
                Label(Format.date(trip.startDate), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Format.distance(trip.distanceMeters))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard(tint: trip.type.accent.opacity(0.28))
    }

    // MARK: Header

    /// A single mode circle for simple trips, or a chain of small mode icons
    /// (e.g. ✈ → 🚆 → 🚗) for multi-modal trips.
    @ViewBuilder
    private var modeChain: some View {
        if trip.isMultiModal {
            HStack(spacing: -6) {
                ForEach(Array(trip.modeSequence.enumerated()), id: \.offset) { _, mode in
                    Image(systemName: mode.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(mode.gradient, in: .circle)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                }
            }
        } else {
            Image(systemName: trip.type.symbol)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(trip.type.gradient, in: .circle)
        }
    }

    private var headline: String {
        trip.isMultiModal ? "\(trip.legCount) legs" : trip.type.label
    }

    private var subheadline: String? {
        if trip.isMultiModal {
            return trip.modeSequence.map(\.label).joined(separator: " · ")
        }
        if let number = trip.vehicleNumber, !number.isEmpty {
            return number
        }
        return nil
    }

    private var routeRow: some View {
        HStack(alignment: .center, spacing: 8) {
            endpoint(trip.startPlace.displayName)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
            endpoint(trip.endPlace.displayName)
            Spacer(minLength: 0)
        }
    }

    private func endpoint(_ text: String) -> some View {
        Text(text)
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var statusPill: some View {
        Text(Format.relative(trip.startDate))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(trip.isPast ? .secondary : trip.type.accent)
            .background(
                (trip.isPast ? Color.secondary : trip.type.accent).opacity(0.15),
                in: .capsule
            )
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 16) {
            TripCardView(trip: .sampleFlight)
            TripCardView(trip: .sampleMultiModal)
            TripCardView(trip: .sampleRoadTrip)
        }
        .padding()
    }
    .background(.blue.opacity(0.1))
}
#endif
