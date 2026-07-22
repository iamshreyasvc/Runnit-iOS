//
//  MapLayout.swift
//  Runnit iOS
//
//  How a map screen arranges its map and its trip list. Portrait stacks them —
//  map behind, sheet sliding up from the bottom; landscape sets them side by
//  side, the way Apple Maps does, with the list as a floating panel pinned to
//  the leading edge and the whole map visible beside it.
//

import SwiftUI

enum MapLayout {
    /// Map full-bleed, trip list in a bottom sheet with drag detents.
    case stacked
    /// Map full-bleed, trip list in a fixed-width panel on the leading edge.
    case sideBySide

    /// Chooses off the container's own shape rather than the size class, so the
    /// panel appears wherever there is genuinely more width than height —
    /// iPhone landscape, iPad landscape, and iPad multitasking widths alike.
    init(containerSize: CGSize) {
        self = containerSize.width > containerSize.height ? .sideBySide : .stacked
    }

    /// Width of the leading panel. Wide enough for a trip card to keep its
    /// two-line layout, narrow enough to leave the map the majority of a
    /// landscape iPhone.
    var panelWidth: CGFloat { 340 }

    /// Inset the map's floating controls need so they clear the panel.
    func leadingInset(collapsed: Bool) -> CGFloat {
        guard self == .sideBySide, !collapsed else { return 0 }
        return panelWidth + 12
    }
}
