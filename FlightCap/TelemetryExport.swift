//
//  TelemetryExport.swift
//  FlightCap
//

import Foundation

enum TelemetryExport {

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func csvString(from records: [TelemetryRecord]) -> String {
        var lines = ["datetime,interactions,distance_mm,user_flag"]
        let sorted = records.sorted { $0.timestamp < $1.timestamp }
        for r in sorted {
            let dt = isoFormatter.string(from: r.timestamp)
            let interactions = r.interactions.map(String.init) ?? ""
            let distance = r.distanceMm.map(String.init) ?? ""
            let flag = r.userFlag ? "true" : "false"
            lines.append("\(dt),\(interactions),\(distance),\(flag)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func writeTempCSV(_ content: String, baseName: String) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let safeBase = baseName.replacingOccurrences(of: " ", with: "_")
        let filename = "\(safeBase)_\(stamp).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
