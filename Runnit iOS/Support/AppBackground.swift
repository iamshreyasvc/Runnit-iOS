//
//  AppBackground.swift
//  Runnit iOS
//
//  A colorful ambient background used behind the main screens. Soft blurred
//  color blobs over a base gradient that adapts to light / dark mode.
//

import SwiftUI

struct AppBackground: View {
    /// Primary tint; usually the active trip mode's accent.
    var accent: Color = .blue
    /// Secondary tint for variety.
    var secondary: Color = .purple

    @Environment(\.colorScheme) private var scheme
    private var isDark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            baseGradient
            blob(accent, strength: 1.0, size: 420, x: -150, y: -320)
            blob(secondary, strength: 0.85, size: 380, x: 170, y: -160)
            blob(.teal, strength: 0.65, size: 400, x: 150, y: 340)
            blob(accent, strength: 0.5, size: 320, x: -140, y: 300)
        }
        .ignoresSafeArea()
    }

    private var baseGradient: LinearGradient {
        let colors = isDark
            ? [Color(red: 0.05, green: 0.06, blue: 0.11), Color(red: 0.02, green: 0.02, blue: 0.04)]
            : [Color(red: 0.97, green: 0.98, blue: 1.00), Color(red: 0.88, green: 0.91, blue: 0.98)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private func blob(_ color: Color, strength: Double, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        // Blobs are vivid in dark mode, much softer in light mode so dark text
        // stays readable.
        let opacity = (isDark ? 0.45 : 0.20) * strength
        return Circle()
            .fill(color.opacity(opacity))
            .frame(width: size, height: size)
            .blur(radius: 120)
            .offset(x: x, y: y)
    }
}

#if DEBUG
#Preview("Dark") {
    AppBackground(accent: .green, secondary: .blue)
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    AppBackground(accent: .green, secondary: .blue)
        .preferredColorScheme(.light)
}
#endif
