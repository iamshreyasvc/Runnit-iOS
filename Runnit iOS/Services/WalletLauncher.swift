//
//  WalletLauncher.swift
//  Runnit iOS
//
//  Opens Apple Wallet so a traveler can pull up a boarding pass mid-trip.
//  Isolated behind one type to match MapsLauncher and keep the URL scheme in a
//  single place.
//

import UIKit

enum WalletLauncher {
    /// Open the Wallet app. Wallet exposes no public deep link to a specific
    /// pass, so this opens the app itself (via its legacy Passbook `shoebox://`
    /// scheme, still honored by Wallet) to where boarding passes live.
    static func openBoardingPasses() {
        guard let url = URL(string: "shoebox://") else { return }
        UIApplication.shared.open(url) { opened in
            // If the scheme is ever refused, fall back to the App Store's Wallet
            // landing so the tap still goes somewhere sensible rather than nowhere.
            guard !opened, let fallback = URL(string: "https://apps.apple.com/app/apple-wallet/id1160481993") else { return }
            UIApplication.shared.open(fallback)
        }
    }
}
