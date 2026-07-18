//
//  SegmentRouteContent.swift
//  Runnit iOS
//
//  The one way a trip leg is drawn on a map: a casing-backed, gradient-tinted
//  route line — plus, while a flight leg is actually in the air, the live
//  aircraft riding the travelled track, with the remaining stretch to the
//  destination dashed. Shared by the trip detail map, the full-screen map, and
//  the Upcoming/Past tab maps, so every surface tells the same story.
//

import SwiftUI
import MapKit

/// Draws one segment's route. Pass the segment's displayable live record (if
/// any) to get the in-flight presentation; with `live == nil` the leg renders
/// as before: its real route when cached, else a straight line through its
/// places.
struct SegmentRouteContent: MapContent {
    let segment: TripSegment
    var live: FlightStatusRecord?

    var body: some MapContent {
        let coords = travelledCoordinates
        MapPolyline(coordinates: coords)
            .stroke(.black.opacity(0.22),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
        MapPolyline(coordinates: coords)
            .stroke(segment.type.gradient,
                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))

        if let position = livePosition {
            // The stretch still to fly, dashed so travelled vs. remaining reads
            // at a glance.
            MapPolyline(coordinates: [position, segment.destination.coordinate])
                .stroke(segment.type.accent.opacity(0.55),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 7]))
            Annotation("", coordinate: position) {
                LivePlaneMarker(heading: live?.liveDirection ?? 0, tint: segment.type.accent)
            }
            .annotationTitles(.hidden)
        }
    }

    /// The live aircraft coordinate, only when this leg is a flight that's
    /// airborne right now. (Filtering to a *displayable* record is the caller's
    /// job — `[FlightStatusRecord].liveRecord(for:)` does both.)
    private var livePosition: CLLocationCoordinate2D? {
        guard segment.type == .flight, let live, live.hasLivePosition else { return nil }
        return live.liveCoordinate
    }

    /// The solid line: while airborne, the flown track so far extended to the
    /// live position (so the path never lags behind the aircraft); otherwise the
    /// full cached route, or the straight-line fallback through the leg's places.
    private var travelledCoordinates: [CLLocationCoordinate2D] {
        guard let position = livePosition else {
            return segment.routedCoordinates ?? segment.routePlaces.map(\.coordinate)
        }
        var coords = segment.routedCoordinates ?? [segment.origin.coordinate]
        coords.append(position)
        return coords
    }
}

/// The live aircraft, styled like the app's other map pins: the airplane glyph
/// rotated to its true heading in a tinted disc, ringed white.
struct LivePlaneMarker: View {
    /// Track over ground in degrees (0 = north). The SF airplane glyph points
    /// east, hence the -90 correction.
    let heading: Double
    let tint: Color

    var body: some View {
        Image(systemName: "airplane")
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(heading - 90))
            .frame(width: 32, height: 32)
            .background(tint.gradient, in: .circle)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
}

extension Array where Element == FlightStatusRecord {
    /// The record that should put a live aircraft on the map for `segment`:
    /// this segment's, displayable, active, and carrying a position.
    func liveRecord(for segment: TripSegment, now: Date = Date()) -> FlightStatusRecord? {
        guard segment.type == .flight else { return nil }
        return first {
            $0.segmentID == segment.id
                && $0.isDisplayable(for: segment, now: now)
                && $0.hasLivePosition
        }
    }
}
