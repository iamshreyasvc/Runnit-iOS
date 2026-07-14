//
//  QuotaBannerView.swift
//  Runnit iOS
//
//  Home-screen notice shown when the AviationStack monthly free-tier budget is
//  spent. Live flight tracking pauses until the next calendar month.
//

import SwiftUI

struct QuotaBannerView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "airplane.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Live flight tracking paused")
                    .font(.subheadline.weight(.semibold))
                Text("Monthly API limit reached. Resets next month.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular.tint(.orange.opacity(0.22)), in: .rect(cornerRadius: 18))
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
