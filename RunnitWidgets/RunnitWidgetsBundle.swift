//
//  RunnitWidgetsBundle.swift
//  RunnitWidgets
//
//  The widget extension's entry point. Bundles the Home/Lock Screen "Next Trip"
//  widget and the trip Live Activity together.
//

import SwiftUI
import WidgetKit

@main
struct RunnitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextTripWidget()
        TripLiveActivityWidget()
    }
}
