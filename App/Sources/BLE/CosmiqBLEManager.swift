import CoreBluetooth
import CosmiqKit
import Foundation
import os

/// CoreBluetooth transport for the COSMIQ+.
///
/// The device exposes the Nordic UART Service; commands go out on the write
/// characteristic and replies arrive as notifications, possibly split across
/// several BLE packets, each line terminated by '\n'.
@MainActor
final class CosmiqBLEManager: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")

    enum ConnectionState: Equatable {
        case bluetoothOff
        case idle
        case scanning
        case connecting
        case ready
        case failed(String)

        var isConnected: Bool { self == .ready }
    }

    struct DiscoveredDevice: Identifiable {
        let peripheral: CBPeripheral
        let name: String
        let rssi: Int
        var id: UUID { peripheral.identifier }
    }

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var discovered: [DiscoveredDevice] = []
    @Published private(set) var deviceName: String?
    /// Rolling log of raw packets, for the diagnostics screen.
    @Published private(set) var packetLog: [String] = []

    private let log = Logger(subsystem: "com.pbouffaut.CosmiqCompanion", category: "ble")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxBuffer = Data()

    /// Continuation waiting for the next decoded packet, if any.
    private var pendingReceive: CheckedContinuation<CosmiqPacket, Error>?
    private var receiveTimeoutTask: Task<Void, Never>?
    /// Packets that arrived while nobody was waiting — consumed by the next
    /// `receive()` so fast replies are never dropped.
    private var inbox: [CosmiqPacket] = []

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: Connection lifecycle

    func startScan() {
        guard central.state == .poweredOn else { return }
        discovered = []
        state = .scanning
        // The COSMIQ+ advertises the NUS service; scan broadly and filter by
        // name (like the web controller) so renamed units still show up.
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    func stopScan() {
        central.stopScan()
        if state == .scanning { state = .idle }
    }

    func connect(_ device: DiscoveredDevice) {
        stopScan()
        state = .connecting
        peripheral = device.peripheral
        deviceName = device.name
        device.peripheral.delegate = self
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        cleanupConnection(error: nil)
    }

    private func cleanupConnection(error: Error?) {
        peripheral = nil
        txCharacteristic = nil
        rxBuffer.removeAll()
        inbox.removeAll()
        failPending(with: error ?? CosmiqProtocolError.disconnected)
        if case .failed = state {} else {
            state = .idle
        }
    }

    // MARK: Packet I/O

    /// Send a packet without waiting for a reply.
    func send(_ packet: CosmiqPacket) throws {
        guard let peripheral, let txCharacteristic else {
            throw CosmiqProtocolError.disconnected
        }
        appendLog("TX \(packet.encodedString.trimmingCharacters(in: .newlines))")
        let type: CBCharacteristicWriteType =
            txCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(packet.encodedData, for: txCharacteristic, type: type)
    }

    /// Wait for the next decoded packet from the device, draining any packet
    /// that arrived while nobody was listening first.
    func receive(timeout: TimeInterval = 5.0) async throws -> CosmiqPacket {
        if !inbox.isEmpty {
            return inbox.removeFirst()
        }
        guard pendingReceive == nil else {
            throw CosmiqProtocolError.malformedPacket("overlapping receive")
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingReceive = continuation
            receiveTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                self?.failPending(with: CosmiqProtocolError.timeout)
            }
        }
    }

    /// Send a command and wait for the reply with a matching command byte.
    /// Packets with other command bytes (stale replies) are skipped, and a
    /// timed-out command is re-sent once — the device can be slow to answer
    /// the first command after connecting.
    func transfer(_ packet: CosmiqPacket, timeout: TimeInterval = 5.0,
                  retries: Int = 1) async throws -> CosmiqPacket {
        var attempt = 0
        while true {
            do {
                try send(packet)
                while true {
                    let reply = try await receive(timeout: timeout)
                    if reply.command == packet.command { return reply }
                    log.warning("Skipping out-of-band reply 0x\(String(format: "%02x", reply.command))")
                }
            } catch CosmiqProtocolError.timeout where attempt < retries {
                attempt += 1
                appendLog("-- timeout, resending (attempt \(attempt + 1))")
            }
        }
    }

    /// Collect `totalBytes` of bulk data streamed as packets with command
    /// `command` (dive headers: 0x42, dive profiles: 0x44).
    func receiveBulk(command: UInt8, totalBytes: Int, timeout: TimeInterval = 5.0,
                     progress: ((Int) -> Void)? = nil) async throws -> [UInt8] {
        var data: [UInt8] = []
        data.reserveCapacity(totalBytes)
        while data.count < totalBytes {
            let packet = try await receive(timeout: timeout)
            guard packet.command == command else {
                throw CosmiqProtocolError.unexpectedResponse(command: packet.command)
            }
            data.append(contentsOf: packet.payload)
            progress?(data.count)
        }
        return data
    }

    private func resumePending(with packet: CosmiqPacket) {
        guard let pendingReceive else {
            // Nobody is waiting yet — keep the packet for the next receive().
            inbox.append(packet)
            if inbox.count > 64 { inbox.removeFirst(inbox.count - 64) }
            return
        }
        receiveTimeoutTask?.cancel()
        receiveTimeoutTask = nil
        pendingReceive.resume(returning: packet)
        self.pendingReceive = nil
    }

    private func failPending(with error: Error) {
        receiveTimeoutTask?.cancel()
        receiveTimeoutTask = nil
        pendingReceive?.resume(throwing: error)
        pendingReceive = nil
    }

    private func handleIncoming(_ chunk: Data) {
        rxBuffer.append(chunk)
        while let newlineIndex = rxBuffer.firstIndex(of: 0x0A) {
            let lineData = rxBuffer[rxBuffer.startIndex...newlineIndex]
            rxBuffer.removeSubrange(rxBuffer.startIndex...newlineIndex)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            appendLog("RX \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
            do {
                let packet = try CosmiqPacket.decode(line: line)
                resumePending(with: packet)
            } catch {
                log.error("Packet decode failed: \(error.localizedDescription)")
                failPending(with: error)
            }
        }
    }

    private func appendLog(_ entry: String) {
        packetLog.append(entry)
        if packetLog.count > 200 {
            packetLog.removeFirst(packetLog.count - 200)
        }
    }
}

// MARK: - CBCentralManagerDelegate / CBPeripheralDelegate

extension CosmiqBLEManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let centralState = central.state
        Task { @MainActor in
            switch centralState {
            case .poweredOn:
                if self.state == .bluetoothOff { self.state = .idle }
            case .poweredOff, .unauthorized, .unsupported:
                self.state = .bluetoothOff
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rssi = RSSI.intValue
        Task { @MainActor in
            let name = advertisedName ?? peripheral.name ?? ""
            // Same name filter as the web controller.
            guard name.hasPrefix("COS") || name.hasPrefix("Deep") else { return }
            if let index = self.discovered.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discovered[index] = DiscoveredDevice(peripheral: peripheral, name: name, rssi: rssi)
            } else {
                self.discovered.append(DiscoveredDevice(peripheral: peripheral, name: name, rssi: rssi))
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        let message = error?.localizedDescription ?? "Connection failed"
        Task { @MainActor in
            self.state = .failed(message)
            self.cleanupConnection(error: error)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.cleanupConnection(error: error)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
                self.state = .failed("COSMIQ service not found")
                self.disconnect()
                return
            }
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        Task { @MainActor in
            guard let characteristics = service.characteristics else { return }
            for characteristic in characteristics {
                if characteristic.properties.contains(.write)
                    || characteristic.properties.contains(.writeWithoutResponse) {
                    self.txCharacteristic = characteristic
                }
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            if self.txCharacteristic != nil, characteristic.isNotifying {
                self.state = .ready
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard let value = characteristic.value else { return }
        Task { @MainActor in
            self.handleIncoming(value)
        }
    }
}
