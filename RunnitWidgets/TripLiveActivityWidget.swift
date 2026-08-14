//
//  TripLiveActivityWidget.swift
//  RunnitWidgets
//
//  The Lock Screen and Dynamic Island presentation of a trip in progress. The app
//  (Services/TripLiveActivity.swift) owns the lifecycle and feeds it a
//  `TripActivityAttributes.ContentState`; this only draws.
//

import SwiftUI
import WidgetKit
import ActivityKit

struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            LockScreenLiveActivityView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(context.state.tint.color.opacity(0.12))
                .activitySystemActionForegroundColor(context.state.tint.color)
        } dynamicIsland: { context in
            let state = context.state
            let tint = state.tint.color
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(state.departureCode).font(.caption).fontWeight(.semibold)
                    } icon: {
                        Image(systemName: state.legMode.symbol).foregroundStyle(tint)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.punctuality)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.headline)
                        .font(.headline).fontWeight(.bold)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        LiveProgressBar(start: state.rangeStart, end: state.rangeEnd, tint: tint)
                        HStack {
                            timeText(state.departureTime, code: state.departureCode)
                            Spacer()
                            if let end = state.rangeEnd, end > Date() {
                                Text(timerInterval: Date()...end, countsDown: true)
                                    .font(.caption2.weight(.semibold))
                                    .monospacedDigit()
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: 70)
                            }
                            Spacer()
                            timeText(state.arrivalTime, code: state.arrivalCode)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: state.legMode.symbol).foregroundStyle(tint)
            } compactTrailing: {
                if let end = state.rangeEnd, end > Date() {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(tint)
                        .frame(maxWidth: 44)
                } else {
                    Text(state.arrivalCode).font(.caption2).foregroundStyle(tint)
                }
            } minimal: {
                Image(systemName: state.legMode.symbol).foregroundStyle(tint)
            }
            .widgetURL(URL(string: "runnit://trip/\(context.attributes.tripID)"))
            .keylineTint(tint)
        }
    }

    private func timeText(_ date: Date?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(code).font(.caption2.weight(.bold))
            if let date {
                Text(date, style: .time)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// The Lock Screen banner: a compact status card mirroring the in-app live card.
struct LockScreenLiveActivityView: View {
    let attributes: TripActivityAttributes
    let state: TripActivityAttributes.ContentState

    private var tint: Color { state.tint.color }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if state.isUnderway {
                    LivePulseDot(color: tint)
                } else {
                    Image(systemName: state.legMode.symbol)
                        .font(.headline).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.headline)
                        .font(.headline).fontWeight(.bold)
                        .lineLimit(1)
                    if let subtitle = state.subtitle {
                        Text(subtitle)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text(state.punctuality)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(tint.opacity(0.16), in: .capsule)
            }

            LiveProgressBar(start: state.rangeStart, end: state.rangeEnd, tint: tint)

            HStack(alignment: .firstTextBaseline) {
                endpoint(code: state.departureCode, time: state.departureTime, alignment: .leading)
                Spacer(minLength: 0)
                Image(systemName: state.legMode.symbol)
                    .font(.caption2).foregroundStyle(tint)
                Spacer(minLength: 0)
                endpoint(code: state.arrivalCode, time: state.arrivalTime, alignment: .trailing)
            }
        }
        .padding(16)
    }

    private func endpoint(code: String, time: Date?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(code).font(.subheadline.weight(.bold))
            if let time {
                Text(time, style: .time)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
