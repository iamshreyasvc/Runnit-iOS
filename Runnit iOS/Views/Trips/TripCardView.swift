//
//  TripCardView.swift
//  Runnit iOS
//
//  Liquid Glass card summarizing one trip in the list.
//

import SwiftUI

struct TripCardView: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: trip.type.symbol)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(trip.type.gradient, in: .circle)

                VStack(alignment: .leading, spacing: 1) {
                    Text(trip.type.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trip.type.accent)
                    if let number = trip.vehicleNumber, !number.isEmpty {
                        Text(number)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                statusPill
            }

            routeRow

            HStack {
                Label(Format.date(trip.departureDate), systemImage: "calendar")
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

    private var routeRow: some View {
        HStack(alignment: .center, spacing: 8) {
            endpoint(trip.origin.displayName)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
            endpoint(trip.destination.displayName)
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
        Text(Format.relative(trip.departureDate))
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
            TripCardView(trip: .sampleRoadTrip)
        }
        .padding()
    }
    .background(.blue.opacity(0.1))
}
#endif
