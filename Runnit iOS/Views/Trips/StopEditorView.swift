//
//  StopEditorView.swift
//  Runnit iOS
//
//  A glass-styled editor for a single road-trip stop: where it is, what it's for
//  (an icon category like food or gas), and an optional note. Matches the leg
//  editor's look. Reached only from the Edit Trip page.
//

import SwiftUI

struct StopEditorView: View {
    let titleText: String
    let onSave: (RoadStop) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrefKey.appearance) private var appearanceRaw = AppAppearance.dark.rawValue

    private let existingID: UUID
    @State private var place: Place?
    @State private var category: StopCategory
    @State private var note: String

    private let accent: Color = .cyan
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 10)]

    init(titleText: String, stop: RoadStop? = nil, onSave: @escaping (RoadStop) -> Void) {
        self.titleText = titleText
        self.onSave = onSave
        self.existingID = stop?.id ?? UUID()
        _place = State(initialValue: stop?.place)
        _category = State(initialValue: stop?.category ?? .other)
        _note = State(initialValue: stop?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PlanBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        locationCard
                        categoryCard
                        noteCard
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { done() }
                        .fontWeight(.semibold)
                        .disabled(place == nil)
                }
            }
            .tint(accent)
            .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .dark).colorScheme)
        }
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where").font(.headline)
            LocationSearchField(title: "Stop location",
                                systemImage: category.symbol, place: $place)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's it for?").font(.headline)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(StopCategory.allCases) { option in
                    categoryButton(option)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func categoryButton(_ option: StopCategory) -> some View {
        let selected = category == option
        return Button {
            withAnimation(.snappy(duration: 0.2)) { category = option }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: option.symbol)
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(option.tint))
                    .frame(width: 46, height: 42)
                    .background(
                        selected ? AnyShapeStyle(option.tint.gradient)
                                 : AnyShapeStyle(option.tint.opacity(0.16)),
                        in: .rect(cornerRadius: 13)
                    )
                Text(option.label)
                    .font(.caption2)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Note").font(.headline)
            TextField("Optional — e.g. lunch reservation at 1pm", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func done() {
        guard let place else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(RoadStop(id: existingID, place: place, category: category,
                        note: trimmed.isEmpty ? nil : trimmed))
        dismiss()
    }
}

#if DEBUG
#Preview {
    StopEditorView(titleText: "Add Stop") { _ in }
}
#endif
