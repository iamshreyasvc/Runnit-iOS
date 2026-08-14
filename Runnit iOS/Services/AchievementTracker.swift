//
//  AchievementTracker.swift
//  Runnit iOS
//
//  Remembers which milestones the traveler has already been congratulated for, so
//  a newly-earned stamp is celebrated exactly once — not re-toasted every time the
//  Passport opens. Titles are the stable identity here (an Achievement's `id` is a
//  fresh UUID each rebuild), stored as a small JSON array in UserDefaults.
//
//  First run is deliberately quiet: someone who already has ten stamps when this
//  ships shouldn't be hit with ten pop-ups. We seed the remembered set on the
//  first look and only celebrate what unlocks *after* that.
//

import Foundation

@MainActor
enum AchievementTracker {

    /// Compare the current achievements against what we've already celebrated and
    /// return the ones that just unlocked, recording them so they don't fire again.
    /// On the very first call (nothing remembered yet) it seeds silently and
    /// returns nothing.
    static func newlyUnlocked(from achievements: [Achievement]) -> [Achievement] {
        let defaults = UserDefaults.standard
        let unlockedNow = achievements.filter(\.isUnlocked)

        guard let stored = defaults.string(forKey: PrefKey.unlockedAchievements),
              let data = stored.data(using: .utf8),
              let known = try? JSONDecoder().decode(Set<String>.self, from: data)
        else {
            // First run: remember today's state without celebrating any of it.
            save(Set(unlockedNow.map(\.title)))
            return []
        }

        let fresh = unlockedNow.filter { !known.contains($0.title) }
        guard !fresh.isEmpty else { return [] }

        save(known.union(fresh.map(\.title)))
        return fresh
    }

    private static func save(_ titles: Set<String>) {
        guard let data = try? JSONEncoder().encode(titles),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: PrefKey.unlockedAchievements)
    }
}
