import Foundation
import XCTest

/// Helpers for locating fixtures inside the test bundle.
enum TestBundle {

    private final class Anchor {}

    static var bundle: Bundle { Bundle(for: Anchor.self) }

    /// Load a fixture file by name. Looks under the test bundle root first
    /// (where Xcode flattens resources), then under a `Fixtures/` subdirectory
    /// for SwiftPM-style layouts.
    static func loadFixture(_ name: String, ext: String) throws -> Data {
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return try Data(contentsOf: url)
        }
        if let url = bundle.url(forResource: name, withExtension: ext,
                                subdirectory: "Fixtures") {
            return try Data(contentsOf: url)
        }
        throw NSError(
            domain: "TestBundle",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey:
                "Fixture \(name).\(ext) not found in test bundle"]
        )
    }

    static func loadFixtureString(_ name: String, ext: String) throws -> String {
        let data = try loadFixture(name, ext: ext)
        guard let s = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "TestBundle", code: 500)
        }
        return s
    }
}
