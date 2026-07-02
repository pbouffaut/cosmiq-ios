import Foundation

/// Dive activity as recorded in byte 2 of the dive header.
public enum DiveActivity: Int, Codable, Sendable {
    case scuba = 2
    case gauge = 3
    case freedive = 4

    public var label: String {
        switch self {
        case .scuba: return "Scuba"
        case .gauge: return "Gauge"
        case .freedive: return "Freedive"
        }
    }
}

public struct DiveSample: Codable, Equatable, Hashable, Sendable {
    /// Seconds since the start of the dive.
    public let time: Int
    /// Depth in meters.
    public let depth: Double
    /// Water temperature in °C.
    public let temperature: Double

    public init(time: Int, depth: Double, temperature: Double) {
        self.time = time
        self.depth = depth
        self.temperature = temperature
    }
}

/// One parsed dive: 36-byte header + 4-byte samples, as produced by the
/// 0x41/0x42 (header) and 0x43/0x44 (profile) commands.
public struct Dive: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Hex string of header bytes 6...11 (the dive timestamp) — the same
    /// fingerprint libdivecomputer uses to recognize already-downloaded dives.
    public let fingerprint: String
    public let activity: DiveActivity
    public let start: Date?
    /// Total dive time in seconds.
    public let duration: Int
    /// Maximum depth in meters.
    public let maxDepth: Double
    /// Oxygen fraction in percent; only meaningful for scuba dives.
    public let oxygenPercent: Int
    /// Surface pressure in millibar.
    public let atmosphericMillibar: Int
    public let sampleIntervalSeconds: Int
    public let samples: [DiveSample]
    /// Raw header + profile bytes, kept so dives can be re-parsed or re-exported later.
    public let rawData: Data

    // MARK: User-editable metadata (not from the device; all optional so old
    // logbook JSON keeps decoding)

    /// User-chosen dive title, e.g. "Night dive with turtles".
    public var name: String? = nil
    public var siteName: String? = nil
    public var notes: String? = nil
    public var latitude: Double? = nil
    public var longitude: Double? = nil
    /// Overrides `start` when the device clock was wrong for this dive.
    public var userDate: Date? = nil

    public var id: String { fingerprint }

    /// The date to display and export: the user's correction if set, else the
    /// device's own clock.
    public var effectiveDate: Date? { userDate ?? start }

    public var displayTitle: String {
        if let name, !name.isEmpty { return name }
        if let siteName, !siteName.isEmpty { return siteName }
        return effectiveDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Dive"
    }

    public var coordinate: (latitude: Double, longitude: Double)? {
        guard let latitude, let longitude else { return nil }
        return (latitude, longitude)
    }

    public var averageTemperature: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.map(\.temperature).reduce(0, +) / Double(samples.count)
    }
}

public enum DiveParser {
    public static let headerSize = 36
    public static let sampleSize = 4
    static let fingerprintRange = 6..<12

    /// Density used to convert pressure to depth. libdivecomputer defaults to
    /// salt water; fresh water is ~1000 kg/m³.
    public static let saltWaterDensity = 1025.0
    static let gravity = 9.80665

    /// Parse a raw dive record (36-byte header immediately followed by samples).
    public static func parse(data: Data, waterDensity: Double = saltWaterDensity) throws -> Dive {
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize else {
            throw CosmiqProtocolError.malformedPacket("dive record too short (\(bytes.count) bytes)")
        }

        func le16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }

        guard let activity = DiveActivity(rawValue: Int(bytes[2])) else {
            throw CosmiqProtocolError.malformedPacket("unknown activity \(bytes[2])")
        }

        let atmospheric = le16(4) & 0x1FFF
        let hydrostatic = waterDensity * gravity
        // Depths are stored as absolute pressure in millibar; 1 mbar = 100 Pa.
        func depthMeters(_ rawMillibar: Int) -> Double {
            Double(rawMillibar - atmospheric) * 100.0 / hydrostatic
        }

        var components = DateComponents()
        components.year = le16(6)
        components.day = Int(bytes[8])
        components.month = Int(bytes[9])
        components.minute = Int(bytes[10])
        components.hour = Int(bytes[11])
        let start = Calendar.current.date(from: components)

        let rawDuration = le16(12)
        let duration = activity == .freedive ? rawDuration : rawDuration * 60

        let interval = Int(bytes[26])
        var samples: [DiveSample] = []
        var time = 0
        var offset = headerSize
        while offset + sampleSize <= bytes.count {
            defer { offset += sampleSize }
            let chunk = bytes[offset..<offset + sampleSize]
            if chunk.allSatisfy({ $0 == 0xFF }) { continue } // padding
            time += interval
            samples.append(DiveSample(
                time: time,
                depth: depthMeters(le16(offset + 2)),
                temperature: Double(le16(offset)) / 10.0
            ))
        }

        return Dive(
            fingerprint: bytes[fingerprintRange].hexString,
            activity: activity,
            start: start,
            duration: duration,
            maxDepth: depthMeters(le16(22)),
            oxygenPercent: Int(bytes[3]),
            atmosphericMillibar: atmospheric,
            sampleIntervalSeconds: interval,
            samples: samples,
            rawData: data
        )
    }

    /// Extract the fingerprint from a bare 36-byte header, for deduplication
    /// before the (slow) profile download.
    public static func fingerprint(ofHeader header: [UInt8]) -> String? {
        guard header.count >= headerSize else { return nil }
        return header[fingerprintRange].hexString
    }
}
