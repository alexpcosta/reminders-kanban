import SwiftUI
import XCTest
@testable import TaskBoard

@MainActor
final class CategorySettingsTests: XCTestCase {
    func testAddRemoveAndReload() {
        let suite = "TaskBoardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = CategorySettings(defaults: defaults)
        XCTAssertEqual(settings.categories.count, 3)
        settings.add(name: "Garden", color: .green)
        XCTAssertNotNil(settings.category(for: "garden"))
        XCTAssertFalse(settings.canAdd("Garden"))

        let reloaded = CategorySettings(defaults: defaults)
        XCTAssertNotNil(reloaded.category(for: "garden"))
        reloaded.remove("garden")
        XCTAssertNil(CategorySettings(defaults: defaults).category(for: "garden"))
    }
}
