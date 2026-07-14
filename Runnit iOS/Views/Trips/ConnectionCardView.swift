//
//  ConnectionCardView.swift
//  Runnit iOS
//
//  The card for a connecting airport. It answers, in order: do I make it, why,
//  where do I have to get to, and by when. Cache-only — it reads whatever live
//  snapshots FlightStatusCardView has already fetched and never calls the API
//  itself, so appearing between two leg cards costs nothing.
//

import SwiftUI
import SwiftData

struct ConnectionCardView: View {
    let inbound: TripSegment
    let outbound: TripSegment

    @Query private var records: [FlightStatusRecord]

    init(inbound: TripSegment, outbound: TripSegment) {
        self.inbound = inbound
        self.outbound = outbound
        let inID = inbound.id
        let outID = outbound.id
        _records = Query(filter: #Predicate<FlightStatusRecord> {
            $0.segmentID == inID || $0.segmentID == outID
        })
    }

    private var connection: Connection {
        Connection(inbound: inbound, outbound: outbound, records: records)
    }

    var body: some View {
        let connection = self.connection
        let risk = connection.risk

        VStack(alignment: .leading, spacing: 12) {
            headline(connection, risk: risk)
            Text(connection.advisory)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            transferRow(connection, risk: risk)
            Divider()
            timesRow(connection)

            Label("Connect at \(connection.airport.name)", systemImage: "arrow.triangle.swap")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: risk.color.opacity(0.22))
    }

    // MARK: Headline — the verdict and how long you actually have.

    private func headline(_ connection: Connection, risk: ConnectionRisk) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(risk.label, systemImage: risk.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(risk.color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(risk.color.opacity(0.15), in: .capsule)

            Spacer(minLength: 0)

            if let effective = connection.effectiveLayover, effective > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Format.duration(effective))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(risk.color)
                    if connection.didLayoverChange, let scheduled = connection.scheduledLayover,
                       scheduled > 0 {
                        Text(Format.duration(scheduled))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .strikethrough()
                    }
                }
            }
        }
    }

    // MARK: Transfer — the core: where you land, where you need to be.

    private func transferRow(_ connection: Connection, risk: ConnectionRisk) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                gateStack(title: "Arrive",
                          terminal: connection.arrivalTerminal,
                          gate: connection.arrivalGate,
                          tint: TripType.flight.accent)
                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                gateStack(title: "Depart",
                          terminal: connection.departureTerminal,
                          gate: connection.departureGate,
                          tint: TripType.flight.accent)
                Spacer(minLength: 0)
            }

            if connection.isTerminalChange {
                InfoChip("Terminal change", "allow \(connection.requiredMinutes) min", tint: .orange)
            }
        }
    }

    private func gateStack(title: String, terminal: String?, gate: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if terminal == nil && gate == nil {
                Text("Not assigned yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 6) {
                    if let terminal { InfoChip("Terminal", terminal, tint: tint) }
                    if let gate { InfoChip("Gate", gate, tint: tint) }
                }
            }
        }
    }

    // MARK: Times

    private func timesRow(_ connection: Connection) -> some View {
        let zone = connection.timeZone
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                timeStack(title: "Arrives",
                          effective: connection.effectiveArrival,
                          scheduled: connection.scheduledArrival,
                          isLate: (connection.inboundDelayMinutes ?? 0) > 0,
                          zone: zone)
                Spacer()
                timeStack(title: "Departs",
                          effective: connection.effectiveDeparture,
                          scheduled: connection.scheduledDeparture,
                          isLate: false,
                          zone: zone)
            }
            // One clock for the whole layover: the one on the wall at the hub.
            if let label = Format.zone(zone, at: connection.effectiveDeparture) {
                Text("Times shown in \(label) — local at \(connection.airport.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func timeStack(title: String, effective: Date?, scheduled: Date?,
                           isLate: Bool, zone: TimeZone?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let effective {
                Text(Format.dateTime(effective, in: zone))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isLate ? .orange : .primary)
                if let scheduled, abs(effective.timeIntervalSince(scheduled)) > 60 {
                    Text(Format.dateTime(scheduled, in: zone))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                }
            } else {
                Text("—").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
#Preview("At risk") {
    ScrollView {
        if let pair = Trip.sampleConnection.connectionPairs.first {
            ConnectionCardView(inbound: pair.inbound, outbound: pair.outbound)
                .padding()
        }
    }
    .modelContainer(PreviewData.container)
}
#endif
