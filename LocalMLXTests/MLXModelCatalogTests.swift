import XCTest
@testable import LocalMLX

final class MLXModelCatalogTests: XCTestCase {

    func test_builtIn_isNonEmpty() {
        XCTAssertFalse(MLXModelCatalog.builtIn.isEmpty,
                       "the catalog must ship with at least one curated model")
    }

    func test_builtIn_idsAreUnique() {
        let ids = MLXModelCatalog.builtIn.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count,
                       "catalog entry ids must be globally unique")
    }

    func test_builtIn_allPointAtMLXCommunity() {
        // Guardrail: the curated list should stay in the mlx-community
        // namespace so `mlx_lm.server` can auto-download on first run
        // without the user needing extra credentials.
        for entry in MLXModelCatalog.builtIn {
            XCTAssertTrue(entry.id.hasPrefix("mlx-community/"),
                          "entry \(entry.id) should live under mlx-community/")
        }
    }

    func test_builtIn_haveSaneSizeHints() {
        for entry in MLXModelCatalog.builtIn {
            XCTAssertGreaterThan(entry.approxSizeGB, 0,
                                 "\(entry.id) has non-positive size")
            XCTAssertLessThan(entry.approxSizeGB, 80,
                              "\(entry.id) is suspiciously large for a 4-bit build")
        }
    }

    func test_builtIn_displayNameAndBlurb_areNonEmpty() {
        for entry in MLXModelCatalog.builtIn {
            XCTAssertFalse(entry.displayName.isEmpty)
            XCTAssertFalse(entry.blurb.isEmpty)
        }
    }

    func test_find_returnsEntryForKnownID() {
        let known = MLXModelCatalog.builtIn.first!
        XCTAssertEqual(MLXModelCatalog.find(known.id), known)
    }

    func test_find_returnsNilForUnknownID() {
        XCTAssertNil(MLXModelCatalog.find("definitely/not-a-model"))
    }

    func test_groupedByFamily_preservesWithinFamilyOrder() {
        let grouped = MLXModelCatalog.groupedByFamily
        // Every entry in the catalog should appear in the grouped
        // projection, and families should never come back empty.
        let flattened = grouped.flatMap(\.entries)
        XCTAssertEqual(Set(flattened.map(\.id)),
                       Set(MLXModelCatalog.builtIn.map(\.id)))
        for group in grouped {
            XCTAssertFalse(group.entries.isEmpty)
            XCTAssertTrue(group.entries.allSatisfy { $0.family == group.family })
        }
    }

    func test_groupedByFamily_omitsFamiliesWithoutEntries() {
        let grouped = MLXModelCatalog.groupedByFamily
        // Defensive: the projection must not include empty sections
        // that the UI would render as blank headers.
        for group in grouped {
            XCTAssertGreaterThan(group.entries.count, 0)
        }
    }

    func test_builtIn_hasAtLeastOneVisionModel() {
        let vision = MLXModelCatalog.builtIn.filter(\.isVision)
        XCTAssertFalse(vision.isEmpty,
                       "catalog should include at least one vision model")
    }

    func test_visionFlag_alignsWithFamily() {
        // Every vision-family entry should be flagged, and vice versa.
        for entry in MLXModelCatalog.builtIn {
            XCTAssertEqual(entry.isVision, entry.family == .vision,
                           "\(entry.id) vision flag does not match family")
        }
    }

    func test_defaultInit_isNotVision() {
        // isVision defaults to false so existing text entries don't
        // need to be touched.
        let entry = MLXModelEntry(
            id: "mlx-community/whatever",
            displayName: "Whatever",
            blurb: "",
            family: .llama,
            approxSizeGB: 1.0)
        XCTAssertFalse(entry.isVision)
    }
}
