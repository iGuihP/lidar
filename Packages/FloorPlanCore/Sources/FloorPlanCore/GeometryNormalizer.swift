import Foundation

/// Geometria de uma captura já projetada no plano de cima (metros), ainda sem correções.
public struct NormalizedCapture: Equatable, Sendable {
    public struct WallSegment: Equatable, Sendable {
        public var surfaceID: UUID
        public var start: Point2D
        public var end: Point2D
        public var height: Double
        public var confidence: SurfaceSnapshot.Confidence
        public var hasIncompleteEnds: Bool
        public var isCurved: Bool
        public var length: Double { start.distance(to: end) }
    }

    public struct OpeningItem: Equatable, Sendable {
        public var surfaceID: UUID
        public var parentID: UUID?
        public var kind: Opening.Kind
        public var center: Point2D
        public var width: Double
        public var height: Double
        public var sillHeight: Double
        public var isOpen: Bool?
        public var confidence: SurfaceSnapshot.Confidence
    }

    public var captureID: UUID
    public var walls: [WallSegment]
    public var openings: [OpeningItem]
    /// Polígonos de piso no plano (um por superfície `floor`).
    public var floorPolygons: [[Point2D]]
    public var warnings: [ReviewIssue]
}

/// Converte o snapshot 3D (mundo ARKit, Y para cima) em segmentos 2D de vista superior.
///
/// Cada parede/porta/janela/abertura do RoomPlan é um retângulo no plano local XY da superfície:
/// o eixo local X (coluna 0 do `transform`) corre ao longo da superfície, `dimensions.x` é a largura.
/// Projetar no plano da planta é descartar Y: `(X, Z)`.
public enum GeometryNormalizer {
    public static func normalize(_ capture: CaptureRecord) -> NormalizedCapture {
        normalize(capture.snapshot, captureID: capture.id, placement: capture.placement)
    }

    public static func normalize(_ snapshot: CapturedRoomSnapshot, captureID: UUID = UUID(),
                                 placement: Transform2D = .identity) -> NormalizedCapture {
        var warnings: [ReviewIssue] = []
        var walls: [NormalizedCapture.WallSegment] = []
        var openingSurfaces: [(SurfaceSnapshot, Pose)] = []
        var floors: [[Point2D]] = []
        var wallBottoms: [Double] = []

        for s in snapshot.surfaces {
            guard s.transform.count == 16, s.dimensions.count == 3,
                  (s.transform + s.dimensions).allSatisfy({ $0.isFinite }),
                  let pose = Pose(s, placement: placement) else {
                warnings.append(ReviewIssue(kind: .invalidSurface, targetIDs: [s.id]))
                continue
            }
            switch s.kind {
            case .wall:
                let half = s.dimensions[0] / 2
                walls.append(.init(
                    surfaceID: s.id,
                    start: pose.center - pose.direction * half,
                    end: pose.center + pose.direction * half,
                    height: s.dimensions[1],
                    confidence: s.confidence,
                    hasIncompleteEnds: !(s.completedEdges.contains(.left) && s.completedEdges.contains(.right)),
                    isCurved: s.isCurved))
                wallBottoms.append(pose.elevation - s.dimensions[1] / 2)
            case .door, .window, .opening:
                openingSurfaces.append((s, pose))
            case .floor:
                floors.append(floorPolygon(s, placement: placement))
            }
        }

        let floorElevation = wallBottoms.min() ?? 0
        let openings: [NormalizedCapture.OpeningItem] = openingSurfaces.map { s, pose in
            let kind: Opening.Kind = s.kind == .door ? .door : (s.kind == .window ? .window : .opening)
            let bottom = pose.elevation - s.dimensions[1] / 2
            return .init(surfaceID: s.id, parentID: s.parentID, kind: kind, center: pose.center,
                         width: s.dimensions[0], height: s.dimensions[1],
                         sillHeight: max(0, bottom - floorElevation), isOpen: s.isDoorOpen,
                         confidence: s.confidence)
        }

        return NormalizedCapture(captureID: captureID, walls: walls, openings: openings,
                                 floorPolygons: floors.filter { $0.count >= 3 }, warnings: warnings)
    }

    // MARK: - Helpers

    /// Centro, direção horizontal do eixo X local e cota (Y do mundo) de uma superfície.
    private struct Pose {
        var center: Point2D
        var direction: Point2D
        var elevation: Double

        init?(_ s: SurfaceSnapshot, placement: Transform2D) {
            let t = s.transform
            let dir = Point2D(x: t[0], y: t[2])
            guard dir.length > 1e-6 else { return nil }
            center = placement.apply(Point2D(x: t[12], y: t[14]))
            direction = placement.applyDirection(dir.normalized)
            elevation = t[13]
        }
    }

    /// Vértices do piso no plano. Usa `polygonCorners` (espaço local) quando existem; senão o
    /// retângulo `dimensions.x × dimensions.y`.
    private static func floorPolygon(_ s: SurfaceSnapshot, placement: Transform2D) -> [Point2D] {
        let t = s.transform
        var local = s.polygonCorners.filter { $0.count == 3 }
        if local.count < 3 {
            let hx = s.dimensions[0] / 2, hy = s.dimensions[1] / 2
            local = [[-hx, -hy, 0], [hx, -hy, 0], [hx, hy, 0], [-hx, hy, 0]]
        }
        return local.map { p in
            let worldX = t[0] * p[0] + t[4] * p[1] + t[8] * p[2] + t[12]
            let worldZ = t[2] * p[0] + t[6] * p[1] + t[10] * p[2] + t[14]
            return placement.apply(Point2D(x: worldX, y: worldZ))
        }
    }
}
