# Setup — Live Activities, Widgets, Notifications & Wallet

Most of this branch's work compiles into the existing app target and needs nothing
special. Two features — the **Live Activity** and the **Home/Lock Screen widget** —
need a **Widget Extension target** and an **App Group**, which can only be created
in Xcode. This document is the ~10-minute wiring checklist.

Everything below was written in an environment with Command Line Tools only, so it
has **not** been built. Please verify in Xcode / CI.

---

## What already works with no setup

- **Trip notifications** — `Services/TripNotifications.swift`, toggled on the
  Account screen. Local only; the first time you enable them the system asks for
  permission.
- **Passport achievements** — new milestones + an unlock celebration
  (`Services/AchievementTracker.swift`, `Views/Passport/AchievementCelebration.swift`).
- **Add an existing boarding pass to Wallet** — the Trip menu → "Add boarding pass
  to Wallet" (`Views/Trips/AddPassesView.swift`). No certificate needed.

---

## 1. Add the Widget Extension target

1. **File → New → Target… → Widget Extension.**
2. Name it **`RunnitWidgets`**. Uncheck "Include Configuration App Intent".
   **Check "Include Live Activity".** Finish. (Activate the scheme if prompted.)
3. Xcode generates a starter folder. **Delete the generated `.swift` files**
   (keep the target) — this repo already has the real ones in the top-level
   **`RunnitWidgets/`** folder.
4. Add the existing sources to the target: select the `RunnitWidgets/` group and
   add these to the **RunnitWidgets** target only:
   - `RunnitWidgetsBundle.swift`
   - `TripLiveActivityWidget.swift`
   - `NextTripWidget.swift`
   - `WidgetSupport.swift`
   - `Info.plist` (set as the target's Info.plist in Build Settings) and
     `RunnitWidgets.entitlements` (set as `CODE_SIGN_ENTITLEMENTS`).

## 2. Shared files → both targets

These live in **`Shared/`** and must belong to **both** the app and the widget
target (select each file → File Inspector → Target Membership):

- `Shared/TripActivityAttributes.swift`
- `Shared/TripWidgetSnapshot.swift`

> The app already references these (`TripLiveActivity`, `WidgetSnapshotWriter`), so
> the app won't compile until they're in the app target.

## 3. App Group (for the widget snapshot)

The Home/Lock Screen widget reads a snapshot the app writes into a shared
container. Create the group once and enable it on both targets.

1. **App target → Signing & Capabilities → + Capability → App Groups.** Add
   **`group.Runnit.Runnit-iOS`**. This should pick up
   `Runnit iOS/Runnit iOS.entitlements` (already in the repo); if Xcode made a new
   entitlements file, either point `CODE_SIGN_ENTITLEMENTS` at the repo one or copy
   the `application-groups` key across.
2. **RunnitWidgets target → + Capability → App Groups.** Add the **same** group
   (`RunnitWidgets.entitlements` already declares it).

> Using a different group id? Change the single constant in
> `Shared/TripWidgetSnapshot.swift` (`WidgetSharing.appGroup`) and both
> `.entitlements` files.

## 4. Live Activities plist key

- The **app** `Info.plist` already has `NSSupportsLiveActivities = YES`
  (`Config/Info.plist`).
- The **widget** `Info.plist` (`RunnitWidgets/Info.plist`) already has it too.
- Nothing else to do — the app starts activities from `TripDetailView` when a trip
  is underway, and the widget renders them.

## 5. (Optional) Time-Sensitive delay alerts

Delay notifications set `interruptionLevel = .timeSensitive`. To let them break
through Focus, add the **Time Sensitive Notifications** capability to the app
target. Without it they still deliver, just at the normal level.

## 6. (Optional) Deep link from the widget

The Live Activity sets `widgetURL(runnit://trip/<id>)`. To make tapping it open the
trip, register a `runnit` URL scheme (app target → Info → URL Types) and handle it
with `.onOpenURL` in `RootTabView`. Harmless if skipped.

---

## Wallet: generating passes from scratch (not yet enabled)

`Services/PassGenerator.swift` builds a boarding pass **payload** (`pass.json` +
`manifest.json`) from a flight leg, but **cannot produce an installable
`.pkpass`** on its own. A `.pkpass` must be signed with a **Pass Type ID
certificate**, and Wallet rejects anything unsigned. To finish this:

1. In the Apple Developer portal, create a **Pass Type ID** (e.g.
   `pass.Runnit.boarding`) and download its certificate.
2. Fill `PassGenerator.Identity` with that identifier and your Team ID.
3. Implement `PassSigner` to produce the PKCS#7 detached signature over the
   manifest — **keep the private key off-device** (a small signing service), then
   ZIP `pass.json` + `manifest.json` + `signature` into the `.pkpass`.
4. Hand the resulting data to `AddPassesView` (already built) to install it.

Until then, travelers can add passes they already have (§ "What already works").

---

## Quick verification checklist

- [ ] App target compiles (shared files are members).
- [ ] `RunnitWidgets` target compiles (its 4 sources + Info.plist + entitlements).
- [ ] App Group `group.Runnit.Runnit-iOS` on both targets.
- [ ] Run the app, open a trip that's underway → a Live Activity appears on the
      Lock Screen / Dynamic Island.
- [ ] Add the "Next Trip" widget to the Home/Lock Screen → shows your next trip and
      a live countdown.
- [ ] Account → enable Trip reminders → accept the permission prompt.
