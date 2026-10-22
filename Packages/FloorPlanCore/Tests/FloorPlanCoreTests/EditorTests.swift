import XCTest
@testable import FloorPlanCore

final class EditorTests: XCTestCase {
    private func makeEditor() -> (FloorPlanEditor, FloorPlan) {
        let project = Fixtures.project()
        return (FloorPlanEditor(original: project.original, edited: project.edited), project.original)
    }

    func testMoveWallDragsConnectedWallsAndRoomOutline() throws {
        var (editor, original) = makeEditor()
        let north = try XCTUnwrap(editor.plan.walls.first { $0.sourceSurfaceID == Fixtures.ids.n })
        XCTAssertTrue(editor.moveWall(north.id, by: Point2D(x: 0, y: -0.5)))

        let moved = try XCTUnwrap(editor.plan.wall(north.id))
        XCTAssertEqual(moved.start.y, -0.5, accuracy: 1e-9)
        // Paredes oeste/leste acompanham a ponta superior.
        let west = try XCTUnwrap(editor.plan.walls.first { $0.sourceSurfaceID == Fixtures.ids.w })
        XCTAssertEqual(min(west.start.y, west.end.y), -0.5, accuracy: 1e-9)
        // Contorno do ambiente também.
        XCTAssertEqual(editor.plan.rooms[0].area, 4 * 3.5, accuracy: 1e-6)
        // Original intacto.
        XCTAssertEqual(editor.original, original)
        XCTAssertEqual(original.rooms[0].area, 12, accuracy: 1e-6)
        original = editor.original
    }

    func testMoveWallWithoutDraggingConnected() throws {
        var (editor, _) = makeEditor()
        let north = try XCTUnwrap(editor.plan.walls.first { $0.sourceSurfaceID == Fixtures.ids.n })
        editor.moveWall(north.id, by: Point2D(x: 0, y: -0.5), dragConnected: false)
        let west = try XCTUnwrap(editor.plan.walls.first { $0.sourceSurfaceID == Fixtures.ids.w })
        XCTAssertEqual(min(west.start.y, west.end.y), 0, accuracy: 1e-9)
    }

    func testUndoRedoAndReset() throws {
        var (editor, original) = makeEditor()
        XCTAssertFalse(editor.canUndo)
        let door = try XCTUnwrap(editor.plan.openings.first { $0.kind == .door })
        editor.moveOpening(door.id, toOffset: 2.0)
        editor.renameRoom(editor.plan.rooms[0].id, to: "Consultório")
        XCTAssertTrue(editor.hasChanges)
        XCTAssertEqual(editor.plan.rooms[0].name, "Consultório")

        editor.undo()
        XCTAssertEqual(editor.plan.rooms[0].name, "Sala")
        editor.undo()
        XCTAssertEqual(editor.plan, original)
        XCTAssertFalse(editor.canUndo)
        XCTAssertTrue(editor.canRedo)
        editor.redo()
        editor.redo()
        XCTAssertEqual(editor.plan.rooms[0].name, "Consultório")

        editor.resetToOriginal()
        XCTAssertEqual(editor.plan, original)
        editor.undo()
        XCTAssertEqual(editor.plan.rooms[0].name, "Consultório")
    }

    func testNewEditClearsRedoStack() throws {
        var (editor, _) = makeEditor()
        let room = editor.plan.rooms[0].id
        editor.renameRoom(room, to: "A")
        editor.undo()
        XCTAssertTrue(editor.canRedo)
        editor.renameRoom(room, to: "B")
        XCTAssertFalse(editor.canRedo)
    }

    func testGestureCollapsesIntoSingleUndoStep() throws {
        var (editor, original) = makeEditor()
        let north = try XCTUnwrap(editor.plan.walls.first { $0.sourceSurfaceID == Fixtures.ids.n })
        editor.beginGesture()
        for _ in 0..<10 { editor.moveWall(north.id, by: Point2D(x: 0, y: -0.05)) }
        editor.endGesture()
        XCTAssertEqual(editor.plan.wall(north.id)!.start.y, -0.5, accuracy: 1e-9)
        editor.undo()
        XCTAssertEqual(editor.plan, original)
        XCTAssertFalse(editor.canUndo)
    }

    func testEmptyGestureLeavesNoHistory() {
        var (editor, _) = makeEditor()
        editor.beginGesture()
        editor.endGesture()
        XCTAssertFalse(editor.canUndo)
    }

    func testRemoveWallRemovesItsOpeningsAndIssues() throws {
        var (editor, _) = makeEditor()
        let south = try XCTUnwrap(editor.plan.walls.first { $0.sourceSurfaceID == Fixtures.ids.s })
        XCTAssertTrue(editor.removeWall(south.id))
        XCTAssertNil(editor.plan.wall(south.id))
        XCTAssertFalse(editor.plan.openings.contains { $0.kind == .door })
        XCTAssertFalse(editor.plan.rooms[0].wallIDs.contains(south.id))
        XCTAssertFalse(editor.removeWall(south.id))
    }

    func testAddWallAndOpeningWithClamping() throws {
        var (editor, _) = makeEditor()
        XCTAssertNil(editor.addWall(from: .zero, to: .zero))
        let id = try XCTUnwrap(editor.addWall(from: Point2D(x: 0, y: 1.5), to: Point2D(x: 4, y: 1.5)))
        XCTAssertEqual(editor.plan.wall(id)?.origin, .userAdded)

        let o = try XCTUnwrap(editor.addOpening(kind: .door, onWall: id, offset: -3))
        XCTAssertEqual(editor.plan.openings.first { $0.id == o }!.offset, 0.45, accuracy: 1e-9)
        XCTAssertTrue(editor.resizeOpening(o, width: 2.0))
        XCTAssertEqual(editor.plan.openings.first { $0.id == o }!.offset, 1.0, accuracy: 1e-9)
        XCTAssertTrue(editor.setOpeningKind(o, to: .window))
        XCTAssertEqual(editor.plan.openings.first { $0.id == o }!.sillHeight, 0.9, accuracy: 1e-9)
        XCTAssertTrue(editor.removeOpening(o))
    }

    func testShorteningWallClampsOpening() throws {
        var (editor, _) = makeEditor()
        let south = try XCTUnwrap(editor.plan.walls.first { $0.sourceSurfaceID == Fixtures.ids.s })
        let door = try XCTUnwrap(editor.plan.openings.first { $0.wallID == south.id })
        // Encurta a parede a partir do fim, deixando a porta para fora.
        let isEndOfX: Bool = south.end.x > south.start.x
        editor.moveEndpoint(ofWall: south.id, isEnd: isEndOfX, to: Point2D(x: 0.5, y: 3), dragConnected: false)
        let updated = editor.plan.openings.first { $0.id == door.id }!
        let wall = editor.plan.wall(south.id)!
        XCTAssertLessThanOrEqual(updated.offset + updated.width / 2, wall.length + 1e-9)
    }

    func testRoomVertexEditingKeepsMinimumOfThree() throws {
        var (editor, _) = makeEditor()
        let room = editor.plan.rooms[0].id
        XCTAssertTrue(editor.insertRoomVertex(room: room, after: 0, at: Point2D(x: 2, y: -0.2)))
        XCTAssertEqual(editor.plan.rooms[0].outline.count, 5)
        XCTAssertTrue(editor.moveRoomVertex(room: room, index: 1, to: Point2D(x: 2, y: -0.3)))
        XCTAssertTrue(editor.removeRoomVertex(room: room, index: 1))
        XCTAssertTrue(editor.removeRoomVertex(room: room, index: 0))
        XCTAssertFalse(editor.removeRoomVertex(room: room, index: 0))
        XCTAssertEqual(editor.plan.rooms[0].outline.count, 3)
        XCTAssertFalse(editor.renameRoom(room, to: "   "))
    }

    func testEditingAFlaggedWallResolvesItsIssue() throws {
        var snap = Fixtures.rectangularRoom()
        let i = snap.surfaces.firstIndex { $0.id == Fixtures.ids.w }!
        snap.surfaces[i].confidence = .low
        let project = Fixtures.project(snap)
        var editor = FloorPlanEditor(original: project.original)
        let flagged = try XCTUnwrap(editor.plan.issues.first { $0.kind == .lowConfidence })
        XCTAssertTrue(editor.moveWall(flagged.targetIDs[0], by: Point2D(x: 0.02, y: 0)))
        XCTAssertFalse(editor.plan.issues.contains { $0.id == flagged.id })
        editor.undo()
        XCTAssertTrue(editor.plan.issues.contains { $0.id == flagged.id })
        XCTAssertTrue(editor.dismissIssue(flagged.id))
    }

    func testRebuildOutlineFromWalls() throws {
        var (editor, _) = makeEditor()
        let room = editor.plan.rooms[0].id
        let east = try XCTUnwrap(editor.plan.walls.first { $0.sourceSurfaceID == Fixtures.ids.e })
        editor.moveWall(east.id, by: Point2D(x: 1, y: 0))
        editor.moveRoomVertex(room: room, index: 0, to: Point2D(x: -9, y: -9))
        XCTAssertTrue(editor.rebuildRoomOutlineFromWalls(room: room))
        XCTAssertEqual(editor.plan.rooms[0].area, 15, accuracy: 1e-6)
    }
}
