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
    /// Minimum water temperature from the header, when valid — available even
    /// when the profile itself couldn't be read.
    public let minTemperature: Double?
    public let samples: [DiveSample]
    /// Raw header + profile bytes, kept so dives can be re-parsed or re-exported later.
    public let rawData: Data

    /// Set when the profile was affected by the sector-wrap firmware bug
    /// (recovered through another slot, partial, or missing entirely).
    public var profileNote: String? = nil

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

    /// Samples up to the end of the dive. The device keeps logging near-0 m
    /// readings for a while after surfacing, so profiles grow a flat tail;
    /// this cuts everything after the last sample deeper than 1 m, keeping
    /// one extra sample so the curve closes at the surface.
    public var trimmedSamples: [DiveSample] {
        guard let lastDeep = samples.lastIndex(where: { $0.depth > 1.0 }) else {
            return samples
        }
        return Array(samples[...Swift.min(lastDeep + 1, samples.count - 1)])
    }
}

public enum DiveParser {
    public static let headerSize = 36
    public static let sampleSize = 4
    static let fingerprintRange = 6..<12

    /// Flash sectors wrap at 256 (the sector-wrap firmware bug: profiles are
    /// written to `startSector % 256` but read back from the full value).
    public static let sectorWrap = 256

    /// Parse a raw dive record (36-byte header immediately followed by
    /// samples). Header layout and unit conversions follow the official
    /// Deepblu app (CosmiqLogHeader.java), as documented by cosmiq5-web v69.
    public static func parse(data: Data) throws -> Dive {
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize else {
            throw CosmiqProtocolError.malformedPacket("dive record too short (\(bytes.count) bytes)")
        }

        func le16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }

        // Unknown modes are treated as scuba, like the official app.
        let activity = DiveActivity(rawValue: Int(bytes[2])) ?? .scuba

        // 0x80B4 is a sentinel for standard pressure; the salt/fresh flag
        // lives in the "reserved" word, and the app converts pressure to
        // depth with these exact divisors.
        let dvsetting = le16(4)
        let atmospheric = dvsetting == 0x80B4 ? 1000 : dvsetting & 0x1FFF
        let salt = le16(20) & 1 == 1
        func depthMeters(_ rawMillibar: Int) -> Double {
            Double(rawMillibar - atmospheric) / (salt ? 102.5 : 100.0)
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

        // The official app hard-codes the interval; header byte 26 is not it.
        let interval = activity == .freedive ? 1 : 20

        let rawMinTemp = Double(le16(24)) / 10.0

        // Sample times are positional (slot k records second (k+1)*interval),
        // erased 0xFF slots are skipped, recording past the dive time is cut.
        var samples: [DiveSample] = []
        var time = 0
        var offset = headerSize
        while offset + sampleSize <= bytes.count {
            defer { offset += sampleSize }
            time += interval
            if duration > 0 && time > duration { break }
            let chunk = bytes[offset..<offset + sampleSize]
            if chunk.allSatisfy({ $0 == 0xFF }) { continue } // erased flash
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
            minTemperature: rawMinTemp < 100 ? rawMinTemp : nil,
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

    /// Number of recorded samples, from header bytes 28-29.
    public static func sampleCount(ofHeader header: [UInt8]) -> Int {
        guard header.count >= headerSize else { return 0 }
        return Int(header[28]) | Int(header[29]) << 8
    }

    /// Flash start sector, from header bytes 30-31.
    public static func startSector(ofHeader header: [UInt8]) -> Int {
        guard header.count >= headerSize else { return 0 }
        return Int(header[30]) | Int(header[31]) << 8
    }

    /// Where a dive's profile can actually be read, given the sector-wrap
    /// firmware bug: profiles are written to `startSector % 256` but the read
    /// command uses the full sector, so a dive past the wrap is only readable
    /// through the older dive whose sector it overwrote.
    public enum ProfileSlot: Equatable {
        /// Readable through its own index (0-based).
        case own(Int)
        /// Readable through an older dive's index (0-based).
        case recovered(Int)
        /// This dive's flash was overwritten by a newer dive.
        case overwritten
        /// No header points at the physical sector; the profile can't be read.
        case unreachable
    }

    public static func profileSlot(forDiveAt index: Int, headers: [[UInt8]]) -> ProfileSlot {
        let sectors = headers.map(startSector(ofHeader:))
        let sector = sectors[index]
        if sector >= sectorWrap, let older = sectors.firstIndex(of: sector - sectorWrap) {
            return .recovered(older)
        }
        if sector < sectorWrap, sectors.contains(sector + sectorWrap) {
            return .overwritten
        }
        return sector >= sectorWrap ? .unreachable : .own(index)
    }

    /// Drop trailing erased-flash (0xFF) sample slots from a profile body.
    public static func stripErased(_ body: [UInt8]) -> [UInt8] {
        var count = body.count - body.count % sampleSize
        while count >= sampleSize, body[(count - sampleSize)..<count].allSatisfy({ $0 == 0xFF }) {
            count -= sampleSize
        }
        return Array(body.prefix(count))
    }
}
