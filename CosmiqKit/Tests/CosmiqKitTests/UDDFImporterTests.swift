import XCTest
@testable import CosmiqKit

final class UDDFImporterTests: XCTestCase {
    /// Build a device dive, export it with DiveExporter, re-import it with
    /// UDDFImporter, and check the core data survives the round trip.
    func testRoundTripThroughOwnExporter() throws {
        var raw = [UInt8](repeating: 0, count: DiveParser.headerSize)
        raw[2] = 2 // scuba
        raw[3] = 32
        raw[4] = UInt8(1013 & 0xFF); raw[5] = UInt8(1013 >> 8)
        raw[6] = UInt8(2026 & 0xFF); raw[7] = UInt8(2026 >> 8)
        raw[8] = 15; raw[9] = 6; raw[10] = 30; raw[11] = 14
        raw[12] = 42 // 42 min
        raw[22] = UInt8(3013 & 0xFF); raw[23] = UInt8(3013 >> 8)
        raw[26] = 20
        raw += [0x1D, 0x01, 0xE5, 0x05] // 28.5 C, 1509 mbar
        raw += [0x18, 0x01, 0xC5, 0x0B] // 28.0 C, 3013 mbar

        var dive = try DiveParser.parse(data: Data(raw))
        dive.siteName = "Blue Hole"
        dive.latitude = 28.5723
        dive.longitude = 34.5370
        dive.notes = "Amazing viz & turtles"

        let uddf = DiveExporter.uddf(for: [dive])
        let imported = try UDDFImporter.parse(data: Data(uddf.utf8))

        XCTAssertEqual(imported.count, 1)
        let result = try XCTUnwrap(imported.first)
        XCTAssertEqual(result.duration, dive.duration)
        XCTAssertEqual(result.maxDepth, dive.maxDepth, accuracy: 0.05)
        XCTAssertEqual(result.oxygenPercent, 32)
        XCTAssertEqual(result.samples.count, 2)
        XCTAssertEqual(result.samples[0].depth, dive.samples[0].depth, accuracy: 0.05)
        XCTAssertEqual(result.samples[0].temperature, 28.5, accuracy: 0.1)
        XCTAssertEqual(result.siteName, "Blue Hole")
        XCTAssertEqual(try XCTUnwrap(result.latitude), 28.5723, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(result.longitude), 34.5370, accuracy: 0.0001)
        XCTAssertEqual(result.notes, "Amazing viz & turtles")
        if let original = dive.start, let roundTripped = result.start {
            XCTAssertEqual(original.timeIntervalSince1970,
                           roundTripped.timeIntervalSince1970, accuracy: 1)
        }
    }

    func testImportIsDeterministicForDedupe() throws {
        let uddf = """
        <uddf version="3.2.1">
        <profiledata><repetitiongroup><dive id="d1">
        <informationbeforedive><datetime>2025-08-17T10:58:00Z</datetime></informationbeforedive>
        <samples>
        <waypoint><depth>10.0</depth><divetime>60</divetime><temperature>299.15</temperature></waypoint>
        <waypoint><depth>20.0</depth><divetime>120</divetime></waypoint>
        </samples>
        <informationafterdive><greatestdepth>20.0</greatestdepth><diveduration>2520</diveduration></informationafterdive>
        </dive></repetitiongroup></profiledata>
        </uddf>
        """
        let first = try UDDFImporter.parse(data: Data(uddf.utf8))
        let second = try UDDFImporter.parse(data: Data(uddf.utf8))
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].fingerprint, second[0].fingerprint)
        XCTAssertTrue(first[0].fingerprint.hasPrefix("uddf"))
        // Temperature carries forward when a waypoint omits it.
        XCTAssertEqual(first[0].samples[1].temperature, 26.0, accuracy: 0.1)
        XCTAssertEqual(first[0].sampleIntervalSeconds, 60)
    }

    func testGarbageInputThrows() {
        XCTAssertThrowsError(try UDDFImporter.parse(data: Data("not xml at all".utf8)))
    }
}
