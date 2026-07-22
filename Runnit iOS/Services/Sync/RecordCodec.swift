//
//  RecordCodec.swift
//  Runnit iOS
//
//  Translates between the SwiftData models and CloudKit's CKRecord.
//
//  SwiftData stays the source of truth; CloudKit is only the transport. Nothing
//  here touches the network or a ModelContext, which keeps the whole mapping —
//  the part most likely to silently drop a field — unit-testable.
//
//  Two conventions run through the file:
//
//  * A record's name is the model's own `id` UUID, so the same trip is the same
//    record on every device without a lookup table.
//  * Codable value types (Place, RoadStop, RoutePoint) are stored as JSON Data
//    rather than exploded into columns. They already round-trip through Codable
//    for SwiftData, so reusing it means one definition of the wire format.
//

import CloudKit
import Foundation

enum RecordType {
    static let trip = "Trip"
    static let segment = "TripSegment"
    static let flightStatus = "FlightStatusRecord"
}

enum RecordCodec {

    /// CloudKit rejects records over 1 MB. A flown track is the only field that
    /// could plausibly approach it, so oversized geometry is dropped rather than
    /// failing the whole trip's upload — the receiving device refetches it.
    static let maxFieldBytes = 700_000

    // MARK: - Zones

    /// Every trip owns a zone, so sharing it is just attaching a CKShare to the
    /// zone — records never have to move between zones.
    static func zoneName(for tripID: UUID) -> String {
        "trip-\(tripID.uuidString)"
    }

    /// The trip id encoded in a zone name, or nil if it isn't one of ours.
    static func tripID(fromZoneName name: String) -> UUID? {
        guard name.hasPrefix("trip-") else { return nil }
        return UUID(uuidString: String(name.dropFirst("trip-".count)))
    }

    // MARK: - Trip

    /// Encode a trip. Reuses the stored system fields when we've seen the server
    /// copy before, so the change tag survives and CloudKit can detect conflicts.
    static func record(for trip: Trip, in zoneID: CKRecordZone.ID) -> CKRecord {
        let record = existingRecord(from: trip.ckSystemFields)
            ?? CKRecord(recordType: RecordType.trip,
                        recordID: CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID))

        record["type"] = trip.type.rawValue
        record["title"] = trip.title
        record["origin"] = encode(trip.origin)
        record["destination"] = encode(trip.destination)
        record["departureDate"] = trip.departureDate
        record["arrivalDate"] = trip.arrivalDate
        record["operatorName"] = trip.operatorName
        record["vehicleNumber"] = trip.vehicleNumber
        record["boardingPoint"] = trip.boardingPoint
        record["seat"] = trip.seat
        record["confirmation"] = trip.confirmation
        record["notes"] = trip.notes
        record["createdAt"] = trip.createdAt
        record["updatedAt"] = trip.updatedAt
        return record
    }

    /// Overwrite a trip's travel data from a server record.
    ///
    /// Deliberately leaves the local-only bookkeeping alone — `isSample`,
    /// `zoneName`, `ownerName`, share state — because those describe this
    /// device's relationship to the trip, not the trip itself.
    static func apply(_ record: CKRecord, to trip: Trip) {
        if let raw = record["type"] as? String, let type = TripType(rawValue: raw) {
            trip.type = type
        }
        trip.title = record["title"] as? String ?? trip.title
        if let origin: Place = decode(record["origin"]) { trip.origin = origin }
        if let destination: Place = decode(record["destination"]) { trip.destination = destination }
        trip.departureDate = record["departureDate"] as? Date ?? trip.departureDate
        trip.arrivalDate = record["arrivalDate"] as? Date
        trip.operatorName = record["operatorName"] as? String
        trip.vehicleNumber = record["vehicleNumber"] as? String
        trip.boardingPoint = record["boardingPoint"] as? String
        trip.seat = record["seat"] as? String
        trip.confirmation = record["confirmation"] as? String
        trip.notes = record["notes"] as? String
        trip.createdAt = record["createdAt"] as? Date ?? trip.createdAt
        trip.updatedAt = record["updatedAt"] as? Date ?? Date()
        // This version came from the server, so it is by definition already
        // synced — without this the next sweep would upload it straight back.
        trip.syncedAt = trip.updatedAt
        trip.ckSystemFields = archiveSystemFields(record)
    }

    /// Build a brand-new local trip for a record we've never seen — a trip
    /// someone shared with us, or one synced down from another device.
    static func makeTrip(from record: CKRecord) -> Trip? {
        guard record.recordType == RecordType.trip,
              let id = UUID(uuidString: record.recordID.recordName)
        else { return nil }

        let trip = Trip(id: id, origin: .init(name: "", latitude: 0, longitude: 0),
                        destination: .init(name: "", latitude: 0, longitude: 0))
        apply(record, to: trip)
        trip.zoneName = record.recordID.zoneID.zoneName
        return trip
    }

    // MARK: - Segment

    /// Encode a leg. The `parent` reference ties it to its trip so CloudKit
    /// treats the trip and its legs as one shareable hierarchy.
    static func record(for segment: TripSegment, tripID: UUID, in zoneID: CKRecordZone.ID) -> CKRecord {
        let record = existingRecord(from: segment.ckSystemFields)
            ?? CKRecord(recordType: RecordType.segment,
                        recordID: CKRecord.ID(recordName: segment.id.uuidString, zoneID: zoneID))

        let tripRef = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: tripID.uuidString, zoneID: zoneID),
            action: .deleteSelf
        )
        record["trip"] = tripRef
        record.parent = CKRecord.Reference(recordID: tripRef.recordID, action: .none)

        record["type"] = segment.type.rawValue
        record["origin"] = encode(segment.origin)
        record["destination"] = encode(segment.destination)
        record["departureDate"] = segment.departureDate
        record["arrivalDate"] = segment.arrivalDate
        record["operatorName"] = segment.operatorName
        record["vehicleNumber"] = segment.vehicleNumber
        record["boardingPoint"] = segment.boardingPoint
        record["seat"] = segment.seat
        record["confirmation"] = segment.confirmation
        record["stops"] = encode(segment.stops)
        record["routePolyline"] = encode(segment.routePolyline, maxBytes: maxFieldBytes)
        record["routeSignature"] = segment.routeSignature
        record["routeCheckedAt"] = segment.routeCheckedAt
        record["order"] = segment.order
        record["updatedAt"] = segment.updatedAt
        return record
    }

    static func apply(_ record: CKRecord, to segment: TripSegment) {
        if let raw = record["type"] as? String, let type = TripType(rawValue: raw) {
            segment.type = type
        }
        if let origin: Place = decode(record["origin"]) { segment.origin = origin }
        if let destination: Place = decode(record["destination"]) { segment.destination = destination }
        segment.departureDate = record["departureDate"] as? Date ?? segment.departureDate
        segment.arrivalDate = record["arrivalDate"] as? Date
        segment.operatorName = record["operatorName"] as? String
        segment.vehicleNumber = record["vehicleNumber"] as? String
        segment.boardingPoint = record["boardingPoint"] as? String
        segment.seat = record["seat"] as? String
        segment.confirmation = record["confirmation"] as? String
        segment.stops = decode(record["stops"]) ?? []
        // A dropped-for-size polyline arrives empty; `needsRouteRefresh` then
        // recomputes it locally rather than leaving the map on a straight line.
        segment.routePolyline = decode(record["routePolyline"]) ?? []
        segment.routeSignature = record["routeSignature"] as? String
        segment.routeCheckedAt = record["routeCheckedAt"] as? Date
        segment.order = record["order"] as? Int ?? segment.order
        segment.updatedAt = record["updatedAt"] as? Date ?? Date()
        segment.syncedAt = segment.updatedAt
        segment.ckSystemFields = archiveSystemFields(record)
    }

    static func makeSegment(from record: CKRecord) -> TripSegment? {
        guard record.recordType == RecordType.segment,
              let id = UUID(uuidString: record.recordID.recordName)
        else { return nil }

        let segment = TripSegment(id: id,
                                  origin: .init(name: "", latitude: 0, longitude: 0),
                                  destination: .init(name: "", latitude: 0, longitude: 0))
        apply(record, to: segment)
        return segment
    }

    /// The trip a leg record belongs to, read from its reference.
    static func tripID(ofSegmentRecord record: CKRecord) -> UUID? {
        guard let ref = record["trip"] as? CKRecord.Reference else { return nil }
        return UUID(uuidString: ref.recordID.recordName)
    }

    // MARK: - Flight status

    /// Encode a live-status snapshot. These ride in their trip's zone so everyone
    /// invited sees the same gate and delay without each device spending the
    /// shared API budget.
    static func record(for status: FlightStatusRecord, in zoneID: CKRecordZone.ID) -> CKRecord {
        let record = existingRecord(from: status.ckSystemFields)
            ?? CKRecord(recordType: RecordType.flightStatus,
                        recordID: CKRecord.ID(recordName: statusRecordName(for: status.segmentID),
                                              zoneID: zoneID))

        record["segmentID"] = status.segmentID.uuidString
        record["status"] = status.statusRaw
        record["flightIata"] = status.flightIata
        record["airlineName"] = status.airlineName

        record["depScheduled"] = status.depScheduled
        record["depEstimated"] = status.depEstimated
        record["depActual"] = status.depActual
        record["depTerminal"] = status.depTerminal
        record["depGate"] = status.depGate
        record["depDelayMinutes"] = status.depDelayMinutes
        record["depTimeZoneID"] = status.depTimeZoneID

        record["arrScheduled"] = status.arrScheduled
        record["arrEstimated"] = status.arrEstimated
        record["arrActual"] = status.arrActual
        record["arrTerminal"] = status.arrTerminal
        record["arrGate"] = status.arrGate
        record["arrBaggage"] = status.arrBaggage
        record["arrDelayMinutes"] = status.arrDelayMinutes
        record["arrTimeZoneID"] = status.arrTimeZoneID

        record["liveLatitude"] = status.liveLatitude
        record["liveLongitude"] = status.liveLongitude
        record["liveAltitude"] = status.liveAltitude
        record["liveDirection"] = status.liveDirection
        record["liveSpeed"] = status.liveSpeed
        record["liveIsGround"] = status.liveIsGround.map { $0 ? 1 : 0 }
        record["liveUpdated"] = status.liveUpdated

        record["fetchedAt"] = status.fetchedAt
        record["isFinal"] = (status.isFinal ? 1 : 0)
        record["didFindData"] = (status.didFindData ? 1 : 0)
        record["updatedAt"] = status.updatedAt
        return record
    }

    static func apply(_ record: CKRecord, to status: FlightStatusRecord) {
        if let raw = record["segmentID"] as? String, let id = UUID(uuidString: raw) {
            status.segmentID = id
        }
        status.statusRaw = record["status"] as? String ?? status.statusRaw
        status.flightIata = record["flightIata"] as? String
        status.airlineName = record["airlineName"] as? String

        status.depScheduled = record["depScheduled"] as? Date
        status.depEstimated = record["depEstimated"] as? Date
        status.depActual = record["depActual"] as? Date
        status.depTerminal = record["depTerminal"] as? String
        status.depGate = record["depGate"] as? String
        status.depDelayMinutes = record["depDelayMinutes"] as? Int
        status.depTimeZoneID = record["depTimeZoneID"] as? String

        status.arrScheduled = record["arrScheduled"] as? Date
        status.arrEstimated = record["arrEstimated"] as? Date
        status.arrActual = record["arrActual"] as? Date
        status.arrTerminal = record["arrTerminal"] as? String
        status.arrGate = record["arrGate"] as? String
        status.arrBaggage = record["arrBaggage"] as? String
        status.arrDelayMinutes = record["arrDelayMinutes"] as? Int
        status.arrTimeZoneID = record["arrTimeZoneID"] as? String

        status.liveLatitude = record["liveLatitude"] as? Double
        status.liveLongitude = record["liveLongitude"] as? Double
        status.liveAltitude = record["liveAltitude"] as? Double
        status.liveDirection = record["liveDirection"] as? Double
        status.liveSpeed = record["liveSpeed"] as? Double
        status.liveIsGround = (record["liveIsGround"] as? Int).map { $0 != 0 }
        status.liveUpdated = record["liveUpdated"] as? Date

        status.fetchedAt = record["fetchedAt"] as? Date ?? status.fetchedAt
        status.isFinal = (record["isFinal"] as? Int ?? 0) != 0
        status.didFindData = (record["didFindData"] as? Int ?? 1) != 0
        status.updatedAt = record["updatedAt"] as? Date ?? Date()
        status.syncedAt = status.updatedAt
        status.zoneName = record.recordID.zoneID.zoneName
        status.ckSystemFields = archiveSystemFields(record)
    }

    static func makeStatus(from record: CKRecord) -> FlightStatusRecord? {
        guard record.recordType == RecordType.flightStatus,
              let raw = record["segmentID"] as? String,
              let segmentID = UUID(uuidString: raw)
        else { return nil }

        let status = FlightStatusRecord(segmentID: segmentID)
        apply(record, to: status)
        return status
    }

    /// A snapshot has no id of its own — there's at most one per leg, so the
    /// leg's id (prefixed, to stay distinct from the leg's own record) names it.
    static func statusRecordName(for segmentID: UUID) -> String {
        "status-\(segmentID.uuidString)"
    }

    // MARK: - System fields

    /// Archive a record's system fields (id, change tag, timestamps) so the next
    /// upload updates the server copy instead of blindly replacing it.
    static func archiveSystemFields(_ record: CKRecord) -> Data? {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    /// Rebuild the bare record (system fields only, no values) we last saw.
    static func existingRecord(from data: Data?) -> CKRecord? {
        guard let data,
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data)
        else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }

    // MARK: - Codable payloads

    /// JSON-encode a Codable value for a record field. Values larger than
    /// `maxBytes` are dropped rather than failing the whole record's upload.
    static func encode<T: Encodable>(_ value: T, maxBytes: Int? = nil) -> Data? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        if let maxBytes, data.count > maxBytes { return nil }
        return data
    }

    static func decode<T: Decodable>(_ value: Any?) -> T? {
        guard let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
