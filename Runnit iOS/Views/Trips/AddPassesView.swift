//
//  AddPassesView.swift
//  Runnit iOS
//
//  Presents Apple Wallet's own "Add Pass" sheet for a boarding pass the traveler
//  already has (from a confirmation email, the airline app, or a file). This path
//  needs no certificate — it's adding an existing, already-signed `.pkpass`, not
//  minting one. Generating a pass from scratch is the part that needs signing
//  (see PassGenerator).
//

import SwiftUI
import PassKit

/// A thin SwiftUI wrapper over `PKAddPassesViewController`. Present it in a sheet
/// with the passes decoded from a `.pkpass` file.
struct AddPassesView: UIViewControllerRepresentable {
    let passes: [PKPass]
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> PKAddPassesViewController {
        let controller = PKAddPassesViewController(passes: passes) ?? PKAddPassesViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PKAddPassesViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
            onFinish()
        }
    }
}

enum WalletPassImporter {
    /// Decode the passes contained in a `.pkpass` file's data. Returns an empty
    /// array when the file isn't a valid pass.
    static func passes(from data: Data) -> [PKPass] {
        guard let pass = try? PKPass(data: data) else { return [] }
        return [pass]
    }
}
