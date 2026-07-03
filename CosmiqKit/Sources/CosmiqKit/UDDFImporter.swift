import CryptoKit
import Foundation

/// Imports dives from UDDF files produced by other logbook apps (Subsurface,
/// MacDive, divelogs.de, or this app's own export).
public enum UDDFImporter {
    public static func parse(data: Data) throws -> [Dive] {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() || !delegate.dives.isEmpty else {
            throw CosmiqProtocolError.malformedPacket("not a valid UDDF file")
        }
        return delegate.finishedDives()
    }

    /// Stable identifier for an imported dive so re-importing the same file
    /// doesn't duplicate entries.
    static func fingerprint(date: Date?, duration: Int, maxDepth: Double) -> String {
        let seed = "\(date?.timeIntervalSince1970 ?? 0)|\(duration)|\(String(format: "%.1f", maxDepth))"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return "uddf" + digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    struct Site {
        var name: String?
        var latitude: Double?
        var longitude: Double?
    }

    struct PendingDive {
        var date: Date?
        var duration: Int?
        var maxDepth: Double?
        var notes: String = ""
        var linkRefs: [String] = []
        var samples: [DiveSample] = []
    }

    var dives: [PendingDive] = []
    private var sites: [String: Site] = [:]
    private var mixes: [String: Int] = [:] // mix id -> O2 percent

    private var elementStack: [String] = []
    private var text = ""
    private var currentDive: PendingDive?
    private var currentSiteID: String?
    private var currentMixID: String?
    private var waypointDepth: Double?
    private var waypointTime: Int?
    private var waypointTemperature: Double?
    private var lastTemperature = 0.0

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let plainFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        let name = element.lowercased()
        elementStack.append(name)
        text = ""
        switch name {
        case "dive":
            currentDive = PendingDive()
        case "site":
            if let id = attributes["id"] {
                currentSiteID = id
                sites[id] = Site()
            }
        case "mix":
            currentMixID = attributes["id"]
        case "waypoint":
            waypointDepth = nil
            waypointTime = nil
            waypointTemperature = nil
        case "link":
            if let ref = attributes["ref"], currentDive != nil {
                currentDive?.linkRefs.append(ref)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        let name = element.lowercased()
        defer { if elementStack.last == name { elementStack.removeLast() } }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let inWaypoint = elementStack.contains("waypoint")

        switch name {
        case "datetime" where currentDive != nil:
            currentDive?.date = Self.parseDate(value)
        case "greatestdepth":
            currentDive?.maxDepth = Double(value)
        case "diveduration":
            currentDive?.duration = Double(value).map { Int($0) }
        case "para" where currentDive != nil:
            let existing = currentDive?.notes ?? ""
            currentDive?.notes = existing.isEmpty ? value : "\(existing)\n\(value)"
        case "depth" where inWaypoint:
            waypointDepth = Double(value)
        case "divetime" where inWaypoint:
            waypointTime = Double(value).map { Int($0) }
        case "temperature" where inWaypoint:
            waypointTemperature = Double(value).map { $0 - 273.15 } // Kelvin -> °C
        case "waypoint":
            if let depth = waypointDepth, let time = waypointTime {
                if let temperature = waypointTemperature { lastTemperature = temperature }
                currentDive?.samples.append(
                    DiveSample(time: time, depth: depth, temperature: lastTemperature))
            }
        case "name":
            if let id = currentSiteID, elementStack.contains("site") {
                sites[id]?.name = value
            }
        case "latitude":
            if let id = currentSiteID { sites[id]?.latitude = Double(value) }
        case "longitude":
            if let id = currentSiteID { sites[id]?.longitude = Double(value) }
        case "site":
            currentSiteID = nil
        case "o2":
            if let id = currentMixID, let fraction = Double(value) {
                // Both fraction (0.32) and percent (32) forms exist in the wild.
                mixes[id] = fraction <= 1.0 ? Int((fraction * 100).rounded()) : Int(fraction.rounded())
            }
        case "mix":
            currentMixID = nil
        case "dive":
            if let dive = currentDive { dives.append(dive) }
            currentDive = nil
        default:
            break
        }
        text = ""
    }

    // MARK: Assembly

    func finishedDives() -> [Dive] {
        dives.compactMap { pending in
            let samples = pending.samples.sorted { $0.time < $1.time }
            let duration = pending.duration ?? samples.last?.time ?? 0
            let maxDepth = pending.maxDepth ?? samples.map(\.depth).max() ?? 0
            guard duration > 0 || maxDepth > 0 else { return nil }

            var site: Site?
            var oxygen = 21
            for ref in pending.linkRefs {
                if let match = sites[ref] { site = match }
                if let o2 = mixes[ref] { oxygen = o2 }
            }

            let interval: Int
            if samples.count >= 2 {
                interval = max(1, samples[1].time - samples[0].time)
            } else {
                interval = 20
            }

            return Dive(
                fingerprint: UDDFImporter.fingerprint(date: pending.date,
                                                      duration: duration,
                                                      maxDepth: maxDepth),
                activity: .scuba,
                start: pending.date,
                duration: duration,
                maxDepth: maxDepth,
                oxygenPercent: oxygen,
                atmosphericMillibar: 1013,
                sampleIntervalSeconds: interval,
                samples: samples,
                rawData: Data(),
                siteName: site?.name,
                notes: pending.notes.isEmpty ? nil : pending.notes,
                latitude: site?.latitude,
                longitude: site?.longitude
            )
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        isoFormatter.date(from: value) ?? plainFormatter.date(from: value)
    }
}
