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
    /// destination. Falls back to just showing the destination if the origin
    /// has no meaningful coordinate.
    static func openDirections(from origin: Place, to destination: Place) {
        let destinationItem = mapItem(for: destination)

        let hasOrigin = origin.latitude != 0 || origin.longitude != 0
        let options: [String: Any] = [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ]

        if hasOrigin {
            let originItem = mapItem(for: origin)
            MKMapItem.openMaps(with: [originItem, destinationItem], launchOptions: options)
        } else {
            destinationItem.openInMaps(launchOptions: options)
        }
    }

    private static func mapItem(for place: Place) -> MKMapItem {
        let item = MKMapItem(location: place.clLocation, address: nil)
        item.name = place.displayName
        return item
    }
}
