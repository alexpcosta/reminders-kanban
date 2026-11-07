import XCTest
@testable import TaskBoard

final class BoardCategoryTests: XCTestCase {
    func testReadsCategoryAndKeepsOtherNotes() {
        let result = BoardCategory.read(from: "Call on Tuesday\n#board-family\nBring documents", categories: BoardCategory.defaults)
        XCTAssertEqual(result.categoryID, "family")
        XCTAssertEqual(result.notes, "Call on Tuesday\nBring documents")
    }

    func testChangingCategoryReplacesMarker() {
        XCTAssertEqual(
            BoardCategory.write("work", to: "Call on Tuesday\n#board-family", categories: BoardCategory.defaults),
            "Call on Tuesday\n#board-work"
        )
    }

    func testUnrecognisedMarkerIsPreserved() {
        let result = BoardCategory.read(from: "Note\n#board-custom", categories: BoardCategory.defaults)
        XCTAssertNil(result.categoryID)
        XCTAssertEqual(result.notes, "Note\n#board-custom")
    }

    func testAddedAndRemovedCategoryMarkers() {
        let custom = BoardCategory(id: "garden", name: "Garden", hex: "#00AA00")
        let notes = "Plant seeds\n#board-garden"
        XCTAssertEqual(BoardCategory.read(from: notes, categories: BoardCategory.defaults + [custom]).categoryID, "garden")
        XCTAssertNil(BoardCategory.read(from: notes, categories: BoardCategory.defaults).categoryID)
        XCTAssertEqual(BoardCategory.write(nil, to: notes, categories: BoardCategory.defaults), notes)
        XCTAssertEqual(BoardCategory.write("family", to: notes, categories: BoardCategory.defaults), "Plant seeds\n#board-family")
    }
}
