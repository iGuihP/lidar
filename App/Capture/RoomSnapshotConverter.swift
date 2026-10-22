import Foundation
import RoomPlan
import simd
import FloorPlanCore

/// Única fronteira entre os tipos do RoomPlan e o núcleo: copia o `CapturedRoom` para um
/// `CapturedRoomSnapshot` (sem simd, sem RoomPlan) que é gravado como geometria original.
enum RoomSnapshotConverter {
    static func snapshot(from room: CapturedRoom) -> CapturedRoomSnapshot {
        var surfaces: [SurfaceSnapshot] = []
        surfaces += room.walls.map { convert($0, as: .wall) }
        surfaces += room.doors.map { convert($0, as: .door) }
        surfaces += room.windows.map { convert($0, as: .window) }
        surfaces += room.openings.map { convert($0, as: .opening) }
        surfaces += room.floors.map { convert($0, as: .floor) }

        let objects = room.objects.map { o in
            ObjectSnapshot(id: o.identifier,
                           category: String(describing: o.category),
                           confidence: confidence(o.confidence),
                           transform: flatten(o.transform),
                           dimensions: vector(o.dimensions))
        }

        return CapturedRoomSnapshot(roomID: room.identifier,
                                    story: room.story,
                                    roomPlanVersion: room.version,
                                    surfaces: surfaces,
                                    objects: objects,
                                    sections: room.sections.map { String(describing: $0.label) })
    }

    private static func convert(_ s: CapturedRoom.Surface, as kind: SurfaceSnapshot.Kind) -> SurfaceSnapshot {
        var isOpen: Bool?
        if case .door(let open) = s.category { isOpen = open }

        let edges: [SurfaceSnapshot.Edge] = s.completedEdges.compactMap { edge in
            switch edge {
            case .top: return .top
            case .left: return .left
            case .bottom: return .bottom
            case .right: return .right
            @unknown default: return nil
            }
        }

        return SurfaceSnapshot(id: s.identifier,
                               parentID: s.parentIdentifier,
                               kind: kind,
                               isDoorOpen: isOpen,
                               confidence: confidence(s.confidence),
                               transform: flatten(s.transform),
                               dimensions: vector(s.dimensions),
                               polygonCorners: s.polygonCorners.map { vector($0) },
                               completedEdges: edges,
                               isCurved: s.curve != nil)
    }

    private static func confidence(_ c: CapturedRoom.Confidence) -> SurfaceSnapshot.Confidence {
        switch c {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        @unknown default: return .medium
        }
    }

    /// Column-major, como `simd_float4x4`.
    private static func flatten(_ m: simd_float4x4) -> [Double] {
        [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap {
            [Double($0.x), Double($0.y), Double($0.z), Double($0.w)]
        }
    }

    private static func vector(_ v: simd_float3) -> [Double] {
        [Double(v.x), Double(v.y), Double(v.z)]
    }
}
