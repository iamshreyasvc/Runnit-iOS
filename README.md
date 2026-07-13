# Runnit

[![CI](https://github.com/iamshreyasvc/Runnit-iOS/actions/workflows/ci.yml/badge.svg)](https://github.com/iamshreyasvc/Runnit-iOS/actions/workflows/ci.yml)

A **Flighty-style trip tracker for every kind of journey** — flights, trains, and road trips — built for iOS 26 with SwiftUI, SwiftData, and Liquid Glass.

Where Flighty tracks only flights, Runnit keeps your whole travel history in one place: upcoming and past trips, an interactive map of your routes, and a "Passport" of stats and country stamps.

## Features

- **All travel modes** — flights, trains, road trips, and a catch-all "other".
- **Conversational add flow** — a one-question-at-a-time wizard (type → route → date → details) instead of a dull form.
- **Upcoming & Past tabs** — each with an interactive, zoomable map header of that tab's trips plus Liquid Glass trip cards.
- **Road-trip ETAs** — enter an origin and destination and Runnit pulls the driving time and arrival from **Apple Maps** (no manual arrival needed); one tap opens turn-by-turn directions.
- **Passport** — lifetime stats (distance, countries, trips by mode) and a grid of country flag "stamps" from your completed trips.
- **Account** — editable profile, lifetime stats, and preferences (appearance, distance units).
- **Liquid Glass UI** — dark-mode by default, a colorful ambient background, mode-tinted glass cards, and the iOS 26 minimizing tab bar.

## Requirements

- **Xcode 26** or later
- **iOS 26.5+** deployment target
- No third-party dependencies; no API keys required.

## Getting started

```bash
git clone https://github.com/iamshreyasvc/Runnit-iOS.git
cd Runnit-iOS
open "Runnit iOS.xcodeproj"
```

Select an iOS 26 simulator (or a device) and run. On first launch the app seeds a few sample trips so every screen has content; add your own with the **+** button.

## Architecture

Local-first and dependency-free. All data lives on-device via SwiftData.

```
Runnit iOS/
├── App/            RootTabView (4 tabs: Upcoming, Past, Passport, Account)
├── Models/         Trip (@Model) + Place (Codable value type) + samples
├── Services/       LocationSearch, MapsLauncher, RouteEstimator,
│                   TripStatistics, FlightStatusProvider (future-live seam)
├── Support/        DesignSystem, AppBackground, Preferences
└── Views/          Trips (list, card, detail, add wizard), Passport, Account

Runnit iOSTests/    Swift Testing unit tests for the logic layer
Scripts/            test.sh + coverage-report.sh (shared by local runs and CI)
```

Key decisions:

- **Manual entry now, live-tracking-ready** — `FlightStatusProvider` is a protocol seam so a real aviation API (AeroAPI / AviationStack) can be dropped in later without touching the views.
- **Apple Maps only** — road-trip directions and ETAs go through `MapsLauncher` / `RouteEstimator`, isolated so Google Maps / Waze can be added later.
- **Local storage** — SwiftData only for v1; CloudKit sync is a small later change.

See [ROADMAP.md](ROADMAP.md) for planned features and design directions.

## Testing & CI

Unit tests (Swift Testing) cover the pure-logic layer — models, statistics, formatting, and preferences — in `Runnit iOSTests/`.

Run the full build + test + coverage gate locally exactly as CI does:

```bash
Scripts/test.sh                 # auto-picks an available iPhone simulator
COVERAGE_MIN=30 Scripts/test.sh # raise the coverage bar
```

Or drive `xcodebuild` directly:

```bash
xcodebuild test \
  -project "Runnit iOS.xcodeproj" -scheme "Runnit iOS" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES CODE_SIGNING_ALLOWED=NO
```

Every push to `main` and every pull request runs [`.github/workflows/ci.yml`](.github/workflows/ci.yml), which:

1. **Lints** with [SwiftLint](.swiftlint.yml) (error-level violations fail the build; warnings are annotated). Run `swiftlint --strict` locally to stay warning-clean.
2. **Builds & tests** on an iOS 26 simulator with coverage enabled.
3. **Enforces coverage** for the app target via [`Scripts/coverage-report.sh`](Scripts/coverage-report.sh) — the build fails below `COVERAGE_MIN` (currently **15%**) and a per-file coverage table is posted to the run summary.

The threshold is a deliberately conservative floor: most of the app is SwiftUI views that only gain incidental coverage from the test host launching, while the deterministic logic layer (models, statistics, formatting) is covered well above it. Ratchet the floor upward as UI/integration tests are added.

## Status

Early MVP — functional end to end, but pre-release. Not yet on the App Store.
