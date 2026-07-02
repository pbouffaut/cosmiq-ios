import Foundation

/// Errors thrown by the COSMIQ+ wire protocol codec.
public enum CosmiqProtocolError: Error, Equatable, LocalizedError {
    case payloadTooLarge
    case malformedPacket(String)
    case badChecksum
    case lengthMismatch
    /// The device answered with a `$80...` packet, meaning it refused the command.
    case commandRejected
    case unexpectedResponse(command: UInt8)
    case timeout
    case disconnected

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge: return "Payload too large for a single packet."
        case .malformedPacket(let line): return "Malformed packet: \(line)"
        case .badChecksum: return "Packet checksum mismatch."
        case .lengthMismatch: return "Packet length field mismatch."
        case .commandRejected: return "The dive computer rejected the command."
        case .unexpectedResponse(let command):
            return String(format: "Unexpected response command 0x%02X.", command)
        case .timeout: return "The dive computer did not answer in time."
        case .disconnected: return "The dive computer disconnected."
        }
    }
}

/// One COSMIQ+ BLE packet.
///
/// The device speaks an ASCII, hex-encoded, newline-terminated protocol over the
/// Nordic UART Service:
///
///     '#' [CMD] [CHECKSUM] [LENGTH] [PAYLOAD...] '\n'    (phone -> device)
///     '$' [CMD] [CHECKSUM] [LENGTH] [PAYLOAD...] '\n'    (device -> phone)
///
/// where every bracketed field is one byte rendered as two hex characters, and
/// LENGTH counts the *hex characters* of the payload (i.e. 2x the byte count).
/// The checksum is the two's complement of (CMD + LENGTH + sum of payload bytes),
/// so the byte sum of a whole decoded packet is always 0 mod 256.
public struct CosmiqPacket: Equatable, Sendable {
    /// Maximum payload bytes in one packet (mirrors libdivecomputer's MAX_DATA).
    public static let maxPayload = 20

    public let command: UInt8
    public let payload: [UInt8]

    public init(command: UInt8, payload: [UInt8] = [0x00]) {
        self.command = command
        self.payload = payload
    }

    public static func checksum(command: UInt8, payload: [UInt8]) -> UInt8 {
        var sum = command &+ UInt8(truncatingIfNeeded: payload.count * 2)
        for byte in payload { sum = sum &+ byte }
        return UInt8(0) &- sum
    }

    /// Wire representation, e.g. `#5f9f0200\n`. Lowercase hex, matching the
    /// official app and the cosmiq5-web controller.
    public var encodedString: String {
        var raw = [command, Self.checksum(command: command, payload: payload),
                   UInt8(truncatingIfNeeded: payload.count * 2)]
        raw.append(contentsOf: payload)
        return "#" + raw.hexString + "\n"
    }

    public var encodedData: Data { Data(encodedString.utf8) }

    /// Decode one complete line (with or without the leading `$`/`#` and
    /// trailing newline). Throws `.commandRejected` for `$80...` error replies.
    public static func decode(line: String) throws -> CosmiqPacket {
        // Keep only hex characters; strips '$'/'#', '\r', '\n' and any noise,
        // same as the web controller does.
        let clean = line.filter(\.isHexDigit)
        guard clean.count >= 6, clean.count % 2 == 0 else {
            throw CosmiqProtocolError.malformedPacket(line)
        }
        guard let raw = [UInt8](hexString: clean) else {
            throw CosmiqProtocolError.malformedPacket(line)
        }
        if raw[0] == 0x80 {
            throw CosmiqProtocolError.commandRejected
        }
        let payload = Array(raw.dropFirst(3))
        guard Int(raw[2]) == payload.count * 2 else {
            throw CosmiqProtocolError.lengthMismatch
        }
        // Sum over cmd + checksum + length + payload must be 0 mod 256.
        guard raw.reduce(UInt8(0), &+) == 0 else {
            throw CosmiqProtocolError.badChecksum
        }
        return CosmiqPacket(command: raw[0], payload: payload)
    }
}

extension Sequence where Element == UInt8 {
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension Array where Element == UInt8 {
    public init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = bytes
    }
}
