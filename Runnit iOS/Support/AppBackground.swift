//
//  AppBackground.swift
//  Runnit iOS
//
//  The app's base backdrop: a solid black (dark) or white (light) fill with a
//  fine procedural grain over it, so large flat areas read as textured paper
//  rather than dead pixels. No gradient, no color blobs.
//

import SwiftUI
import UIKit
import CoreImage

struct AppBackground: View {
    // Kept for call-site compatibility; the flat backdrop ignores them.
    var accent: Color = .blue
    var secondary: Color = .purple

    @Environment(\.colorScheme) private var scheme
    private var isDark: Bool { scheme == .dark }

    var body: some View {
        (isDark ? Color.black : Color.white)
            .overlay(FilmGrain(intensity: isDark ? 0.10 : 0.05))
            .ignoresSafeArea()
    }
}

/// A tiled monochrome noise overlay. The noise tile is rendered once from
/// Core Image and reused, so the grain is essentially free to draw.
private struct FilmGrain: View {
    var intensity: Double

    var body: some View {
        if let grain = Self.tile {
            Image(uiImage: grain)
                .resizable(resizingMode: .tile)
                .opacity(intensity)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }

    /// One small grayscale noise tile, generated a single time and cached.
    private static let tile: UIImage? = makeTile(size: 180)

    private static func makeTile(size: CGFloat) -> UIImage? {
        let context = CIContext(options: nil)
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        // Desaturate so the grain is neutral gray, not colored static.
        let mono = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        guard let cg = context.createCGImage(mono, from: rect) else { return nil }
        return UIImage(cgImage: cg)
    }
}

#if DEBUG
#Preview("Dark") {
    AppBackground()
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    AppBackground()
        .preferredColorScheme(.light)
}
#endif
