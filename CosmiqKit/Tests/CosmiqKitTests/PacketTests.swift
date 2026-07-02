import XCTest
@testable import CosmiqKit

final class PacketTests: XCTestCase {
    /// The six read queries must match the exact strings the cosmiq5-web
    /// controller sends (readAllSettings in index.html).
    func testQueryEncodingMatchesWebController() {
        let expected: [UInt8: String] = [
            0x58: "#58a60200\n",
            0x5F: "#5f9f0200\n",
            0x5B: "#5ba30200\n",
            0x5C: "#5ca20200\n",
            0x5D: "#5da10200\n",
            0x60: "#609e0200\n",
        ]
        for (command, wire) in expected {
            XCTAssertEqual(CosmiqCommand.query(command).encodedString, wire)
        }
    }

    /// Mode presets from the web controller: #2bd30200, #2bd20201, #2bd10202.
    func testDefaultModeEncoding() {
        XCTAssertEqual(CosmiqSettingWrite.defaultMode(.scuba).encodedString, "#2bd30200\n")
        XCTAssertEqual(CosmiqSettingWrite.defaultMode(.gauge).encodedString, "#2bd20201\n")
        XCTAssertEqual(CosmiqSettingWrite.defaultMode(.freedive).encodedString, "#2bd10202\n")
    }

    /// The documented per-command checksum "targets" are 256 - cmd; verify our
    /// two's-complement checksum against every target in technical_documentation.md.
    func testChecksumMatchesDocumentedTargets() {
        let targets: [UInt8: Int] = [
            0x20: 224, 0x2E: 210, 0x2A: 214, 0x23: 221, 0x24: 220, 0x30: 208,
            0x21: 223, 0x22: 222, 0x2D: 211, 0x27: 217, 0x28: 216, 0x26: 218,
            0x25: 219, 0x31: 207, 0x32: 206,
        ]
        for (command, target) in targets {
            // For an empty payload with length byte L and payload sum S, the web
            // controller computes (target - (L + S)) & 0xFF. Compare on a probe payload.
            let payload: [UInt8] = [0x01, 0x02]
            let webChecksum = UInt8((target - (payload.count * 2 + 3)) & 0xFF)
            XCTAssertEqual(CosmiqPacket.checksum(command: command, payload: payload), webChecksum,
                           "checksum mismatch for cmd \(String(format: "%02x", command))")
        }
    }

    func testSetUnitsMetricEncoding() {
        // sendCalcSum("23", 221, "01", "02") -> checksum 218 = 0xda
        XCTAssertEqual(CosmiqSettingWrite.units(.metric).encodedString, "#23da0201\n")
    }

    func testDecodeValidReply() throws {
        // Dive count reply: cmd 0x40, payload [0x02].
        // checksum = -(0x40 + 0x02 + 0x02) mod 256 = 0xbc
        let packet = try CosmiqPacket.decode(line: "$40bc0202\n")
        XCTAssertEqual(packet.command, 0x40)
        XCTAssertEqual(packet.payload, [0x02])
    }

    func testDecodeIsCaseInsensitiveAndTolerant() throws {
        let packet = try CosmiqPacket.decode(line: "$40BC0202\r\n")
        XCTAssertEqual(packet.payload, [0x02])
    }

    func testEncodeDecodeRoundTrip() throws {
        let original = CosmiqPacket(command: 0x5C, payload: [0x04, 0xB0, 0x00, 0x0A, 0x20, 0x00])
        let decoded = try CosmiqPacket.decode(line: original.encodedString)
        XCTAssertEqual(decoded, original)
    }

    func testDecodeRejectsBadChecksum() {
        XCTAssertThrowsError(try CosmiqPacket.decode(line: "$40bd0202\n")) { error in
            XCTAssertEqual(error as? CosmiqProtocolError, .badChecksum)
        }
    }

    func testDecodeRejectsLengthMismatch() {
        // Length field says 4 hex chars but only one payload byte follows.
        XCTAssertThrowsError(try CosmiqPacket.decode(line: "$40ba0402\n")) { error in
            XCTAssertEqual(error as? CosmiqProtocolError, .lengthMismatch)
        }
    }

    func testDecodeDetectsRejection() {
        XCTAssertThrowsError(try CosmiqPacket.decode(line: "$80000000\n")) { error in
            XCTAssertEqual(error as? CosmiqProtocolError, .commandRejected)
        }
    }

    func testSystemTimeUsesBCD() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 2
        components.hour = 16
        components.minute = 45
        components.second = 9
        let date = Calendar.current.date(from: components)!
        let packet = CosmiqSettingWrite.systemTime(date)
        XCTAssertEqual(packet.payload, [0x26, 0x07, 0x02, 0x16, 0x45, 0x09])
        XCTAssertEqual(packet.command, 0x20)
        // Length byte must be 0x0c (12 hex chars), per the documented Set System Time format.
        XCTAssertTrue(packet.encodedString.hasPrefix("#20"))
        XCTAssertEqual(packet.encodedString.count, 1 + 6 + 12 + 1) // '#' + header + payload + '\n'
    }
}
