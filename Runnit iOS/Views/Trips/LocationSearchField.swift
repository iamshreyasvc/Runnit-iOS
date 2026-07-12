//
//  LocationSearchField.swift
//  Runnit iOS
//
//  A tappable field that presents a location search sheet backed by
//  LocationSearchService, and returns a resolved Place binding.
//

import SwiftUI
import MapKit

struct LocationSearchField: View {
    let title: String
    let systemImage: String
    @Binding var place: Place?

    @State private var showingSearch = false

    var body: some View {
        Button {
            showingSearch = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let place {
                        Text(place.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        if !place.subtitle.isEmpty {
                            Text(place.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Search…")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSearch) {
            LocationSearchSheet(title: title) { resolved in
                place = resolved
                showingSearch = false
            }
        }
    }
}

private struct LocationSearchSheet: View {
    let title: String
    let onSelect: (Place) -> Void

    @State private var service = LocationSearchService()
    @State private var isResolving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if service.query.isEmpty {
                    ContentUnavailableView(
                        "Search a place",
                        systemImage: "mappin.and.ellipse",
                        description: Text("Airports, stations, cities or addresses.")
                    )
                } else if service.suggestions.isEmpty {
                    ContentUnavailableView.search(text: service.query)
                } else {
                    ForEach(service.suggestions, id: \.self) { suggestion in
                        Button {
                            select(suggestion)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .foregroundStyle(.primary)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $service.query, prompt: "Search location")
            .overlay {
                if isResolving {
                    ProgressView().controlSize(.large)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func select(_ suggestion: MKLocalSearchCompletion) {
        isResolving = true
        Task {
            if let place = await service.resolve(suggestion) {
                onSelect(place)
            }
            isResolving = false
        }
    }
}
