# Runnit — Roadmap & Design Notes

This captures the features and design directions discussed but **not yet built**, plus the intentional seams in the current code that make them cheap to add. It's a living document — order is rough priority, not commitments.

## Live tracking (the big one)

Runnit's biggest differentiator vs. a manual log would be **live status**, like Flighty.

- **Flights/trains live status** — gate/terminal/platform, delays, boarding, and a live position on the map.
- **Hook already in place:** `Services/FlightStatusProvider.swift` is a protocol with a no-op `ManualFlightStatusProvider`. A real implementation backed by an aviation API (e.g. **AeroAPI** or **AviationStack**) can slot in behind it without touching the views. Requires an API key and likely a paid plan.
- ~~**Delay push notifications / Live Activities** — alert when a tracked flight's gate or time changes; a Lock Screen / Dynamic Island Live Activity for the active trip.~~ **Shipped** (local notifications + a Lock Screen / Dynamic Island Live Activity). Delay alerts are surfaced from data the app already has rather than server push. See `Services/TripNotifications.swift`, `Services/TripLiveActivity.swift`, and `RunnitWidgets/TripLiveActivityWidget.swift`. Widget-target wiring is in `SETUP.md`.

## Sync & sharing

- **iCloud sync (CloudKit)** — **built, gated off.** Needs a paid Apple Developer
  account: free "personal teams" cannot use the iCloud capability at all. Flip
  `RunnitCloudKitEnabled` in `Config/Info.plist` once enrolled. `Services/Sync/` drives `CKSyncEngine`
  `Services/Sync/` drives `CKSyncEngine` over a private and a shared database,
  with SwiftData still the local source of truth. The CloudKit schema also has to
  be deployed to Production before any TestFlight build.
- **Trip sharing** — **built, gated off** with the above. Invite people to a trip with view-only or can-edit
  access, per person, managed from the trip's People screen.
- **Passport sharing** — still open: share a "passport" summary with friends.
- **Sharing beyond iCloud** — the CloudKit choice means guests need an Apple
  account and there's no Android or web path. Revisit only if that becomes a real
  constraint; it would mean a server and an auth system.

## Navigation & maps

- **More navigation apps** — v1 opens **Apple Maps** only, isolated in `Services/MapsLauncher.swift`. Add **Google Maps** and **Waze** via their URL schemes, with an in-app picker (iOS has no API to read the system default maps app, so the choice lives in-app — a preference stub already exists on the Account page).
- **Transit ETAs** — extend `RouteEstimator` (currently driving-only via `MKDirections`) to walking/transit for non-car trips.
- **Richer route rendering** — draw the actual road/great-circle route geometry instead of a straight dashed line.

## Importing trips

- **Email / calendar import** — parse airline confirmation emails or calendar events into trips, so users don't hand-enter everything.
- **Flight-number autofill** — look up airports, times, and operator from a flight number (pairs with the live-tracking API).

## Passport & stats

- **More "tidbits"** — richer Passport content (longest streak, busiest month, favorite route, new-countries-this-year, map heat of visited regions).
- **Achievements / stamps** — unlockable stamps for milestones (first international trip, 10 countries, etc.). Badges shipped in `PassportInsights.swift`; a newly-earned milestone now gets a one-time celebratory drop-in (`Views/Passport/AchievementCelebration.swift`, `Services/AchievementTracker.swift`).

## Platform extras

- ~~**Home Screen widgets** — next upcoming trip / countdown.~~ **Shipped** — a "Next Trip" widget for the Home Screen (small/medium) and Lock Screen (rectangular/circular/inline), fed by an App Group snapshot the app writes (`RunnitWidgets/NextTripWidget.swift`, `Services/WidgetSnapshotWriter.swift`). Widget-target wiring is in `SETUP.md`.
- **Apple Wallet passes** — adding an existing boarding pass to Wallet is shipped (Trip menu → "Add boarding pass to Wallet"). *Generating* a pass from trip data is scaffolded (`Services/PassGenerator.swift`) but needs a Pass Type ID certificate + a signing step — see `SETUP.md`.
- **Apple Watch app** — glanceable next trip and boarding info.
- **App Shortcuts / Siri** — "Add a trip", "When's my next flight?".

## Design system notes

Established look & feel to keep consistent as features are added:

- **Liquid Glass throughout** — `glassEffect` cards, mode-tinted via `glassCard(tint:)`, the iOS 26 minimizing tab bar, and `GlassEffectContainer` groupings.
- **Dark by default** — with a colorful ambient `AppBackground` (blurred color blobs); appearance is user-overridable (System/Light/Dark) on the Account page.
- **Per-mode accent colors** — flight = blue, train = orange, road trip = green, other = purple (`TripType.accent`). New surfaces should adopt the relevant mode accent.
- **Styled section headers** — colored section icon + title + count in the nav bar (`sectionHeader(_:systemImage:tint:subtitle:)`).
- **Conversational input** — the add-trip flow is a one-question-at-a-time wizard (`AddTripFlowView`); prefer this friendly style over dense forms for future input flows.

## Explicitly considered and deferred / declined

- **App localization (multiple human languages)** — briefly considered, but **not wanted for now**. ("Multi-language" turned out to mean the conversational one-question-at-a-time add flow, which is done.)
- **Editing via the wizard** — editing an existing trip still uses the classic form (`AddEditTripView`); the wizard is add-only by design. Could be revisited.

## Housekeeping / tech debt

- **DEBUG-only env hooks** in the UI for screenshotting specific screens without tapping the simulator: `INITIAL_TAB`, `SHOW_ADD`, `ADD_STEP`, `ADD_DEMO_ROADTRIP`. Compiled out of release builds; remove when no longer useful.
- **Seeded sample road trips** predate the ETA feature, so they have no stored arrival/drive time; only wizard-added road trips get one.
