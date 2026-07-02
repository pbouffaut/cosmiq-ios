import CosmiqKit
import Foundation

struct CosmiqDeviceInfo: Equatable {
    let firmware: Int
    let serial: String
}

struct DiveSyncProgress: Equatable {
    var phase: String
    /// 0...1 across the whole sync.
    var fraction: Double
}

struct SettingsReadResult {
    var settings: CosmiqSettings
    /// Query commands that got no answer; empty means a complete read.
    var failedQueries: [UInt8]
}

/// High-level operations composed from BLE transfers. All calls are serialized
/// by the caller (the UI performs one operation at a time).
@MainActor
final class CosmiqSession {
    private let ble: CosmiqBLEManager

    init(ble: CosmiqBLEManager) {
        self.ble = ble
    }

    // MARK: Settings

    /// The device wedges if commands arrive back-to-back; the official app and
    /// the web controller both leave ~300 ms between queries.
    private static let interCommandGap: Duration = .milliseconds(300)

    func readDeviceInfo() async throws -> CosmiqDeviceInfo {
        try await ble.exclusive {
            let firmware = try await ble.transfer(CosmiqCommand.query(CosmiqCommand.queryFirmware))
            try await Task.sleep(for: Self.interCommandGap)
            let mac = try await ble.transfer(CosmiqCommand.query(CosmiqCommand.queryMacAddress))
            return CosmiqDeviceInfo(
                firmware: Int((firmware.payload.first ?? 0) & 0x3F),
                serial: mac.payload.map { String(format: "%02X", $0) }.joined(separator: ":")
            )
        }
    }

    /// Read every config packet, tolerating individual timeouts: whatever the
    /// device did answer is kept, and the failed queries are reported so the
    /// UI can say what's missing instead of discarding everything.
    func readAllSettings() async throws -> SettingsReadResult {
        try await ble.exclusive {
            var settings = CosmiqSettings()
            var failed: [UInt8] = []
            for command in CosmiqCommand.settingsQueries {
                try await Task.sleep(for: Self.interCommandGap)
                // $60 (freedive alarms 3-6) doesn't exist on the original COSMIQ+,
                // only on the Gen 5 — probe it once with a short timeout instead
                // of the full retry dance.
                let isOptional = command == CosmiqCommand.queryFreediveSecondary
                do {
                    let reply = try await ble.transfer(CosmiqCommand.query(command),
                                                       timeout: isOptional ? 2.0 : 5.0,
                                                       retries: isOptional ? 0 : 1)
                    settings.apply(reply)
                } catch CosmiqProtocolError.timeout {
                    failed.append(command)
                }
            }
            if failed.count == CosmiqCommand.settingsQueries.count {
                throw CosmiqProtocolError.timeout
            }
            return SettingsReadResult(settings: settings, failedQueries: failed)
        }
    }

    /// Write one setting, then read back the affected config packet so the
    /// caller can fold the device's actual stored values into its settings.
    func apply(_ write: CosmiqPacket) async throws -> CosmiqPacket? {
        try await ble.exclusive {
            _ = try await ble.transfer(write)
            guard let verification = CosmiqSettingWrite.verificationQuery(for: write.command) else {
                return nil
            }
            // The device needs a beat before the new value reads back.
            try await Task.sleep(for: .milliseconds(400))
            return try await ble.transfer(CosmiqCommand.query(verification))
        }
    }

    func syncClock() async throws {
        try await ble.exclusive {
            _ = try await ble.transfer(CosmiqSettingWrite.systemTime(Date()))
        }
    }

    // MARK: Dive log download (protocol from libdivecomputer deepblu_cosmiq.c)

    /// Download all dives not present in `knownFingerprints`. Headers of all
    /// dives are fetched first (they're small); profiles only for new dives.
    func downloadDives(knownFingerprints: Set<String>,
                       progress: @escaping (DiveSyncProgress) -> Void) async throws -> [Dive] {
        try await ble.exclusive {
            try await downloadDivesLocked(knownFingerprints: knownFingerprints, progress: progress)
        }
    }

    private func downloadDivesLocked(knownFingerprints: Set<String>,
                                     progress: @escaping (DiveSyncProgress) -> Void) async throws -> [Dive] {
        progress(DiveSyncProgress(phase: "Reading dive count…", fraction: 0))

        try await Task.sleep(for: Self.interCommandGap)
        let countReply = try await ble.transfer(CosmiqCommand.query(CosmiqCommand.diveCount))
        let diveCount = Int(countReply.payload.first ?? 0)
        guard diveCount > 0 else { return [] }

        // Phase 1: headers. Dive 1 is the most recent.
        var headers: [[UInt8]] = []
        for index in 1...diveCount {
            progress(DiveSyncProgress(phase: "Reading dive \(index) of \(diveCount)…",
                                      fraction: 0.3 * Double(index - 1) / Double(diveCount)))
            try await Task.sleep(for: Self.interCommandGap)
            let lengthReply = try await ble.transfer(
                CosmiqPacket(command: CosmiqCommand.diveHeader, payload: [UInt8(index)]))
            let headerLength = Int(lengthReply.payload.first ?? 0)
            guard headerLength == DiveParser.headerSize else {
                throw CosmiqProtocolError.malformedPacket("dive header length \(headerLength)")
            }
            let header = try await ble.receiveBulk(
                command: CosmiqCommand.diveHeaderData, totalBytes: headerLength)
            headers.append(header)
        }

        let newIndexes = headers.indices.filter { index in
            guard let fingerprint = DiveParser.fingerprint(ofHeader: headers[index]) else { return false }
            return !knownFingerprints.contains(fingerprint)
        }
        guard !newIndexes.isEmpty else {
            progress(DiveSyncProgress(phase: "Logbook is up to date", fraction: 1))
            return []
        }

        // Phase 2: profiles for new dives only.
        var dives: [Dive] = []
        for (position, index) in newIndexes.enumerated() {
            let base = 0.3 + 0.7 * Double(position) / Double(newIndexes.count)
            let span = 0.7 / Double(newIndexes.count)
            progress(DiveSyncProgress(phase: "Downloading dive \(position + 1) of \(newIndexes.count)…",
                                      fraction: base))

            try await Task.sleep(for: Self.interCommandGap)
            let lengthReply = try await ble.transfer(
                CosmiqPacket(command: CosmiqCommand.diveProfile, payload: [UInt8(index + 1)]))
            guard lengthReply.payload.count >= 2 else {
                throw CosmiqProtocolError.malformedPacket("dive profile length reply")
            }
            let profileLength = Int(lengthReply.payload[0]) << 8 | Int(lengthReply.payload[1])

            var record = headers[index]
            if profileLength > 0 {
                let profile = try await ble.receiveBulk(
                    command: CosmiqCommand.diveProfileData, totalBytes: profileLength) { received in
                        progress(DiveSyncProgress(
                            phase: "Downloading dive \(position + 1) of \(newIndexes.count)…",
                            fraction: base + span * Double(received) / Double(profileLength)))
                    }
                record += profile
            }
            dives.append(try DiveParser.parse(data: Data(record)))
        }

        progress(DiveSyncProgress(phase: "Done", fraction: 1))
        return dives
    }
}
