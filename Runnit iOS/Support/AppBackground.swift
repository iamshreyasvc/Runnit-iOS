//
//  AppBackground.swift
//  Runnit iOS
//
//  A colorful, dark, ambient background used behind the main screens. Soft
//  blurred color blobs over a near-black gradient — vivid but readable.
//

import SwiftUI

struct AppBackground: View {
    /// Primary tint; usually the active trip mode's accent.
    var accent: Color = .blue
    /// Secondary tint for variety.
    var secondary: Color = .purple

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.11),
                    Color(red: 0.02, green: 0.02, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            blob(accent.opacity(0.45), size: 420, x: -150, y: -320)
            blob(secondary.opacity(0.38), size: 380, x: 170, y: -160)
            blob(Color.teal.opacity(0.28), size: 400, x: 150, y: 340)
            blob(accent.opacity(0.22), size: 320, x: -140, y: 300)
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 120)
            .offset(x: x, y: y)
    }
}

#if DEBUG
#Preview {
    AppBackground(accent: .green, secondary: .blue)
}
#endif
