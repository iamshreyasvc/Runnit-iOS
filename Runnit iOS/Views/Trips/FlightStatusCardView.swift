//
//  FlightStatusCardView.swift
//  Runnit iOS
//
//  Live flight status for a single .flight leg, backed by a cached
//  FlightStatusRecord and refreshed through FlightTracker (never directly).
//  Adapts to phase: upcoming (gates/terminals/times/delays), in-air (live map +
//  altitude/speed), and landed (actual times + "Landed"). Degrades gracefully
//  when there's no key, no flight number, or no data — always without surprise
//  API calls.
//

import SwiftUI
import SwiftData
import MapKit

struct FlightStatusCardView: View {
    let segment: TripSegment
    /// When true, render without the surrounding glass card (for nesting inside
    /// an existing card, e.g. a multi-leg disclosure row).
    var embedded: Bool = false

    @Environment(FlightTracker.self) private var tracker
    @Environment(APIUsageTracker.self) private var usage
    @Environment(\.modelContext) private var context
    @AppStorage(PrefKey.flightAutoRefresh) private var autoRefresh = false

    @Query private var records: [FlightStatusRecord]
    @State private var isRefreshing = false
    @State private var lastOutcome: RefreshOutcome?

    init(segment: TripSegment, embedded: Bool = false) {
        self.segment = segment
        self.embedded = embedded
        let id = segment.id
        _records = Query(filter: #Predicate<FlightStatusRecord> { $0.segmentID == id })
    }

    private var record: FlightStatusRecord? { records.first }
    private var canTrack: Bool { FlightIdentityParser.canTrack(segment) }
    private var accent: Color { segment.type.accent }
    private var withinReach: Bool { FlightTracker.isWithinRealtimeReach(segment) }

    /// The record only when it should actually drive the UI: a captured final
    /// snapshot is always valid; live/scheduled data is only shown when the flight
    /// is within real-time reach (so we never show another day's instance).
    private var displayRecord: FlightStatusRecord? {
        guard let r = record, r.didFindData else { return nil }
        if r.isFinal { return r }
        // Live/scheduled data is only trustworthy when it's within reach AND was
        // actually captured today — never show a prior day's snapshot as current.
        guard withinReach, Calendar.current.isDateInToday(r.fetchedAt) else { return nil }
        return r
    }

    private var reachMessage: String {
        if segment.departureDate > Date() {
            return "Live gate, terminal, and tracking become available on the day of departure (\(Format.date(segment.departureDate))). On the free plan, real-time data can't be fetched earlier."
        }
        return "Live data isn't available for past flights on the free plan — only same-day flights can be tracked live."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !embedded { header }
            content
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardChrome(embedded: embedded, tint: accent.opacity(0.22)))
        .task(id: segment.id) {
            await tracker.autoRefreshIfNeeded(segment, in: context, enabled: autoRefresh)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "airplane")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(accent.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text("Flight Status").font(.caption2).foregroundStyle(.secondary)
                Text(record?.airlineName ?? segment.operatorName ?? segment.vehicleNumber ?? "Flight")
                    .font(.headline)
            }
            Spacer()
            if let r = displayRecord { statusPill(for: r) }
        }
    }

    @ViewBuilder
    private func statusPill(for record: FlightStatusRecord) -> some View {
        let (text, color) = statusStyle(record)
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: .capsule)
    }

    private func statusStyle(_ record: FlightStatusRecord) -> (String, Color) {
        switch record.phase {
        case .landed:                       return ("Landed", .green)
        case .cancelled:                    return ("Cancelled", .red)
        case .diverted:                     return ("Diverted", .orange)
        case .incident:                     return ("Incident", .red)
        case .active:                       return ("In the air", accent)
        case .scheduled, .unknown:
            if let d = record.depDelayMinutes, d > 0 { return ("Delayed \(d)m", .orange) }
            return (record.phase == .unknown ? "Scheduled" : "On time", accent)
        }
    }

    // MARK: Content (phase-aware)

    @ViewBuilder
    private var content: some View {
        if !canTrack {
            hint("Add a flight number like \u{201C}UA 523\u{201D} to this leg to enable live tracking.")
        } else if !Secrets.hasAviationStackKey {
            hint("Live tracking is off. Add your AviationStack API key (see the Account tab) to enable it.")
        } else if let r = displayRecord {
            switch r.phase {
            case .active:                       liveBody(r)
            case .landed, .diverted:            landedBody(r)
            default:                            upcomingBody(r)
            }
        } else if !withinReach {
            hint(reachMessage)
        } else if record?.didFindData == false {
            hint("No live data found for this flight today. The number may not match an airline schedule.")
        } else {
            hint("Tap Refresh to load live gate, terminal, and timing details.")
        }
    }

    // Upcoming: gates, terminals, scheduled vs estimated, delays.
    private func upcomingBody(_ r: FlightStatusRecord) -> some View {
        VStack(spacing: 12) {
            endpointRow(title: "Departs", airport: segment.origin,
                        terminal: r.depTerminal, gate: r.depGate ?? segment.boardingPoint,
                        scheduled: r.depScheduled ?? segment.departureDate,
                        estimated: r.depEstimated, delay: r.depDelayMinutes)
            Divider()
            endpointRow(title: "Arrives", airport: segment.destination,
                        terminal: r.arrTerminal, gate: r.arrGate,
                        scheduled: r.arrScheduled ?? segment.arrivalDate,
                        estimated: r.arrEstimated, delay: r.arrDelayMinutes,
                        baggage: r.arrBaggage)
        }
    }

    // Landed / past: actual times and a settled status.
    private func landedBody(_ r: FlightStatusRecord) -> some View {
        VStack(spacing: 12) {
            endpointRow(title: "Departed", airport: segment.origin,
                        terminal: r.depTerminal, gate: r.depGate,
                        scheduled: r.depScheduled, actual: r.depActual)
            Divider()
            endpointRow(title: "Arrived", airport: segment.destination,
                        terminal: r.arrTerminal, gate: r.arrGate,
                        scheduled: r.arrScheduled, actual: r.arrActual,
                        baggage: r.arrBaggage)
        }
    }

    // In the air: live map + telemetry.
    @ViewBuilder
    private func liveBody(_ r: FlightStatusRecord) -> some View {
        VStack(spacing: 12) {
            if let coord = r.liveCoordinate {
                liveMap(coord: coord, heading: r.liveDirection ?? 0)
                    .frame(height: 150)
                    .clipShape(.rect(cornerRadius: 16))
            }
            HStack(spacing: 12) {
                telemetry("Altitude", altitudeText(r.liveAltitude), "arrow.up.to.line")
                telemetry("Ground speed", speedText(r.liveSpeed), "gauge.with.dots.needle.67percent")
                telemetry("Heading", headingText(r.liveDirection), "location.north.line")
            }
            Divider()
            endpointRow(title: "Departed", airport: segment.origin,
                        terminal: r.depTerminal, gate: r.depGate,
                        scheduled: r.depScheduled, actual: r.depActual)
            endpointRow(title: "Arrives", airport: segment.destination,
                        terminal: r.arrTerminal, gate: r.arrGate,
                        scheduled: r.arrScheduled, estimated: r.arrEstimated,
                        delay: r.arrDelayMinutes, baggage: r.arrBaggage)
        }
    }

    private func liveMap(coord: CLLocationCoordinate2D, heading: Double) -> some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)
        ))) {
            Annotation("", coordinate: coord) {
                Image(systemName: "airplane")
                    .font(.title3)
                    .foregroundStyle(accent)
                    .rotationEffect(.degrees(heading - 90))
                    .shadow(radius: 3)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .disabled(true)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            if let r = displayRecord {
                Label(updatedText(r.fetchedAt), systemImage: "clock.arrow.circlepath")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            refreshControl
        }
    }

    @ViewBuilder
    private var refreshControl: some View {
        if !canTrack || !Secrets.hasAviationStackKey || !withinReach {
            EmptyView()
        } else if displayRecord?.isFinal == true {
            Label("Final", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        } else if usage.isExhausted {
            Label("Monthly limit reached", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        } else {
            Button {
                Task { await refresh() }
            } label: {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.glass)
            .disabled(isRefreshing)
        }
    }

    private func refresh() async {
        isRefreshing = true
        lastOutcome = await tracker.refresh(segment, in: context)
        isRefreshing = false
    }

    // MARK: Building blocks

    private func endpointRow(
        title: String, airport: Place,
        terminal: String?, gate: String?,
        scheduled: Date?, estimated: Date? = nil, actual: Date? = nil,
        delay: Int? = nil, baggage: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                timeStack(scheduled: scheduled, estimated: estimated, actual: actual)
            }
            Text(airport.name).font(.subheadline.weight(.semibold))

            let chips: [(String, String)] = [
                terminal.map { ("Terminal", $0) },
                gate.map { ("Gate", $0) },
                baggage.map { ("Baggage", $0) },
            ].compactMap { $0 }

            if !chips.isEmpty || (delay ?? 0) > 0 {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.0) { chip in
                        infoChip(chip.0, chip.1, tint: accent)
                    }
                    if let delay, delay > 0 {
                        infoChip("Delay", "+\(delay)m", tint: .orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func timeStack(scheduled: Date?, estimated: Date?, actual: Date?) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            if let actual {
                Text(Format.dateTime(actual)).font(.caption.weight(.semibold))
                if let scheduled, abs(actual.timeIntervalSince(scheduled)) > 60 {
                    Text(Format.dateTime(scheduled))
                        .font(.caption2).foregroundStyle(.secondary).strikethrough()
                }
            } else if let estimated {
                Text(Format.dateTime(estimated)).font(.caption.weight(.semibold))
                    .foregroundStyle(scheduled.map { abs(estimated.timeIntervalSince($0)) > 60 } == true ? .orange : .primary)
                if let scheduled, abs(estimated.timeIntervalSince(scheduled)) > 60 {
                    Text(Format.dateTime(scheduled))
                        .font(.caption2).foregroundStyle(.secondary).strikethrough()
                }
            } else if let scheduled {
                Text(Format.dateTime(scheduled)).font(.caption.weight(.semibold))
            } else {
                Text("—").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func infoChip(_ label: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
        }
        .font(.caption2)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.14), in: .capsule)
    }

    private func telemetry(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundStyle(accent)
            Text(value).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Formatting

    private func altitudeText(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        let feet = meters * 3.28084
        return "\(Int((feet / 100).rounded()) * 100) ft"
    }
    private func speedText(_ kmh: Double?) -> String {
        guard let kmh else { return "—" }
        return "\(Int(kmh.rounded())) km/h"
    }
    private func headingText(_ deg: Double?) -> String {
        guard let deg else { return "—" }
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return dirs[Int((deg / 45).rounded()) % 8]
    }
    private func updatedText(_ date: Date) -> String {
        let secs = Date().timeIntervalSince(date)
        if secs < 60 { return "Updated just now" }
        return "Updated \(Format.duration(secs)) ago"
    }
}

/// Applies the glass card chrome only when not embedded.
private struct CardChrome: ViewModifier {
    let embedded: Bool
    let tint: Color
    func body(content: Content) -> some View {
        if embedded { content } else { content.glassCard(tint: tint) }
    }
}

/// A compact, reactive status line for a leg — used as the collapsed header of a
/// multi-leg flight in the itinerary. Cache-only; never triggers a fetch.
struct FlightStatusChip: View {
    let segment: TripSegment
    @Query private var records: [FlightStatusRecord]

    init(segment: TripSegment) {
        self.segment = segment
        let id = segment.id
        _records = Query(filter: #Predicate<FlightStatusRecord> { $0.segmentID == id })
    }

    var body: some View {
        if let r = records.first, r.didFindData,
           r.isFinal || FlightTracker.isWithinRealtimeReach(segment) {
            let (text, color) = style(r)
            HStack(spacing: 6) {
                Text(text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.15), in: .capsule)
                if let line = detailLine(r) {
                    Text(line).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private func style(_ r: FlightStatusRecord) -> (String, Color) {
        switch r.phase {
        case .landed:    return ("Landed", .green)
        case .cancelled: return ("Cancelled", .red)
        case .active:    return ("In the air", segment.type.accent)
        default:
            if let d = r.depDelayMinutes, d > 0 { return ("Delayed \(d)m", .orange) }
            return ("On time", segment.type.accent)
        }
    }

    private func detailLine(_ r: FlightStatusRecord) -> String? {
        var parts: [String] = []
        if let g = r.depGate ?? segment.boardingPoint { parts.append("Gate \(g)") }
        if let t = r.depEstimated ?? r.depActual ?? r.depScheduled {
            parts.append("Dep \(t.formatted(.dateTime.hour().minute()))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
