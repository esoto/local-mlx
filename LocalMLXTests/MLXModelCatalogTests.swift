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

    func test_visionIsOrthogonalToFamily_visionEntriesLiveInNaturalFamilies() {
        // Vision-capable models should sit under the family they
        // actually belong to — Qwen2-VL under .qwen, LLaVA under
        // .mistral, Phi-vision under .phi, Gemma 3/4 under .gemma.
        // The eye icon in the picker is the signal for vision, not a
        // separate `.vision` family bucket.
        let visionFamilies = Set(
            MLXModelCatalog.builtIn.filter(\.isVision).map(\.family))
        XCTAssertTrue(visionFamilies.contains(.qwen),
                      "Qwen2-VL should live under the Qwen family")
        XCTAssertTrue(visionFamilies.contains(.mistral),
                      "LLaVA (Mistral base) should live under Mistral")
        XCTAssertTrue(visionFamilies.contains(.phi),
                      "Phi vision should live under Phi")
        XCTAssertTrue(visionFamilies.contains(.gemma),
                      "Gemma 3/4 should live under Gemma")
    }

    func test_gemma_hasBothTextAndVisionVariants() {
        let gemmaEntries = MLXModelCatalog.builtIn.filter { $0.family == .gemma }
        let text = gemmaEntries.filter { !$0.isVision }
        let vision = gemmaEntries.filter { $0.isVision }
        XCTAssertFalse(text.isEmpty, "should still have text-only Gemma entries")
        XCTAssertFalse(vision.isEmpty, "should include at least one vision Gemma")
    }

    func test_gemma3_4b_isVisionAndInCatalog() {
        let entry = MLXModelCatalog.find("mlx-community/gemma-3-4b-it-4bit")
        XCTAssertNotNil(entry, "Gemma 3 4B should be in the curated catalog")
        XCTAssertTrue(entry?.isVision == true)
        XCTAssertEqual(entry?.family, .gemma)
    }

    func test_gemma4_e4b_isVisionAndInCatalog() {
        let entry = MLXModelCatalog.find("mlx-community/gemma-4-e4b-it-4bit")
        XCTAssertNotNil(entry, "Gemma 4 E4B should be in the curated catalog")
        XCTAssertTrue(entry?.isVision == true)
        XCTAssertEqual(entry?.family, .gemma)
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
