//
//  AccountView.swift
//  Runnit iOS
//
//  The traveler's profile and app settings, built in the Upcoming/Past design
//  language: a full-bleed accent hero with the avatar and liquid-glass capsule
//  chips floating over it, then a rounded glass sheet of settings that slides up.
//  Lifetime travel stats live on the Passport tab, so they aren't repeated here.
//

import SwiftUI
import SwiftData

struct AccountView: View {
    @AppStorage(PrefKey.appearance) private var appearanceRaw = AppAppearance.dark.rawValue
    @AppStorage(PrefKey.distanceUnit) private var distanceUnitRaw = DistanceUnit.automatic.rawValue
    @AppStorage(PrefKey.displayName) private var displayName = "Traveler"
    @AppStorage(PrefKey.username) private var username = ""
    @AppStorage(PrefKey.homeBase) private var homeBase = ""
    @AppStorage(PrefKey.email) private var email = ""
    @AppStorage(PrefKey.avatarTint) private var avatarTintRaw = ProfileAccent.cyan.rawValue
    @AppStorage(PrefKey.flightAutoRefresh) private var flightAutoRefresh = false

    @AppStorage(PrefKey.notificationsEnabled) private var notificationsEnabled = false
    @AppStorage(PrefKey.notifyCheckIn) private var notifyCheckIn = true
    @AppStorage(PrefKey.notifyDeparture) private var notifyDeparture = true
    @AppStorage(PrefKey.notifyDelays) private var notifyDelays = true
    @AppStorage(PrefKey.liveActivitiesEnabled) private var liveActivitiesEnabled = true

    @State private var editingProfile = false

    private var accent: Color { (ProfileAccent(rawValue: avatarTintRaw) ?? .cyan).color }
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var name: String {
        displayName.trimmingCharacters(in: .whitespaces).isEmpty ? "Traveler" : displayName
    }
    private var handle: String? {
        let t = username.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return t.hasPrefix("@") ? t : "@\(t)"
    }
    private var base: String? {
        let t = homeBase.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppBackground(accent: accent, secondary: accent)
                accentGlow
                ScrollView {
                    VStack(spacing: 0) {
                        hero.appear(0)
                        settingsSheet.appear(1)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .sectionHeader("Account", systemImage: "person.crop.circle", tint: accent)
            .sheet(isPresented: $editingProfile) {
                EditProfileView(name: $displayName,
                                username: $username,
                                homeBase: $homeBase,
                                email: $email,
                                accentRaw: $avatarTintRaw)
            }
        }
    }

    // MARK: Backdrop

    /// A soft accent wash at the top — the Account tab's vivid backdrop, standing
    /// in for the Trips pages' full-bleed map.
    private var accentGlow: some View {
        LinearGradient(colors: [accent.opacity(0.45), accent.opacity(0.12), .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 420)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: Hero — avatar + identity, floating over the backdrop

    private var hero: some View {
        VStack(spacing: 14) {
            Button {
                editingProfile = true
            } label: {
                ProfileAvatar(name: name, accent: accent, size: 100)
            }
            .buttonStyle(.plain)

            Text(name)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            // Floating liquid-glass chips, exactly the filter-pill idiom used on
            // the Upcoming/Past sheets.
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if let handle {
                        chip(icon: "at", text: String(handle.dropFirst()), tinted: true)
                    }
                    if let base {
                        chip(icon: "house.fill", text: base, tinted: false)
                    }
                    if handle == nil && base == nil {
                        chip(icon: "sparkles", text: "Set up your profile", tinted: true)
                    }
                }
            }

            Button {
                editingProfile = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "pencil")
                    Text("Edit Profile")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
            .buttonStyle(.glassProminent)
            .tint(accent)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    /// A single liquid-glass capsule chip — icon + label. The tinted variant
    /// carries the accent, matching the active filter pill's coloring.
    private func chip(icon: String, text: String, tinted: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tinted ? accent : .secondary)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: Settings sheet

    /// The rounded glass panel that holds all settings — the same slide-up sheet
    /// treatment as the trip list, with a decorative grab handle and a stack of
    /// liquid-glass groups blended by a GlassEffectContainer.
    private var settingsSheet: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(.secondary.opacity(0.45))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 2)

            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    profileGroup
                    preferencesGroup
                    notificationsGroup
                    flightTrackingGroup
                    aboutGroup
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity)
        .background(
            // Unlike the Trips/Passport sheets, this one scrolls with the page
            // instead of being pinned, so it can't reach the safe area from
            // inside the ScrollView. Overhanging the material past the content
            // covers the bottom inset and any rubber-band; the ScrollView clips it.
            UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34)
                .fill(.ultraThinMaterial)
                .padding(.bottom, -400)
                .shadow(color: .black.opacity(0.18), radius: 14, y: -3)
        )
    }

    // MARK: Profile group — the managed identity fields

    private var profileGroup: some View {
        VStack(spacing: 0) {
            groupHeader("Profile", systemImage: "person.text.rectangle.fill") {
                Button("Manage") { editingProfile = true }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
            }
            .padding(.bottom, 4)

            manageRow("person.fill", "Name", fieldValue(displayName, fallback: "Traveler"))
            rowDivider
            manageRow("at", "Username", fieldValue(username, prefix: "@"))
            rowDivider
            manageRow("house.fill", "Home base", fieldValue(homeBase))
            rowDivider
            manageRow("envelope.fill", "Email", fieldValue(email))
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .contentShape(.rect)
        .onTapGesture { editingProfile = true }
    }

    private func manageRow(_ icon: String, _ title: String, _ value: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(accent)
                .frame(width: 26)
            Text(title)
            Spacer(minLength: 12)
            Text(value ?? "Not set")
                .foregroundStyle(value == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 11)
    }

    // MARK: Preferences group

    private var preferencesGroup: some View {
        VStack(alignment: .leading, spacing: 16) {
            groupHeader("Preferences", systemImage: "slider.horizontal.3")

            VStack(spacing: 7) {
                fieldLabel("Appearance")
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }

            VStack(spacing: 7) {
                fieldLabel("Distance units")
                Picker("Distance units", selection: $distanceUnitRaw) {
                    ForEach(DistanceUnit.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    // MARK: Notifications group

    private var notificationsGroup: some View {
        VStack(alignment: .leading, spacing: 16) {
            groupHeader("Notifications", systemImage: "bell.badge.fill")

            Toggle(isOn: $notificationsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trip reminders")
                    Text("Get a heads-up before your trips. Turning this on asks for notification permission.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(accent)
            .onChange(of: notificationsEnabled) { _, on in
                if on { Task { await TripNotifications.requestAuthorization() } }
            }

            if notificationsEnabled {
                rowDivider
                Toggle("Check-in reminder", isOn: $notifyCheckIn).tint(accent)
                Toggle("Time to head out", isOn: $notifyDeparture).tint(accent)
                Toggle("Delay alerts", isOn: $notifyDelays).tint(accent)
                Text("A day before a flight, a few hours before you leave, and whenever a tracked flight slips. All on-device — nothing leaves your phone.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            rowDivider

            Toggle(isOn: $liveActivitiesEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Activities")
                    Text("Show the trip in progress on your Lock Screen and Dynamic Island.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(accent)
            .onChange(of: liveActivitiesEnabled) { _, on in
                #if canImport(ActivityKit)
                if !on { TripLiveActivity.endAll() }
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    // MARK: Flight tracking group

    private var flightTrackingGroup: some View {
        VStack(alignment: .leading, spacing: 16) {
            groupHeader("Flight Tracking", systemImage: "dot.radiowaves.left.and.right")

            Toggle(isOn: $flightAutoRefresh) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Auto-refresh")
                    Text("Auto-update a flight once when you open it on the day of travel or while it's airborne. Off keeps every update manual.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(.blue)

            rowDivider

            HStack(spacing: 12) {
                Image(systemName: Secrets.hasFlightRadarToken ? "key.fill" : "key")
                    .foregroundStyle(Secrets.hasFlightRadarToken ? .green : .orange)
                    .frame(width: 26)
                Text("Flightradar24 token")
                Spacer()
                Text(Secrets.hasFlightRadarToken ? "Configured" : "Not set")
                    .foregroundStyle(Secrets.hasFlightRadarToken ? Color.secondary : Color.orange)
                    .fontWeight(.medium)
            }

            if !Secrets.hasFlightRadarToken {
                Text("Copy Secrets.example.plist to \u{201C}Runnit iOS/Secrets.plist\u{201D} and paste your token to enable live tracking. Your token is gitignored and never committed.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text("Flightradar24 tracks flights that are airborne or already flown. Gate, terminal, and baggage details aren't part of its data, and upcoming flights only appear once they take off.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    // MARK: About group

    private var aboutGroup: some View {
        VStack(spacing: 0) {
            groupHeader("About", systemImage: "info.circle.fill")
                .padding(.bottom, 4)
            aboutRow("Navigation app", "Apple Maps", "location.north.line.fill")
            rowDivider
            aboutRow("Version", appVersion, "info.circle")
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func aboutRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(accent).frame(width: 26)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .padding(.vertical, 11)
    }

    // MARK: Shared bits

    private var rowDivider: some View {
        Divider().padding(.leading, 38)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A group header row: a tinted SF Symbol, a bold title, and an optional
    /// trailing accessory (e.g. a "Manage" button).
    private func groupHeader<Accessory: View>(_ title: String, systemImage: String,
                                              @ViewBuilder accessory: () -> Accessory = { EmptyView() }) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
            Text(title).font(.headline)
            Spacer()
            accessory()
        }
    }

    /// Trims a stored field, returning nil (→ "Not set") when empty. An optional
    /// prefix is applied when there's a value; a fallback substitutes for empty.
    private func fieldValue(_ raw: String, prefix: String = "", fallback: String? = nil) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return fallback }
        if !prefix.isEmpty, !trimmed.hasPrefix(prefix) { return prefix + trimmed }
        return trimmed
    }
}

#if DEBUG
#Preview {
    AccountView()
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
#endif
