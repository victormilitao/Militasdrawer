import XCTest
@testable import MilitasdrawCore

final class DrawingTests: XCTestCase {
    func testDuplicatePreservesContentAndMovesOnlyCopyWithUndo() throws {
        for kind in ElementKind.allCases {
            let object = Element(kind: kind, start: Point(10, 20), end: Point(100, 120),
                                 points: [Point(10, 20), Point(100, 120)], text: "Ideia", color: "FF0000", width: 4)
            let before = Drawing(elements: [object])
            var drawing = before
            let id = try XCTUnwrap(drawing.duplicate(object.id))
            XCTAssertNotEqual(id, object.id)
            var expected = object
            expected.id = id
            expected.move(dx: 30, dy: 50)
            drawing.moveSelection([id], dx: 30, dy: 50)
            XCTAssertEqual(drawing.elements, [object, expected])
            var history = History()
            history.record(before, after: drawing)
            XCTAssertEqual(history.undo(drawing), before)
            XCTAssertEqual(history.redo(before), drawing)
        }
    }
    func testDuplicateArrowFreezesConnectionsWithoutChangingOriginal() throws {
        let shape = Element(kind: .rectangle, start: Point(0, 0), end: Point(100, 100))
        let arrow = Element(kind: .arrow, start: Point(50, 50), end: Point(300, 50), source: shape.id)
        var drawing = Drawing(elements: [shape, arrow])
        let ends = drawing.endpoints(for: arrow)
        let id = try XCTUnwrap(drawing.duplicate(arrow.id))
        drawing.moveSelection([id], dx: 20, dy: 30)
        XCTAssertEqual(drawing.elements[1], arrow)
        XCTAssertNil(drawing.elements[2].source)
        XCTAssertNil(drawing.elements[2].target)
        XCTAssertEqual(drawing.elements[2].start, ends.0.moved(20, 30))
        XCTAssertEqual(drawing.elements[2].end, ends.1.moved(20, 30))
    }
    func testReconnectEitherArrowEndpointAndUndo() {
        let a = Element(kind: .rectangle, start: Point(0, 0), end: Point(100, 100))
        let b = Element(kind: .ellipse, start: Point(300, 0), end: Point(400, 100))
        for endpoint in [ArrowEndpoint.start, .end] {
            let arrow = Element(kind: .arrow, start: Point(150, 50), end: Point(250, 50),
                                source: endpoint == .end ? a.id : nil, target: endpoint == .start ? b.id : nil)
            let before = Drawing(elements: [a, b, arrow])
            var drawing = before
            let shape = endpoint == .start ? a : b
            drawing.reconnectArrow(arrow.id, endpoint: endpoint, at: Point(shape.bounds.midX, shape.bounds.midY), shapeID: shape.id)
            XCTAssertEqual(drawing.elements[2].source, a.id)
            XCTAssertEqual(drawing.elements[2].target, b.id)
            XCTAssertEqual(drawing.endpoints(for: drawing.elements[2]).0, Point(100, 50))
            XCTAssertEqual(drawing.endpoints(for: drawing.elements[2]).1, Point(300, 50))
            var history = History()
            history.record(before, after: drawing)
            XCTAssertEqual(history.undo(drawing), before)
            XCTAssertEqual(history.redo(before), drawing)
            drawing.reconnectArrow(arrow.id, endpoint: endpoint, at: Point(200, 200), shapeID: nil)
            if endpoint == .start {
                XCTAssertNil(drawing.elements[2].source)
                XCTAssertEqual(drawing.elements[2].target, b.id)
                XCTAssertEqual(drawing.elements[2].start, Point(200, 200))
            } else {
                XCTAssertEqual(drawing.elements[2].source, a.id)
                XCTAssertNil(drawing.elements[2].target)
                XCTAssertEqual(drawing.elements[2].end, Point(200, 200))
            }
        }
    }
    func testMarqueeIncludesEnclosedShapesAndZeroHeightLines() {
        let shape = Element(kind: .rectangle, start: Point(10, 10), end: Point(40, 40))
        let partial = Element(kind: .ellipse, start: Point(80, 80), end: Point(120, 120))
        let line = Element(kind: .arrow, start: Point(10, 60), end: Point(90, 60))
        let drawing = Drawing(elements: [shape, partial, line])
        XCTAssertEqual(drawing.elements(enclosedBy: CGRect(x: 0, y: 0, width: 100, height: 100)), [shape.id, line.id])
        XCTAssertTrue(drawing.elements(enclosedBy: CGRect(x: 200, y: 200, width: 50, height: 50)).isEmpty)
    }
    func testGroupMovePreservesInternalConnectionsAndDetachesExternalOnes() {
        let a = Element(kind: .rectangle, start: Point(0, 0), end: Point(100, 100))
        let b = Element(kind: .ellipse, start: Point(300, 0), end: Point(400, 100))
        let arrow = Element(kind: .arrow, start: Point(50, 50), end: Point(350, 50), source: a.id, target: b.id)
        var drawing = Drawing(elements: [a, b, arrow])
        let oldEnds = drawing.endpoints(for: arrow)
        drawing.moveSelection([a.id, b.id, arrow.id], dx: 20, dy: 30)
        XCTAssertEqual(drawing.elements[2].source, a.id)
        XCTAssertEqual(drawing.elements[2].target, b.id)
        XCTAssertEqual(drawing.endpoints(for: drawing.elements[2]).0, oldEnds.0.moved(20, 30))
        XCTAssertEqual(drawing.endpoints(for: drawing.elements[2]).1, oldEnds.1.moved(20, 30))
        drawing.moveSelection([arrow.id], dx: 10, dy: 15)
        XCTAssertNil(drawing.elements[2].source)
        XCTAssertNil(drawing.elements[2].target)
        XCTAssertEqual(drawing.elements[2].start, oldEnds.0.moved(30, 45))
    }
    func testShapeTextSurvivesResizeMoveAndPersistence() throws {
        for kind in [ElementKind.rectangle, .ellipse, .diamond] {
            var shape = Element(kind: kind, start: Point(0, 0), end: Point(200, 150), text: "Texto\ncentralizado")
            shape.resize(corner: .bottomRight, dx: 80, dy: 40)
            shape.move(dx: 50, dy: -20)
            let drawing = Drawing(elements: [shape])
            let loaded = try JSONDecoder().decode(Drawing.self, from: JSONEncoder().encode(drawing))
            XCTAssertEqual(loaded, drawing)
            XCTAssertEqual(loaded.elements[0].text, "Texto\ncentralizado")
        }
    }
    func testResizeKeepsOppositeCornerAndSupportsReverseShapes() {
        for kind in [ElementKind.rectangle, .ellipse, .diamond] {
            for corner in ResizeCorner.allCases {
                var shape = Element(kind: kind, start: Point(100, 100), end: Point(0, 0))
                let fixed = corner.opposite.point(in: shape.bounds)
                let dragged = corner.point(in: shape.bounds).moved(25, 40)
                shape.resize(corner: corner, dx: 25, dy: 40)
                XCTAssertEqual(shape.start, fixed)
                XCTAssertEqual(shape.end, dragged)
                XCTAssertGreaterThan(shape.bounds.width, 0)
                XCTAssertGreaterThan(shape.bounds.height, 0)
            }
        }
    }
    func testResizeCanCrossOppositeCornerAndUndo() {
        let shape = Element(kind: .rectangle, start: Point(0, 0), end: Point(100, 100))
        let before = Drawing(elements: [shape])
        var after = before
        after.elements[0].resize(corner: .topLeft, dx: 150, dy: 160)
        XCTAssertEqual(after.elements[0].bounds, CGRect(x: 100, y: 100, width: 50, height: 60))
        var history = History()
        history.record(before, after: after)
        XCTAssertEqual(history.undo(after), before)
        XCTAssertEqual(history.redo(before), after)
    }
    func testConnectedArrowFollowsShapeAndSurvivesDeletion() {
        var a = Element(kind: .rectangle, start: Point(0, 0), end: Point(100, 100))
        let b = Element(kind: .ellipse, start: Point(300, 0), end: Point(400, 100))
        let arrow = Element(kind: .arrow, start: Point(50, 50), end: Point(350, 50), source: a.id, target: b.id)
        var drawing = Drawing(elements: [a, b, arrow])
        XCTAssertEqual(drawing.endpoints(for: arrow).0, Point(100, 50))
        XCTAssertEqual(drawing.endpoints(for: arrow).1, Point(300, 50))
        a.move(dx: 100, dy: 0); drawing.elements[0] = a
        XCTAssertEqual(drawing.endpoints(for: arrow).0, Point(200, 50))
        drawing.remove(a.id)
        let surviving = drawing.elements.last!
        XCTAssertNil(surviving.source)
        XCTAssertEqual(drawing.endpoints(for: surviving).0, Point(200, 50))
        XCTAssertEqual(surviving.target, b.id)
    }
    func testUndoRedoAndBranch() {
        let empty = Drawing()
        let one = Drawing(elements: [Element(kind: .rectangle, start: Point(0, 0), end: Point(10, 10))])
        var history = History()
        history.record(empty, after: one)
        XCTAssertEqual(history.undo(one), empty)
        XCTAssertEqual(history.redo(empty), one)
        _ = history.undo(one)
        let other = Drawing(elements: [Element(kind: .text, start: Point(1, 1), end: Point(20, 20), text: "Ideia")])
        history.record(empty, after: other)
        XCTAssertTrue(history.future.isEmpty)
        history.record(other, after: other)
        XCTAssertEqual(history.past.count, 1)
    }
    func testDocumentRoundTripPreservesConnectionsAndInk() throws {
        let shape = Element(kind: .diamond, start: Point(-10, -10), end: Point(100, 100))
        let arrow = Element(kind: .arrow, start: Point(0, 0), end: Point(200, 200), source: shape.id)
        let ink = Element(kind: .pen, start: Point(1, 2), end: Point(3, 4), points: [Point(1, 2), Point(3, 4)])
        let drawing = Drawing(elements: [shape, arrow, ink])
        XCTAssertEqual(try JSONDecoder().decode(Drawing.self, from: JSONEncoder().encode(drawing)), drawing)
    }
    func testDiamondAnchorAndReverseDragBounds() {
        let diamond = Element(kind: .diamond, start: Point(100, 100), end: Point(0, 0))
        XCTAssertEqual(diamond.bounds.width, 100)
        XCTAssertEqual(diamond.anchor(toward: Point(150, 150)), Point(75, 75))
    }
}

final class DrawingArchiveTests: XCTestCase {
    func testRoundTripRestoresLastOpenedDrawingRatherThanMostRecentlyEdited() throws {
        var archive = DrawingArchive()
        let original = Drawing(elements: [Element(kind: .text, start: Point(0, 0), end: Point(20, 20), text: "Ideia")])
        archive.create(drawing: original)
        let firstID = archive.activeID
        archive.create()
        archive.activeID = firstID
        let loaded = try JSONDecoder().decode(DrawingArchive.self, from: JSONEncoder().encode(archive))
        try loaded.validate()
        XCTAssertEqual(loaded.drawings.count, 2)
        XCTAssertEqual(loaded.active?.drawing, original)
        XCTAssertEqual(loaded.active?.name, "Untitled 1")
    }

    func testOnlyEditsChangeUpdateDateAndRecentOrder() {
        var archive = DrawingArchive()
        archive.create()
        let firstID = archive.activeID
        let date = archive.active!.updatedAt
        archive.update(Drawing(), at: date.addingTimeInterval(60))
        XCTAssertEqual(archive.active?.updatedAt, date)
        archive.create()
        archive.activeID = firstID
        let changed = Drawing(elements: [Element(kind: .rectangle, start: Point(0, 0), end: Point(10, 10))])
        archive.update(changed, at: date.addingTimeInterval(120))
        XCTAssertEqual(archive.recent.first?.id, firstID)
        XCTAssertTrue(archive.drawings[1].drawing.elements.isEmpty)
    }

    func testDeletingInactiveDrawingPreservesActiveDrawing() throws {
        var archive = DrawingArchive()
        archive.create()
        let first = archive.activeID!
        archive.create()
        let active = archive.activeID
        archive.delete(first)
        XCTAssertEqual(archive.activeID, active)
        XCTAssertEqual(archive.drawings.count, 1)
        let restored = try JSONDecoder().decode(DrawingArchive.self, from: JSONEncoder().encode(archive))
        try restored.validate()
        XCTAssertFalse(restored.drawings.contains { $0.id == first })
    }

    func testDeletingActiveDrawingSelectsMostRecentRemaining() throws {
        var archive = DrawingArchive()
        archive.create()
        let first = archive.activeID!
        archive.create()
        archive.drawings[0].updatedAt = Date().addingTimeInterval(60)
        archive.create()
        archive.delete(archive.activeID!)
        XCTAssertEqual(archive.activeID, first)
        try archive.validate()
    }

    func testDeletingLastDrawingLeavesValidEmptyArchive() throws {
        var archive = DrawingArchive()
        archive.create()
        archive.delete(archive.activeID!)
        XCTAssertTrue(archive.drawings.isEmpty)
        XCTAssertNil(archive.activeID)
        try archive.validate()
        archive.create(name: "Untitled 1")
        XCTAssertNotNil(archive.active)
        try archive.validate()
    }

    func testInvalidArchiveIsRejected() {
        var archive = DrawingArchive()
        archive.create()
        archive.activeID = UUID()
        XCTAssertThrowsError(try archive.validate())
        archive.activeID = archive.drawings[0].id
        archive.drawings[0].drawing.version = 99
        XCTAssertThrowsError(try archive.validate())
    }
}
