//
//  BLEManager.swift
//  FlightCap
//

import Foundation
import CoreBluetooth
import Combine

/// One point in a rolling time-series buffer.
/// `value == .nan` is used to signal an invalid sample so Swift Charts renders a gap.
struct Sample: Identifiable, Equatable {
    let id: Int
    let value: Double
}

enum ConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case connected
}

@MainActor
final class BLEManager: NSObject, ObservableObject {

    // MARK: - GATT contract (FlightCap_BLE_Spec.md, Phase 1)

    static let serviceUUID  = CBUUID(string: "AD2A98A4-2148-4B58-9E14-7E2CBB6C7B01")
    static let motionUUID   = CBUUID(string: "AD2A98A4-2148-4B58-9E14-7E2CBB6C7B02")
    static let distanceUUID = CBUUID(string: "AD2A98A4-2148-4B58-9E14-7E2CBB6C7B03")

    /// Sliding-window length for both plots.
    static let windowSize = 100

    /// Scan timeout before giving up and returning to idle.
    static let scanTimeout: TimeInterval = 10

    // MARK: - Published state

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var motionSamples: [Sample] = []
    @Published private(set) var distanceSamples: [Sample] = []
    @Published var lastMessage: String?

    /// Latest decoded distance sample_count, exposed so the UI can label invalid windows.
    @Published private(set) var latestDistanceSampleCount: UInt16 = 0

    // MARK: - Private

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var motionCharacteristic: CBCharacteristic?
    private var distanceCharacteristic: CBCharacteristic?

    private var motionIndex = 0
    private var distanceIndex = 0

    private var motionSubscribed = false
    private var distanceSubscribed = false

    private var scanTimeoutWork: DispatchWorkItem?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func startScan() {
        lastMessage = nil
        resetBuffers()

        guard central.state == .poweredOn else {
            lastMessage = bluetoothStateMessage(for: central.state)
            return
        }

        state = .scanning
        central.scanForPeripherals(withServices: [Self.serviceUUID])

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.state == .scanning else { return }
            self.central.stopScan()
            self.state = .idle
            self.lastMessage = "No FlightCap found"
        }
        scanTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanTimeout, execute: work)
    }

    // MARK: - Helpers

    private func resetBuffers() {
        motionSamples.removeAll(keepingCapacity: true)
        distanceSamples.removeAll(keepingCapacity: true)
        motionIndex = 0
        distanceIndex = 0
        latestDistanceSampleCount = 0
    }

    private func cancelScanTimeout() {
        scanTimeoutWork?.cancel()
        scanTimeoutWork = nil
    }

    private func teardownConnection(message: String? = nil) {
        cancelScanTimeout()
        if central.isScanning { central.stopScan() }
        peripheral?.delegate = nil
        peripheral = nil
        motionCharacteristic = nil
        distanceCharacteristic = nil
        motionSubscribed = false
        distanceSubscribed = false
        state = .idle
        if let message { lastMessage = message }
    }

    private func appendMotion(_ value: Double) {
        motionSamples.append(Sample(id: motionIndex, value: value))
        motionIndex += 1
        if motionSamples.count > Self.windowSize {
            motionSamples.removeFirst(motionSamples.count - Self.windowSize)
        }
    }

    private func appendDistance(_ value: Double) {
        distanceSamples.append(Sample(id: distanceIndex, value: value))
        distanceIndex += 1
        if distanceSamples.count > Self.windowSize {
            distanceSamples.removeFirst(distanceSamples.count - Self.windowSize)
        }
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
                self.teardownConnection(message: self.bluetoothStateMessage(for: central.state))
            } else if central.state != .poweredOn {
                self.lastMessage = self.bluetoothStateMessage(for: central.state)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        Task { @MainActor in
            guard self.state == .scanning else { return }
            self.cancelScanTimeout()
            central.stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            self.state = .connecting
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.teardownConnection(message: "Failed to connect")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            let msg: String? = (self.state == .connected) ? "Disconnected" : nil
            self.teardownConnection(message: msg)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
                self.teardownConnection(message: "FlightCap service not found")
                return
            }
            peripheral.discoverCharacteristics([Self.motionUUID, Self.distanceUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        Task { @MainActor in
            for chr in service.characteristics ?? [] {
                switch chr.uuid {
                case Self.motionUUID:
                    self.motionCharacteristic = chr
                    peripheral.setNotifyValue(true, for: chr)
                case Self.distanceUUID:
                    self.distanceCharacteristic = chr
                    peripheral.setNotifyValue(true, for: chr)
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            if characteristic.uuid == Self.motionUUID, characteristic.isNotifying {
                self.motionSubscribed = true
            }
            if characteristic.uuid == Self.distanceUUID, characteristic.isNotifying {
                self.distanceSubscribed = true
            }
            if self.motionSubscribed, self.distanceSubscribed, self.state == .connecting {
                self.state = .connected
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case Self.motionUUID:
            guard data.count >= 4 else { return }
            let motion = data.withUnsafeBytes { raw -> UInt32 in
                raw.loadUnaligned(as: UInt32.self)
            }.littleEndian
            Task { @MainActor in
                self.appendMotion(Double(motion))
            }

        case Self.distanceUUID:
            guard data.count >= 4 else { return }
            let mm    = UInt16(data[0]) | (UInt16(data[1]) << 8)
            let count = UInt16(data[2]) | (UInt16(data[3]) << 8)
            let value: Double = count < 4 ? .nan : Double(mm)
            Task { @MainActor in
                self.latestDistanceSampleCount = count
                self.appendDistance(value)
            }

        default:
            break
        }
    }
}
