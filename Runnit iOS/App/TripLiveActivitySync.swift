//
//  TripLiveActivitySync.swift
//  Runnit iOS
//
//  An invisible view sitting behind the tab bar whose only job is to keep the
//  Live Activities honest. It ticks on the same 30-second beat as the active
//  trips box, so the Lock Screen and the Upcoming tab never disagree about
//  what's happening — and because it lives at the root, it keeps ticking no
//  matter which tab is on screen.
//
//  It reads trips and snapshots straight from the store and hands them to the
//  controller; it fetches nothing and writes nothing.
//

import SwiftUI
import SwiftData

struct TripLiveActivitySync: View {
    @Query private var trips: [Trip]
    @Query private var records: [FlightStatusRecord]

    var body: some View {
        #if os(iOS)
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Color.clear
                .task(id: context.date) {
                    await TripLiveActivityController.sync(
                        trips: trips, records: records, now: context.date
                    )
                }
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        #else
        Color.clear.frame(width: 0, height: 0)
        #endif
    }
}
