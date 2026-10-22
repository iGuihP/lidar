import Foundation
@testable import FloorPlanCore

/// Fixtures **sintéticas** para testar a lógica geométrica. Não representam o resultado de um
/// escaneamento real: capturas reais do RoomPlan devem entrar em `Fixtures/` quando exportadas
/// de um aparelho (ver docs/VALIDATION.md).
enum Fixtures {
    /// Matriz 4x4 column-major com eixo local X em (cos, 0, -sin) (rotação em torno de Y), Y para cima.
    static func transform(x: Double, y: Double, z: Double, yaw: Double = 0) -> [Double] {
        let c = cos(yaw), s = sin(yaw)
        return [c, 0, -s, 0,
                0, 1, 0, 0,
                s, 0, c, 0,
                x, y, z, 1]
    }

    static let ids = (n: UUID(), s: UUID(), w: UUID(), e: UUID(), door: UUID(), window: UUID(), floor: UUID())

    /// Sala 4 m (X) × 3 m (Z), pé-direito 2,5 m, piso em Y=0. Paredes com 8 cm de folga em cada ponta
    /// (como o RoomPlan costuma entregar), porta na parede sul e janela na norte.
    static func rectangularRoom(gap: Double = 0.08, includeEast: Bool = true,
                                doorConfidence: SurfaceSnapshot.Confidence = .high,
                                orphanDoor: Bool = false) -> CapturedRoomSnapshot {
        let h = 2.5
        var surfaces: [SurfaceSnapshot] = [
            SurfaceSnapshot(id: ids.n, kind: .wall, transform: transform(x: 2, y: h / 2, z: 0),
                            dimensions: [4 - 2 * gap, h, 0]),
            SurfaceSnapshot(id: ids.s, kind: .wall, transform: transform(x: 2, y: h / 2, z: 3),
                            dimensions: [4 - 2 * gap, h, 0]),
            SurfaceSnapshot(id: ids.w, kind: .wall, transform: transform(x: 0, y: h / 2, z: 1.5, yaw: -.pi / 2),
                            dimensions: [3 - 2 * gap, h, 0]),
            SurfaceSnapshot(id: ids.door, parentID: orphanDoor ? UUID() : ids.s, kind: .door, isDoorOpen: false,
                            confidence: doorConfidence,
                            transform: transform(x: 1, y: 1.05, z: 3), dimensions: [0.9, 2.1, 0]),
            SurfaceSnapshot(id: ids.window, parentID: ids.n, kind: .window,
                            transform: transform(x: 3, y: 1.5, z: 0), dimensions: [1.2, 1.2, 0]),
            SurfaceSnapshot(id: ids.floor, kind: .floor,
                            transform: [1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, 2, 0, 1.5, 1],
                            dimensions: [4, 3, 0],
                            polygonCorners: [[-2, -1.5, 0], [2, -1.5, 0], [2, 1.5, 0], [-2, 1.5, 0]])
        ]
        if includeEast {
            surfaces.append(SurfaceSnapshot(id: ids.e, kind: .wall,
                                            transform: transform(x: 4, y: h / 2, z: 1.5, yaw: -.pi / 2),
                                            dimensions: [3 - 2 * gap, h, 0]))
        }
        return CapturedRoomSnapshot(roomPlanVersion: 2, surfaces: surfaces)
    }

    static func capture(_ snapshot: CapturedRoomSnapshot, placement: Transform2D = .identity) -> CaptureRecord {
        CaptureRecord(capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                      device: DeviceMetadata(deviceModel: "test", systemName: "iOS", systemVersion: "26.0",
                                             appVersion: "0.1", lidarSupported: true),
                      snapshot: snapshot, placement: placement)
    }

    static func project(_ snapshot: CapturedRoomSnapshot = rectangularRoom()) -> FloorPlanProject {
        FloorPlanProject.make(name: "Teste", capture: capture(snapshot), roomName: "Sala",
                              now: Date(timeIntervalSince1970: 1_700_000_100))
    }
}
