//
//  ProfileComponents.swift
//  Runnit iOS
//
//  The monogram avatar used on the Account tab and in the profile editor. Styled
//  like the map's destination pins — a tinted gradient disc ringed in white — so
//  the profile shares the Trips pages' visual language.
//

import SwiftUI

/// A round monogram avatar: the traveler's initials over a tinted gradient, ringed
/// like the map pins. Falls back to a person glyph when the name is blank, so it
/// always reads as a portrait slot.
struct ProfileAvatar: View {
    let name: String
    var accent: Color = .cyan
    var size: CGFloat = 84

    /// Up to two initials from the first and last word of the name.
    private var monogram: String {
        let words = name
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let first = words.first?.first else { return "" }
        if words.count > 1, let last = words.last?.first {
            return "\(first)\(last)".uppercased()
        }
        return String(first).uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(accent.gradient)
            if monogram.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(monogram)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: size * 0.028))
        .shadow(color: accent.opacity(0.55), radius: size * 0.16, y: 5)
    }
}

#if DEBUG
#Preview {
    ZStack {
        AppBackground()
        HStack(spacing: 20) {
            ProfileAvatar(name: "Shreyas Chandramouli", accent: .cyan)
            ProfileAvatar(name: "", accent: .pink)
        }
    }
    .preferredColorScheme(.dark)
}
#endif
