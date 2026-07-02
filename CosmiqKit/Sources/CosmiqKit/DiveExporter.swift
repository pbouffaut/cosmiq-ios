import Foundation

/// Exports dives to formats other logbook software can import.
public enum DiveExporter {
    // MARK: CSV

    public static func csv(for dive: Dive) -> String {
        var lines = ["time_s,depth_m,temperature_c"]
        for sample in dive.samples {
            lines.append("\(sample.time),\(format(sample.depth)),\(format(sample.temperature))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: UDDF (importable by Subsurface, MacDive, divelogs.de, ...)

    public static func uddf(for dives: [Dive]) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <uddf xmlns="http://www.streit.cc/uddf/3.2/" version="3.2.1">
        <generator>
        <name>CosmiQ Companion</name>
        <datetime>\(dateFormatter.string(from: Date()))</datetime>
        </generator>
        <diver><owner id="owner"><personal></personal></owner></diver>

        """

        // Dive sites are document-level in UDDF; one entry per dive that has
        // a site name or coordinates.
        let sitedDives = dives.enumerated().filter { $0.element.siteName != nil || $0.element.coordinate != nil }
        if !sitedDives.isEmpty {
            xml += "<divesite>\n"
            for (index, dive) in sitedDives {
                xml += "<site id=\"site\(index + 1)\">"
                xml += "<name>\(escape(dive.siteName ?? "Dive site"))</name>"
                if let coordinate = dive.coordinate {
                    xml += "<geography><latitude>\(coordinate.latitude)</latitude>"
                    xml += "<longitude>\(coordinate.longitude)</longitude></geography>"
                }
                xml += "</site>\n"
            }
            xml += "</divesite>\n"
        }

        // Gas definitions are document-level in UDDF; collect the distinct
        // nitrox mixes used by the scuba dives.
        let mixes = Set(dives.filter { $0.activity == .scuba }.map(\.oxygenPercent)).sorted()
        if !mixes.isEmpty {
            xml += "<gasdefinitions>\n"
            for o2Percent in mixes {
                let o2 = Double(o2Percent) / 100.0
                xml += "<mix id=\"mix\(o2Percent)\"><name>EAN\(o2Percent)</name>"
                xml += "<o2>\(format(o2))</o2><n2>\(format(1 - o2))</n2><he>0.0</he></mix>\n"
            }
            xml += "</gasdefinitions>\n"
        }

        xml += "<profiledata>\n<repetitiongroup id=\"rg1\">\n"

        for (index, dive) in dives.enumerated() {
            xml += "<dive id=\"dive\(index + 1)_\(dive.fingerprint)\">\n"
            xml += "<informationbeforedive>\n"
            if let start = dive.effectiveDate {
                xml += "<datetime>\(dateFormatter.string(from: start))</datetime>\n"
            }
            if dive.siteName != nil || dive.coordinate != nil {
                xml += "<link ref=\"site\(index + 1)\"/>\n"
            }
            xml += "</informationbeforedive>\n"
            if dive.activity == .scuba {
                xml += "<tankdata><link ref=\"mix\(dive.oxygenPercent)\"/></tankdata>\n"
            }
            xml += "<samples>\n"
            for sample in dive.samples {
                xml += "<waypoint><depth>\(format(sample.depth))</depth>"
                xml += "<divetime>\(sample.time)</divetime>"
                xml += "<temperature>\(format(sample.temperature + 273.15))</temperature></waypoint>\n"
            }
            xml += "</samples>\n"
            xml += "<informationafterdive>"
            xml += "<greatestdepth>\(format(dive.maxDepth))</greatestdepth>"
            xml += "<diveduration>\(dive.duration)</diveduration>"
            var noteParts: [String] = []
            if let name = dive.name, !name.isEmpty { noteParts.append(name) }
            if let notes = dive.notes, !notes.isEmpty { noteParts.append(notes) }
            if !noteParts.isEmpty {
                xml += "<notes><para>\(escape(noteParts.joined(separator: " — ")))</para></notes>"
            }
            xml += "</informationafterdive>\n"
            xml += "</dive>\n"
        }

        xml += """
        </repetitiongroup>
        </profiledata>
        </uddf>
        """
        return xml
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
