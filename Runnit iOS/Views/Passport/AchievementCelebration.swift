//
//  AchievementCelebration.swift
//  Runnit iOS
//
//  The moment a milestone unlocks: a glass card drops in from the top with the
//  fresh stamp, over a brief shower of confetti. Multiple unlocks queue up and
//  play one after another. Purely presentational — what to show is decided by
//  `AchievementTracker`; this just performs it.
//

import SwiftUI

struct AchievementCelebration: View {
    /// Milestones still to show, in order. The view drains this itself.
    @Binding var queue: [Achievement]

    @State private var current: Achievement?
    @State private var confettiOn = false

    var body: some View {
        ZStack(alignment: .top) {
            if confettiOn {
                ConfettiView(tint: current?.tint ?? .yellow)
                    .allowsHitTesting(false)
            }
            if let current {
                card(current)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: current?.title)
        .onChange(of: queue) { _, _ in advanceIfIdle() }
        .onAppear { advanceIfIdle() }
    }

    private func card(_ achievement: Achievement) -> some View {
        HStack(spacing: 14) {
            Image(systemName: achievement.icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(achievement.tint.gradient, in: .circle)
                .shadow(color: achievement.tint.opacity(0.6), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Achievement Unlocked")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(achievement.tint)
                Text(achievement.title)
                    .font(.headline.weight(.heavy))
                Text(achievement.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(achievement.tint.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .contentShape(.rect)
        .onTapGesture { dismissCurrent() }
    }

    /// Pull the next milestone off the queue when nothing is on screen, then let
    /// it linger before making way for the one behind it.
    private func advanceIfIdle() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        current = next
        confettiOn = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.2))
            dismissCurrent()
        }
    }

    private func dismissCurrent() {
        guard current != nil else { return }
        current = nil
        confettiOn = false
        // Small beat before the next card, so they don't overlap.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            advanceIfIdle()
        }
    }
}

/// A brief, lightweight confetti burst — a few dozen colored shards drifting down
/// and fading. Deliberately simple: no physics, just staggered falls.
private struct ConfettiView: View {
    let tint: Color

    private let palette: [Color]
    private let pieces: [Piece]

    init(tint: Color) {
        self.tint = tint
        self.palette = [tint, .yellow, .pink, .cyan, .green, .orange]
        self.pieces = (0..<36).map { _ in Piece() }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(pieces) { piece in
                    ConfettiShard(color: palette[piece.colorIndex % palette.count],
                                  size: proxy.size, piece: piece)
                }
            }
        }
        .ignoresSafeArea()
    }

    struct Piece: Identifiable {
        let id = UUID()
        let xStart = Double.random(in: 0...1)
        let delay = Double.random(in: 0...0.6)
        let duration = Double.random(in: 1.4...2.6)
        let drift = Double.random(in: -60...60)
        let spin = Double.random(in: 180...720)
        let width = Double.random(in: 6...11)
        let height = Double.random(in: 8...16)
        let colorIndex = Int.random(in: 0...5)
    }
}

private struct ConfettiShard: View {
    let color: Color
    let size: CGSize
    let piece: ConfettiView.Piece

    @State private var fall = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: piece.width, height: piece.height)
            .position(x: piece.xStart * size.width + (fall ? piece.drift : 0),
                      y: fall ? size.height + 40 : -40)
            .rotationEffect(.degrees(fall ? piece.spin : 0))
            .opacity(fall ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: piece.duration).delay(piece.delay)) {
                    fall = true
                }
            }
    }
}
