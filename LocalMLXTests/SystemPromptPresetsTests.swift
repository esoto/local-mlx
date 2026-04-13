import XCTest
@testable import LocalMLX

final class SystemPromptPresetsTests: XCTestCase {

    func test_builtInList_isNonEmpty() {
        XCTAssertFalse(SystemPromptPresets.builtIn.isEmpty)
    }

    func test_builtInPresets_haveStableIDsAndNames() {
        for preset in SystemPromptPresets.builtIn {
            XCTAssertFalse(preset.id.isEmpty, "preset id should be non-empty")
            XCTAssertFalse(preset.name.isEmpty, "preset name should be non-empty")
            XCTAssertFalse(preset.icon.isEmpty, "preset icon should be non-empty")
        }
    }

    func test_builtInPresets_haveUniqueIDs() {
        let ids = SystemPromptPresets.builtIn.map(\.id)
        let unique = Set(ids)
        XCTAssertEqual(ids.count, unique.count, "preset ids must be unique")
    }

    func test_defaultPreset_hasEmptyContent() {
        let def = SystemPromptPresets.preset(withId: "default")
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.content, "")
    }

    func test_namedPresets_haveNonEmptyContent() {
        for preset in SystemPromptPresets.builtIn where preset.id != "default" {
            XCTAssertFalse(preset.content.isEmpty,
                           "non-default preset '\(preset.id)' should have content")
        }
    }

    func test_lookupByID_returnsNilForUnknown() {
        XCTAssertNil(SystemPromptPresets.preset(withId: "not-a-real-preset"))
    }

    func test_lookupByID_findsKnown() {
        XCTAssertEqual(SystemPromptPresets.preset(withId: "concise")?.name, "Concise")
    }
}
