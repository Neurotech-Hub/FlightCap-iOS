//
//  FlightCapTelemetry.swift
//  FlightCap
//

import Foundation

// MARK: - Telemetry payload (manufacturer data after company ID)

struct FlightCapTelemetry: Equatable {
    let deviceAddr: Data
    let seq: UInt16
    let distanceMm: Int16
    let interactions: UInt16
    let flags: UInt8
    let vbattMv: UInt16
    let version: UInt8

    var isDistValid: Bool     { flags & Flag.distValid != 0 }
    var isInteractValid: Bool { flags & Flag.interactValid != 0 }
    var isTofErr: Bool        { flags & Flag.tofErr != 0 }
    var isPairMode: Bool      { flags & Flag.pairMode != 0 }
    var isVbattValid: Bool    { flags & Flag.vbattValid != 0 }

    enum Flag {
        static let distValid: UInt8     = 1 << 0
        static let interactValid: UInt8   = 1 << 1
        static let tofErr: UInt8          = 1 << 2
        static let pairMode: UInt8        = 1 << 4
        static let vbattValid: UInt8      = 1 << 5
    }
}

// MARK: - Parser

enum FlightCapTelemetryParser {
    static let companyID: UInt16 = 0x4E48
    static let magic: UInt8 = 0xA5
    static let versionMin: UInt8 = 0x02
    static let versionMax: UInt8 = 0x03

    static let payloadLenV02 = 17
    static let payloadLenV03 = 19

    static func parse(manufacturerData data: Data) -> FlightCapTelemetry? {
        guard data.count >= payloadLenV02 else { return nil }

        let companyID = rdU16LE(data, 0)
        guard companyID == Self.companyID else { return nil }

        let magic = data[2]
        guard magic == Self.magic else { return nil }

        let version = data[3]
        guard version >= versionMin, version <= versionMax else { return nil }
        if version >= 0x03, data.count < payloadLenV03 { return nil }

        let deviceAddr = data.subdata(in: 4..<10)
        guard DeviceAddr.isValid(deviceAddr) else { return nil }

        let seq = rdU16LE(data, 10)
        let distanceMm = rdI16LE(data, 12)
        let interactions = rdU16LE(data, 14)
        let flags = data[16]
        let vbattMv: UInt16 = version >= 0x03 ? rdU16LE(data, 17) : 0

        return FlightCapTelemetry(
            deviceAddr: deviceAddr,
            seq: seq,
            distanceMm: distanceMm,
            interactions: interactions,
            flags: flags,
            vbattMv: vbattMv,
            version: version
        )
    }

    private static func rdU16LE(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func rdI16LE(_ data: Data, _ offset: Int) -> Int16 {
        Int16(bitPattern: rdU16LE(data, offset))
    }
}

// MARK: - Device address helpers

enum DeviceAddr {
    static let byteCount = 6

    static func isValid(_ addr: Data) -> Bool {
        guard addr.count == byteCount else { return false }
        return addr.contains { $0 != 0 }
    }

    /// UI-only formatting — store and compare raw bytes.
    static func format(_ addr: Data) -> String {
        guard addr.count == byteCount else { return "??" }
        return addr.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
