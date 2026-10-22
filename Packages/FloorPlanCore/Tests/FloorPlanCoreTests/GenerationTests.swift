import XCTest
@testable import FloorPlanCore

final class GenerationTests: XCTestCase {
    func testNormalizerProjectsSurfacesOntoTopDownPlane() {
        let n = GeometryNormalizer.normalize(Fixtures.rectangularRoom(), captureID: UUID())
        XCTAssertEqual(n.walls.count, 4)
        let north = n.walls.first { $0.surfaceID == Fixtures.ids.n }!
        XCTAssertEqual(north.start.x, 0.08, accuracy: 1e-9)
        XCTAssertEqual(north.end.x, 3.92, accuracy: 1e-9)
        XCTAssertEqual(north.start.y, 0, accuracy: 1e-9)
        XCTAssertEqual(north.height, 2.5, accuracy: 1e-9)

        let west = n.walls.first { $0.surfaceID == Fixtures.ids.w }!
        XCTAssertEqual(west.start.x, 0, accuracy: 1e-9)
        XCTAssertEqual(abs(west.end.y - west.start.y), 2.84, accuracy: 1e-9)

        let window = n.openings.first { $0.kind == .window }!
        XCTAssertEqual(window.sillHeight, 0.9, accuracy: 1e-9)
        let door = n.openings.first { $0.kind == .door }!
        XCTAssertEqual(door.sillHeight, 0, accuracy: 1e-9)

        let floor = Bounds2D(points: n.floorPolygons[0])!
        XCTAssertEqual(floor.min.x, 0, accuracy: 1e-9)
        XCTAssertEqual(floor.max.x, 4, accuracy: 1e-9)
        XCTAssertEqual(floor.min.y, 0, accuracy: 1e-9)
        XCTAssertEqual(floor.max.y, 3, accuracy: 1e-9)
    }

    func testNormalizerReportsInvalidSurface() {
        var snap = Fixtures.rectangularRoom()
        snap.surfaces.append(SurfaceSnapshot(kind: .wall, transform: [1, 2, 3], dimensions: [1, 1, 0]))
        let n = GeometryNormalizer.normalize(snap)
        XCTAssertEqual(n.warnings.map(\.kind), [.invalidSurface])
        XCTAssertEqual(n.walls.count, 4)
    }

    func testGeneratorClosesCornersAndBuildsRoom() {
        let plan = FloorPlanGenerator.generate(captures: [Fixtures.capture(Fixtures.rectangularRoom())], roomNames: ["Sala"])
        XCTAssertEqual(plan.walls.count, 4)
        XCTAssertFalse(plan.issues.contains { $0.kind == .openCorner })
        XCTAssertFalse(plan.issues.contains { $0.kind == .openRoomOutline })

        let room = try! XCTUnwrap(plan.rooms.first)
        XCTAssertEqual(room.name, "Sala")
        XCTAssertEqual(room.area, 12, accuracy: 1e-6)
        XCTAssertEqual(room.outline.count, 4)
        XCTAssertEqual(room.wallIDs.count, 4)
        XCTAssertGreaterThan(Geometry.signedArea(room.outline), 0)

        for corner in [Point2D(x: 0, y: 0), Point2D(x: 4, y: 0), Point2D(x: 4, y: 3), Point2D(x: 0, y: 3)] {
            XCTAssertTrue(room.outline.contains { $0.distance(to: corner) < 1e-6 }, "canto \(corner) ausente")
        }
        for w in plan.walls { XCTAssertEqual(w.thickness, 0.10, accuracy: 1e-9) }
    }

    func testOpeningsAttachToParentWall() throws {
        let plan = FloorPlanGenerator.generate(captures: [Fixtures.capture(Fixtures.rectangularRoom())])
        XCTAssertEqual(plan.openings.count, 2)
        let door = try XCTUnwrap(plan.openings.first { $0.kind == .door })
        let south = try XCTUnwrap(plan.wall(door.wallID))
        XCTAssertEqual(south.sourceSurfaceID, Fixtures.ids.s)
        XCTAssertEqual(door.width, 0.9, accuracy: 1e-9)
        XCTAssertEqual(door.isOpen, false)
        // Centro da porta continua em X=1 depois de ajustar os cantos.
        XCTAssertEqual(south.point(atOffset: door.offset).x, 1, accuracy: 1e-6)
        let window = try XCTUnwrap(plan.openings.first { $0.kind == .window })
        XCTAssertEqual(plan.wall(window.wallID)!.point(atOffset: window.offset).x, 3, accuracy: 1e-6)
    }

    func testMissingWallFlagsOpenCornersAndFallsBackToFloor() {
        let plan = FloorPlanGenerator.generate(captures: [Fixtures.capture(Fixtures.rectangularRoom(includeEast: false))])
        XCTAssertEqual(plan.walls.count, 3)
        XCTAssertTrue(plan.issues.contains { $0.kind == .openRoomOutline })
        XCTAssertEqual(plan.issues.filter { $0.kind == .openCorner }.count, 2)
        // Contorno vem do piso do RoomPlan.
        XCTAssertEqual(plan.rooms.first?.area ?? 0, 12, accuracy: 1e-6)
        XCTAssertTrue(plan.rooms.first?.wallIDs.isEmpty ?? false)
    }

    func testOrphanOpeningFarFromAnyWallIsReportedNotDropped() {
        var snap = Fixtures.rectangularRoom(orphanDoor: true)
        // Tira a porta de perto de qualquer parede.
        let i = snap.surfaces.firstIndex { $0.kind == .door }!
        snap.surfaces[i].transform = Fixtures.transform(x: 2, y: 1.05, z: 1.5)
        let plan = FloorPlanGenerator.generate(captures: [Fixtures.capture(snap)])
        XCTAssertEqual(plan.issues.filter { $0.kind == .orphanOpening }.count, 1)
        XCTAssertEqual(plan.openings.count, 1)
    }

    func testOrphanOpeningNearAWallFallsBackToNearestWall() {
        let plan = FloorPlanGenerator.generate(captures: [Fixtures.capture(Fixtures.rectangularRoom(orphanDoor: true))])
        XCTAssertFalse(plan.issues.contains { $0.kind == .orphanOpening })
        XCTAssertEqual(plan.openings.count, 2)
    }

    func testLowConfidenceAndIncompleteEdgesAreFlagged() {
        var snap = Fixtures.rectangularRoom(doorConfidence: .low)
        let i = snap.surfaces.firstIndex { $0.id == Fixtures.ids.w }!
        snap.surfaces[i].confidence = .low
        snap.surfaces[i].completedEdges = [.top, .bottom]
        snap.surfaces[i].isCurved = true
        let plan = FloorPlanGenerator.generate(captures: [Fixtures.capture(snap)])
        let kinds = plan.issues.map(\.kind)
        XCTAssertEqual(kinds.filter { $0 == .lowConfidence }.count, 2)
        XCTAssertTrue(kinds.contains(.incompleteEdges))
        XCTAssertTrue(kinds.contains(.curvedWall))
    }

    func testShortWallsAreDroppedWithInfoIssue() {
        var snap = Fixtures.rectangularRoom()
        snap.surfaces.append(SurfaceSnapshot(kind: .wall, transform: Fixtures.transform(x: 1, y: 1, z: 1),
                                             dimensions: [0.05, 2, 0]))
        let plan = FloorPlanGenerator.generate(captures: [Fixtures.capture(snap)])
        XCTAssertEqual(plan.walls.count, 4)
        XCTAssertEqual(plan.issues.first { $0.kind == .shortWall }?.severity, .info)
    }

    func testEmptyCaptureReportsNoWalls() {
        let plan = FloorPlanGenerator.generate(captures: [Fixtures.capture(CapturedRoomSnapshot(surfaces: []))])
        XCTAssertTrue(plan.walls.isEmpty)
        XCTAssertTrue(plan.rooms.isEmpty)
        XCTAssertEqual(plan.issues.map(\.kind), [.noWalls])
    }

    func testRotatedRoomKeepsDimensions() {
        // Mesma sala girada 30° em torno de Y: área e comprimentos preservados.
        let yaw = Double.pi / 6
        func rot(_ x: Double, _ z: Double) -> (Double, Double) {
            (x * cos(yaw) + z * sin(yaw), -x * sin(yaw) + z * cos(yaw))
        }
        let h = 2.5
        func wall(_ cx: Double, _ cz: Double, _ extraYaw: Double, _ w: Double) -> SurfaceSnapshot {
            let (x, z) = rot(cx, cz)
            return SurfaceSnapshot(kind: .wall, transform: Fixtures.transform(x: x, y: h / 2, z: z, yaw: yaw + extraYaw),
                                   dimensions: [w, h, 0])
        }
        let snap = CapturedRoomSnapshot(surfaces: [
            wall(2, 0, 0, 3.9), wall(2, 3, 0, 3.9), wall(0, 1.5, -.pi / 2, 2.9), wall(4, 1.5, -.pi / 2, 2.9)
        ])
        let room = FloorPlanGenerator.generate(captures: [Fixtures.capture(snap)]).rooms.first
        XCTAssertEqual(room?.area ?? 0, 12, accuracy: 1e-6)
    }

    func testPlacementTransformMovesWholePlan() {
        let placed = Fixtures.capture(Fixtures.rectangularRoom(),
                                      placement: Transform2D(rotation: 0, translation: Point2D(x: 10, y: -5)))
        let room = FloorPlanGenerator.generate(captures: [placed]).rooms.first!
        let b = Bounds2D(points: room.outline)!
        XCTAssertEqual(b.min.x, 10, accuracy: 1e-6)
        XCTAssertEqual(b.min.y, -5, accuracy: 1e-6)
        XCTAssertEqual(room.area, 12, accuracy: 1e-6)
    }

    func testTJunctionExtendsWallIntoOtherWall() {
        // Parede divisória parada 10 cm antes da parede norte.
        var snap = Fixtures.rectangularRoom()
        let dividerID = UUID()
        snap.surfaces.append(SurfaceSnapshot(id: dividerID, kind: .wall,
                                             transform: Fixtures.transform(x: 2, y: 1.25, z: 1.55, yaw: -.pi / 2),
                                             dimensions: [3 - 0.1 - 0.08, 2.5, 0]))
        let plan = FloorPlanGenerator.generate(captures: [Fixtures.capture(snap)])
        let divider = plan.walls.first { $0.sourceSurfaceID == dividerID }!
        let ys = [divider.start.y, divider.end.y].sorted()
        XCTAssertEqual(ys[0], 0, accuracy: 1e-6)
        XCTAssertEqual(ys[1], 3, accuracy: 1e-6)
    }
}
