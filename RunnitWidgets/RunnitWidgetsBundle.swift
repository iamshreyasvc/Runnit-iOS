//
//  RunnitWidgetsBundle.swift
//  RunnitWidgets
//
//  The extension's entry point. Only the trip Live Activity for now; home-screen
//  widgets would join the bundle here.
//

import WidgetKit
import SwiftUI

@main
struct RunnitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TripLiveActivityWidget()
    }
}
