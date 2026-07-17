//
//  EditProfileView.swift
//  Runnit iOS
//
//  The profile editor sheet: name, @username, home base, email, and the avatar
//  accent. Edits are staged locally and only written back to the stored
//  preferences on Save, so backing out with Cancel leaves the profile untouched.
//

import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    // Bindings straight to the persisted @AppStorage values on the Account tab.
    @Binding var name: String
    @Binding var username: String
    @Binding var homeBase: String
    @Binding var email: String
    @Binding var accentRaw: String

    // Staged copies so Cancel discards and Save commits atomically.
    @State private var draftName = ""
    @State private var draftUsername = ""
    @State private var draftHome = ""
    @State private var draftEmail = ""
    @State private var draftAccent: ProfileAccent = .cyan

    @FocusState private var focused: Field?
    private enum Field { case name, username, home, email }

    private var accent: Color { draftAccent.color }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 22) {
                        avatarPreview.appear(0)
                        identityCard.appear(1)
                        accentCard.appear(2)
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadDrafts)
        }
        .tint(accent)
    }

    // MARK: Live avatar preview

    private var avatarPreview: some View {
        VStack(spacing: 12) {
            ProfileAvatar(name: draftName, accent: accent, size: 92)
                .animation(.snappy, value: draftAccent)
            Text(draftName.trimmingCharacters(in: .whitespaces).isEmpty ? "Traveler" : draftName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: Identity fields

    private var identityCard: some View {
        VStack(spacing: 0) {
            field(icon: "person.fill", title: "Name",
                  placeholder: "Your name", text: $draftName,
                  field: .name, submit: .username)

            divider

            field(icon: "at", title: "Username",
                  placeholder: "username", text: $draftUsername,
                  field: .username, submit: .home,
                  prefix: "@", autocapitalization: .never)

            divider

            field(icon: "house.fill", title: "Home base",
                  placeholder: "SFO · San Francisco", text: $draftHome,
                  field: .home, submit: .email)

            divider

            field(icon: "envelope.fill", title: "Email",
                  placeholder: "you@example.com", text: $draftEmail,
                  field: .email, submit: nil,
                  keyboard: .emailAddress, autocapitalization: .never)
        }
        .glassCard(cornerRadius: 24)
    }

    private var divider: some View {
        Divider().padding(.leading, 42)
    }

    @ViewBuilder
    private func field(icon: String, title: String, placeholder: String,
                       text: Binding<String>, field: Field, submit: Field?,
                       prefix: String? = nil,
                       keyboard: UIKeyboardType = .default,
                       autocapitalization: TextInputAutocapitalization = .words) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(accent)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 1) {
                    if let prefix, !text.wrappedValue.isEmpty {
                        Text(prefix).foregroundStyle(.secondary)
                    }
                    TextField(placeholder, text: text)
                        .font(.body.weight(.medium))
                        .focused($focused, equals: field)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled(field == .username || field == .email)
                        .submitLabel(submit == nil ? .done : .next)
                        .onSubmit { focused = submit }
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
        .onTapGesture { focused = field }
    }

    // MARK: Accent picker

    private var accentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Avatar Color")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4),
                      spacing: 14) {
                ForEach(ProfileAccent.allCases) { option in
                    swatch(option)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24)
    }

    private func swatch(_ option: ProfileAccent) -> some View {
        let isSelected = draftAccent == option
        return Button {
            withAnimation(.snappy) { draftAccent = option }
        } label: {
            Circle()
                .fill(option.color.gradient)
                .frame(height: 46)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay(
                    Circle().strokeBorder(.white.opacity(isSelected ? 0.95 : 0),
                                          lineWidth: 2.5)
                )
                .shadow(color: option.color.opacity(isSelected ? 0.5 : 0), radius: 8, y: 3)
                .scaleEffect(isSelected ? 1.06 : 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Load / save

    private func loadDrafts() {
        draftName = name
        // Show the handle without its leading "@" while editing.
        draftUsername = username.hasPrefix("@") ? String(username.dropFirst()) : username
        draftHome = homeBase
        draftEmail = email
        draftAccent = ProfileAccent(rawValue: accentRaw) ?? .cyan
    }

    private func save() {
        name = draftName.trimmingCharacters(in: .whitespaces)
        // Store the handle normalized: no leading "@", no spaces, lowercased.
        username = draftUsername
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "@", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        homeBase = draftHome.trimmingCharacters(in: .whitespaces)
        email = draftEmail.trimmingCharacters(in: .whitespaces)
        accentRaw = draftAccent.rawValue
        dismiss()
    }
}

#if DEBUG
private struct EditProfilePreview: View {
    @State var name = "Shreyas Chandramouli"
    @State var username = "shreyasvc"
    @State var home = "SFO · San Francisco"
    @State var email = "you@example.com"
    @State var accent = ProfileAccent.cyan.rawValue

    var body: some View {
        EditProfileView(name: $name, username: $username, homeBase: $home,
                        email: $email, accentRaw: $accent)
    }
}

#Preview {
    EditProfilePreview()
        .preferredColorScheme(.dark)
}
#endif
