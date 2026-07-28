//
//  PassGenerator.swift
//  Runnit iOS
//
//  Builds the *payload* of an Apple Wallet boarding pass from a flight leg — the
//  `pass.json` and the `manifest.json` that indexes it by SHA-1. This is the part
//  that can be written with no special entitlements.
//
//  What this deliberately does NOT do: produce a finished, installable `.pkpass`.
//  A `.pkpass` is a ZIP of `pass.json` + `manifest.json` + a PKCS#7 detached
//  `signature` over the manifest, and that signature requires a Pass Type ID
//  certificate and its private key. Wallet rejects any unsigned pass. Signing
//  therefore belongs on a server (or a build step) that holds the certificate —
//  see `PassSigner` and SETUP.md. Until a signer is supplied, `buildPass` returns
//  `.needsSigning` with the payload ready to hand to one.
//
//  To add a boarding pass a traveler *already has* (from a confirmation email,
//  say), no certificate is involved at all — see AddPassesView.
//

import Foundation
import CryptoKit

/// Supplies the detached PKCS#7 signature over a pass manifest. A real
/// implementation wraps the Pass Type ID certificate + key (kept off-device, on a
/// signing service). Left unimplemented here on purpose.
protocol PassSigner {
    /// PKCS#7 detached signature of `manifest` (the bytes of `manifest.json`).
    func signature(for manifest: Data) throws -> Data
}

enum PassGenerator {

    /// Identifiers that must be filled in from your Apple Developer account before
    /// a signed pass will validate. Placeholders until then.
    struct Identity {
        var passTypeIdentifier: String   // e.g. "pass.Runnit.boarding"
        var teamIdentifier: String       // your 10-char Team ID
        var organizationName: String = "Runnit"
    }

    enum Outcome {
        /// Payload is ready but couldn't be finished into a `.pkpass` because no
        /// signer was provided. `passJSON`/`manifest` are ready for one.
        case needsSigning(passJSON: Data, manifest: Data)
        /// A fully assembled, signed `.pkpass` archive.
        case pkpass(Data)
        /// This leg can't become a boarding pass (not a flight, missing details).
        case unsupported
    }

    /// Build a boarding pass for a flight leg. Returns `.pkpass` only when a
    /// `signer` (and a zip assembler) are supplied; otherwise the ready-to-sign
    /// payload.
    static func buildPass(for segment: TripSegment, trip: Trip,
                          identity: Identity, signer: PassSigner? = nil) -> Outcome {
        guard segment.type == .flight else { return .unsupported }

        guard let passJSON = passJSON(for: segment, trip: trip, identity: identity) else {
            return .unsupported
        }
        let manifest = manifest(files: ["pass.json": passJSON])

        guard let signer else { return .needsSigning(passJSON: passJSON, manifest: manifest) }
        // A signer implies the certificate exists; the ZIP assembly of
        // pass.json + manifest.json + signature is the remaining step (a server
        // job in practice). Kept here as the documented seam.
        _ = try? signer.signature(for: manifest)
        return .needsSigning(passJSON: passJSON, manifest: manifest)
    }

    // MARK: pass.json

    /// The `pass.json` document for a boarding pass, as pretty JSON `Data`.
    static func passJSON(for segment: TripSegment, trip: Trip, identity: Identity) -> Data? {
        let dep = segment.origin
        let arr = segment.destination
        let flight = [segment.operatorName, segment.vehicleNumber]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " ")

        var boardingPass: [String: Any] = [
            "transitType": "PKTransitTypeAir",
            "headerFields": [
                field("flight", "FLIGHT", flight.isEmpty ? "—" : flight)
            ],
            "primaryFields": [
                field("depart", dep.codeLabel, dep.displayName),
                field("arrive", arr.codeLabel, arr.displayName)
            ],
            "secondaryFields": [
                field("boards", "DEPARTS", Format.time(segment.departureDate, in: dep.timeZone))
            ]
        ]

        var auxiliary: [[String: Any]] = []
        if let seat = segment.seat, !seat.isEmpty { auxiliary.append(field("seat", "SEAT", seat)) }
        if let gate = segment.boardingPoint, !gate.isEmpty { auxiliary.append(field("gate", "GATE", gate)) }
        if !auxiliary.isEmpty { boardingPass["auxiliaryFields"] = auxiliary }

        var pass: [String: Any] = [
            "formatVersion": 1,
            "passTypeIdentifier": identity.passTypeIdentifier,
            "teamIdentifier": identity.teamIdentifier,
            "organizationName": identity.organizationName,
            "serialNumber": segment.id.uuidString,
            "description": "Boarding pass — \(dep.codeLabel) → \(arr.codeLabel)",
            "boardingPass": boardingPass
        ]

        if let confirmation = segment.confirmation, !confirmation.isEmpty {
            pass["barcode"] = [
                "format": "PKBarcodeFormatQR",
                "message": confirmation,
                "messageEncoding": "iso-8859-1"
            ]
        }

        return try? JSONSerialization.data(withJSONObject: pass, options: [.prettyPrinted, .sortedKeys])
    }

    private static func field(_ key: String, _ label: String, _ value: String) -> [String: Any] {
        ["key": key, "label": label, "value": value]
    }

    // MARK: manifest.json

    /// The `manifest.json` — a map of each file name to the hex SHA-1 of its bytes,
    /// which is exactly what the pass signature is computed over.
    static func manifest(files: [String: Data]) -> Data {
        let hashes = files.mapValues { sha1Hex($0) }
        return (try? JSONSerialization.data(withJSONObject: hashes, options: [.sortedKeys])) ?? Data()
    }

    private static func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
