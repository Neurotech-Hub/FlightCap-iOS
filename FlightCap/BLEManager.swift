//
//  BLEManager.swift
//  FlightCap
//

import Foundation
import CoreBluetooth
import Combine

/// One point in a rolling time-series buffer.
/// `value == .nan` signals an invalid sample (omitted from the chart).
struct Sample: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

enum AppState: Equatable {
    case idle
    case scanning
    case listening
}

struct DiscoveredCap: Identifiable, Equatable {
    let id: Data
    var displayName: String
    var rssi: Int
    var lastSeen: Date
    var isPairMode: Bool
    var lastSeq: UInt16?
}

@MainActor
final class BLEManager: NSObject, ObservableObject {

    /// Rolling plot window — only samples within the last 5 minutes are kept.
    static let plotWindow: TimeInterval = 5 * 60
    static let scanTimeout: TimeInterval = 60

    private static let scanOptions: [String: Any] = [
        CBCentralManagerScanOptionAllowDuplicatesKey: true
    ]

    // MARK: - Published state

    @Published private(set) var state: AppState = .idle
    @Published private(set) var discoveredCaps: [DiscoveredCap] = []
    @Published private(set) var selectedCap: DiscoveredCap?
    @Published private(set) var motionSamples: [Sample] = []
    @Published private(set) var distanceSamples: [Sample] = []
    @Published private(set) var latestVbattMv: UInt16?
    @Published private(set) var latestVbattValid = false
    @Published private(set) var lastDataReceived: Date?
    @Published var lastMessage: String?

    // MARK: - Private

    private var central: CBCentralManager!
    private var lastRecordedSeq: UInt16?
    private var scanTimeoutWork: DispatchWorkItem?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func startDiscoveryScan() {
        lastMessage = nil
        discoveredCaps.removeAll(keepingCapacity: true)

        guard central.state == .poweredOn else {
            lastMessage = bluetoothStateMessage(for: central.state)
            return
        }

        state = .scanning
        central.scanForPeripherals(withServices: nil, options: Self.scanOptions)
        scheduleScanTimeout(message: "Scan timed out after 60 s")
    }

    func stopScan() {
        cancelScanTimeout()
        if central.isScanning { central.stopScan() }
        if state == .scanning { state = .idle }
    }

    func selectCap(_ cap: DiscoveredCap) {
        cancelScanTimeout()
        if central.isScanning { central.stopScan() }

        selectedCap = cap
        resetBuffers()
        lastDataReceived = nil
        state = .listening
        lastMessage = nil

        guard central.state == .poweredOn else {
            lastMessage = bluetoothStateMessage(for: central.state)
            return
        }

        central.scanForPeripherals(withServices: nil, options: Self.scanOptions)
    }

    func leaveListening() {
        cancelScanTimeout()
        if central.isScanning { central.stopScan() }
        selectedCap = nil
        lastRecordedSeq = nil
        lastDataReceived = nil
        state = .idle
    }

    func clearPlots() {
        resetBuffers()
    }

    // MARK: - Helpers

    private func resetBuffers() {
        motionSamples.removeAll(keepingCapacity: true)
        distanceSamples.removeAll(keepingCapacity: true)
        lastRecordedSeq = nil
        latestVbattMv = nil
        latestVbattValid = false
    }

    private func scheduleScanTimeout(message: String) {
        cancelScanTimeout()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.state == .scanning else { return }
            self.central.stopScan()
            self.state = .idle
            self.lastMessage = message
        }
        scanTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanTimeout, execute: work)
    }

    private func cancelScanTimeout() {
        scanTimeoutWork?.cancel()
        scanTimeoutWork = nil
    }

    private func upsertDiscoveredCap(telemetry: FlightCapTelemetry, rssi: Int) {
        let addr = telemetry.deviceAddr
        let now = Date()

        if let idx = discoveredCaps.firstIndex(where: { $0.id.elementsEqual(addr) }) {
            discoveredCaps[idx].rssi = rssi
            discoveredCaps[idx].lastSeen = now
            discoveredCaps[idx].isPairMode = telemetry.isPairMode
            discoveredCaps[idx].lastSeq = telemetry.seq
        } else {
            discoveredCaps.append(DiscoveredCap(
                id: addr,
                displayName: DeviceAddr.format(addr),
                rssi: rssi,
                lastSeen: now,
                isPairMode: telemetry.isPairMode,
                lastSeq: telemetry.seq
            ))
        }

        discoveredCaps.sort { $0.lastSeen > $1.lastSeen }
    }

    private func handleListeningTelemetry(_ telemetry: FlightCapTelemetry) {
        guard let selected = selectedCap else { return }
        guard telemetry.deviceAddr.elementsEqual(selected.id) else { return }

        lastDataReceived = Date()
        pruneAllSamples()

        if let lastSeq = lastRecordedSeq, lastSeq == telemetry.seq { return }
        lastRecordedSeq = telemetry.seq

        let motionValue: Double = telemetry.isInteractValid
            ? Double(telemetry.interactions)
            : .nan
        let distanceValue: Double = telemetry.isDistValid
            ? Double(telemetry.distanceMm)
            : .nan

        let recordedAt = Date()
        appendMotion(motionValue, at: recordedAt)
        appendDistance(distanceValue, at: recordedAt)

        latestVbattValid = telemetry.isVbattValid
        latestVbattMv = telemetry.isVbattValid ? telemetry.vbattMv : nil
    }

    private func appendMotion(_ value: Double, at timestamp: Date) {
        motionSamples.append(Sample(timestamp: timestamp, value: value))
        pruneSamples(&motionSamples)
    }

    private func appendDistance(_ value: Double, at timestamp: Date) {
        distanceSamples.append(Sample(timestamp: timestamp, value: value))
        pruneSamples(&distanceSamples)
    }

    private func pruneSamples(_ samples: inout [Sample]) {
        let cutoff = Date().addingTimeInterval(-Self.plotWindow)
        if let firstKeep = samples.firstIndex(where: { $0.timestamp >= cutoff }) {
            if firstKeep > 0 {
                samples.removeFirst(firstKeep)
            }
        } else {
            samples.removeAll(keepingCapacity: true)
        }
    }

    private func pruneAllSamples() {
        pruneSamples(&motionSamples)
        pruneSamples(&distanceSamples)
    }

    private func bluetoothStateMessage(for state: CBManagerState) -> String? {
        switch state {
        case .poweredOff:   return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission denied"
        case .unsupported:  return "Bluetooth not supported"
        case .resetting:    return "Bluetooth is resetting…"
        case .unknown:      return "Bluetooth state unknown"
        case .poweredOn:    return nil
        @unknown default:   return nil
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state != .poweredOn, self.state != .idle {
                self.cancelScanTimeout()
                if central.isScanning { central.stopScan() }
                self.selectedCap = nil
                self.lastRecordedSeq = nil
                self.lastDataReceived = nil
                self.state = .idle
                self.lastMessage = self.bluetoothStateMessage(for: central.state)
            } else if central.state != .poweredOn {
                self.lastMessage = self.bluetoothStateMessage(for: central.state)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        guard let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let telemetry = FlightCapTelemetryParser.parse(manufacturerData: mfg) else {
            return
        }

        let rssi = RSSI.intValue

        Task { @MainActor in
            switch self.state {
            case .scanning:
                self.upsertDiscoveredCap(telemetry: telemetry, rssi: rssi)
            case .listening:
                self.handleListeningTelemetry(telemetry)
            case .idle:
                break
            }
        }
    }
}
