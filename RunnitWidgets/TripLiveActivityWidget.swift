//
//  TripLiveActivityWidget.swift
//  RunnitWidgets
//
//  The Lock Screen card and the Dynamic Island for a trip in motion. The card is
//  `TripActivityCard` verbatim — the same header, row, progress track and
//  endpoint strip the app draws in its "Happening Now" box — so a glance at the
//  Lock Screen and a glance at the Upcoming tab show the same thing.
//
//  The Dynamic Island is the same reading compressed: the mode icon and the
//  countdown when collapsed, the full row's information when expanded.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripActivityCard(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(context.state.accent.color)

        } dynamicIsland: { context in
            let state = context.state
            let tint = state.accent.color

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(state.startCode)
                    } icon: {
                        Image(systemName: state.icon).foregroundStyle(tint)
                    }
                    .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.endCode)
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.headline)
                        .font(.subheadline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        TripActivityProgressTrack(
                            progress: state.progress, icon: state.icon, tint: tint
                        )
                        HStack {
                            Text(state.punctuality)
                                .foregroundStyle(tint)
                            Spacer()
                            if let time = state.endTime {
                                Text("\(state.endTitle) \(time)")
                                    .foregroundStyle(state.endIsLate ? .orange : .secondary)
                            }
                        }
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: state.icon)
                    .foregroundStyle(tint)
            } compactTrailing: {
                compactCountdown(state)
                    .font(.caption2)
                    .foregroundStyle(tint)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: state.icon)
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }

    /// Just the clock in the Island's trailing slot — the words that wrap it on
    /// the full card don't fit here, and the number is the point.
    @ViewBuilder
    private func compactCountdown(_ state: TripActivityAttributes.ContentState) -> some View {
        if let range = state.countdownRange {
            Text(timerInterval: range, countsDown: true)
        } else if let fallback = state.countdownFallback {
            Text(fallback)
        }
    }
}
