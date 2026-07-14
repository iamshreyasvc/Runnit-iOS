//
//  ConnectionStrip.swift
//  Runnit iOS
//
//  The compact form of a connection, for the trip editors: how long you have on
//  the ground and whether that's workable. Unlike ConnectionCardView this reads
//  no live status — it judges the itinerary as planned, which is exactly what
//  you want while you're still typing it in.
//

import SwiftUI

struct ConnectionStrip: View {
    let connection: Connection

    private var risk: ConnectionRisk { connection.risk }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.swap")
                .font(.footnote.weight(.bold))
                .foregroundStyle(risk.color)
                .frame(width: 32, height: 32)
                .background(risk.color.opacity(0.16), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect at \(connection.airport.displayName)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let layover = connection.effectiveLayover, layover > 0 {
                Text(Format.duration(layover))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(risk.color)
            } else {
                Text(risk.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(risk.color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(risk.color.opacity(0.16), in: .capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the traveler needs to know at a glance, while still editing.
    private var detail: String {
        switch risk {
        case .unknown:
            return "Add an arrival time to the previous leg to check this layover."
        case .missed:
            return "This flight leaves before the previous one lands."
        case .atRisk:
            return "Under the \(connection.requiredMinutes) min this connection needs."
        case .tight:
            return "Workable, but there's not much slack."
        case .comfortable:
            return "Plenty of time on the ground."
        case .cancelled:
            return risk.message
        }
    }
}

#if DEBUG
#Preview {
    let sfo = Place.sfo, ord = Place.ord, jfk = Place.jfk
    let base = Date()
    func leg(_ from: Place, _ to: Place, _ dep: Double, _ arr: Double) -> TripSegment {
        TripSegment(type: .flight, origin: from, destination: to,
                    departureDate: base.addingTimeInterval(dep * 3600),
                    arrivalDate: base.addingTimeInterval(arr * 3600))
    }
    return VStack(spacing: 20) {
        // Comfortable: 3 h on the ground.
        ConnectionStrip(connection: Connection(inbound: leg(sfo, ord, 0, 4),
                                               outbound: leg(ord, jfk, 7, 9)))
        // At risk: 25 min.
        ConnectionStrip(connection: Connection(inbound: leg(sfo, ord, 0, 4),
                                               outbound: leg(ord, jfk, 4.42, 6)))
        // Missed: leaves before it lands.
        ConnectionStrip(connection: Connection(inbound: leg(sfo, ord, 0, 4),
                                               outbound: leg(ord, jfk, 3, 5)))
        // Unknown: no arrival on the inbound.
        ConnectionStrip(connection: Connection(
            inbound: TripSegment(type: .flight, origin: sfo, destination: ord, departureDate: base),
            outbound: leg(ord, jfk, 7, 9)))
    }
    .padding()
}
#endif
