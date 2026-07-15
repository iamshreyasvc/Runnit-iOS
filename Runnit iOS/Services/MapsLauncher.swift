//
//  MapsLauncher.swift
//  Runnit iOS
//
//  Opens Apple Maps with driving directions preloaded. Isolated behind one
//  type so alternate providers (Google Maps / Waze) can be added later.
//

import MapKit

enum MapsLauncher {
    /// Open Apple Maps with turn-by-turn driving directions from origin to
    /// destination, routing through any intermediate `waypoints` in order. Falls
    /// back to just showing the destination if the origin has no coordinate.
    static func openDirections(from origin: Place, to destination: Place,
                               via waypoints: [Place] = []) {
        let options: [String: Any] = [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ]

        var items: [MKMapItem] = []
        let hasOrigin = origin.latitude != 0 || origin.longitude != 0
        if hasOrigin { items.append(mapItem(for: origin)) }
        items.append(contentsOf: waypoints.map(mapItem(for:)))
        items.append(mapItem(for: destination))

        if items.count == 1 {
            items[0].openInMaps(launchOptions: options)
        } else {
            MKMapItem.openMaps(with: items, launchOptions: options)
        }
    }

    private static func mapItem(for place: Place) -> MKMapItem {
        let item = MKMapItem(location: place.clLocation, address: nil)
        item.name = place.displayName
        return item
    }
}
