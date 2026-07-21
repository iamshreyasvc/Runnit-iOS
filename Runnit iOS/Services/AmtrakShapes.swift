//
//  AmtrakShapes.swift
//  Runnit iOS
//
//  Real Amtrak route geometry, keyed by GTFS shape id. Bundled as
//  `AmtrakShapes.json` (generated and downsampled by
//  Scripts/generate_amtrak_data.py from the feed's shapes.txt), it lets the map
//  trace the true rail corridor a train follows rather than a straight line
//  between stations — and, unlike the Indian route (chained station coordinates),
//  it's the actual surveyed track, so the line curves the way the rails do.
//

import Foundation
import CoreLocation

nonisolated struct AmtrakShapes {
    /// shape id → ordered [[lat, lon], …] polyline.
    let shapes: [String: [[Double]]]

    /// Loaded once, lazily. The largest of the Amtrak resources (~1 MB); still
    /// small enough to parse eagerly on first route draw.
    static let bundled: AmtrakShapes = {
        guard let url = Bundle.main.url(forResource: "AmtrakShapes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [[Double]]].self, from: data)
        else { return AmtrakShapes(shapes: [:]) }
        return AmtrakShapes(shapes: decoded)
    }()

    /// The polyline for a shape id as coordinates, or `nil` when it's unknown or
    /// too short to draw.
    func coordinates(for shapeID: String) -> [CLLocationCoordinate2D]? {
        guard let raw = shapes[shapeID], raw.count >= 2 else { return nil }
        let coords = raw.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
        return coords.count >= 2 ? coords : nil
    }
}
