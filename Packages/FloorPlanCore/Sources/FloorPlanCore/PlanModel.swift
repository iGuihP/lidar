import Foundation

public struct Wall: Codable, Equatable, Identifiable, Sendable {
    public enum Origin: String, Codable, Sendable { case captured, userAdded }

    public var id: UUID
    public var start: Point2D
    public var end: Point2D
    /// Espessura visual em metros. Estimada (o RoomPlan não mede espessura de parede).
    public var thickness: Double
    /// Altura em metros, quando conhecida.
    public var height: Double?
    public var sourceSurfaceID: UUID?
    public var origin: Origin

    public init(id: UUID = UUID(), start: Point2D, end: Point2D, thickness: Double = 0.10,
                height: Double? = nil, sourceSurfaceID: UUID? = nil, origin: Origin = .captured) {
        self.id = id
        self.start = start
        self.end = end
        self.thickness = thickness
        self.height = height
        self.sourceSurfaceID = sourceSurfaceID
        self.origin = origin
    }

    public var length: Double { start.distance(to: end) }
    public var direction: Point2D { (end - start).normalized }
    public var midpoint: Point2D { Point2D(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2) }

    public func point(atOffset offset: Double) -> Point2D { start + direction * offset }
}

public struct Opening: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case door, window, opening }

    public var id: UUID
    public var kind: Kind
    public var wallID: UUID
    /// Distância, em metros, do início da parede até o **centro** da abertura.
    public var offset: Double
    public var width: Double
    public var height: Double
    /// Altura do peitoril em relação ao piso (0 para portas).
    public var sillHeight: Double
    public var isOpen: Bool?
    public var sourceSurfaceID: UUID?

    public init(id: UUID = UUID(), kind: Kind, wallID: UUID, offset: Double, width: Double,
                height: Double = 2.1, sillHeight: Double = 0, isOpen: Bool? = nil,
                sourceSurfaceID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.wallID = wallID
        self.offset = offset
        self.width = width
        self.height = height
        self.sillHeight = sillHeight
        self.isOpen = isOpen
        self.sourceSurfaceID = sourceSurfaceID
    }
}

public struct Room: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Polígono fechado (sem repetir o primeiro vértice), em metros.
    public var outline: [Point2D]
    /// Paredes que formam o contorno, quando ele veio de um laço de paredes (sem ordem garantida).
    public var wallIDs: [UUID]
    public var captureID: UUID?

    public init(id: UUID = UUID(), name: String, outline: [Point2D], wallIDs: [UUID] = [],
                captureID: UUID? = nil) {
        self.id = id
        self.name = name
        self.outline = outline
        self.wallIDs = wallIDs
        self.captureID = captureID
    }

    /// Área em m² (valor absoluto do polígono).
    public var area: Double { abs(Geometry.signedArea(outline)) }
}

/// Ponto da planta que precisa de conferência manual.
public struct ReviewIssue: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case lowConfidence, incompleteEdges, curvedWall, openCorner
        case orphanOpening, openRoomOutline, shortWall, invalidSurface, noWalls
    }
    public enum Severity: String, Codable, Sendable { case info, warning }

    public var id: UUID
    public var kind: Kind
    public var severity: Severity
    /// Paredes/aberturas/superfícies envolvidas.
    public var targetIDs: [UUID]
    public var location: Point2D?
    /// Valor numérico associado (ex.: tamanho da lacuna em metros).
    public var value: Double?

    public init(id: UUID = UUID(), kind: Kind, severity: Severity = .warning,
                targetIDs: [UUID] = [], location: Point2D? = nil, value: Double? = nil) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.targetIDs = targetIDs
        self.location = location
        self.value = value
    }
}

public struct FloorPlan: Codable, Equatable, Sendable {
    public var walls: [Wall]
    public var openings: [Opening]
    public var rooms: [Room]
    public var issues: [ReviewIssue]

    public init(walls: [Wall] = [], openings: [Opening] = [], rooms: [Room] = [], issues: [ReviewIssue] = []) {
        self.walls = walls
        self.openings = openings
        self.rooms = rooms
        self.issues = issues
    }

    public func wall(_ id: UUID) -> Wall? { walls.first { $0.id == id } }
    public func openings(on wallID: UUID) -> [Opening] { openings.filter { $0.wallID == wallID } }

    /// Retângulo que contém paredes (com espessura) e contornos de ambientes.
    public var bounds: Bounds2D? {
        var pts: [Point2D] = []
        for w in walls {
            let n = w.direction.perpendicular * (w.thickness / 2)
            pts += [w.start + n, w.start - n, w.end + n, w.end - n]
        }
        for r in rooms { pts += r.outline }
        return Bounds2D(points: pts)
    }

    /// Parede mais próxima de um ponto, dentro de `tolerance` metros (considera a meia-espessura).
    public func nearestWall(to p: Point2D, tolerance: Double) -> Wall? {
        var best: (Wall, Double)?
        for w in walls {
            let d = Geometry.distance(from: p, toSegment: w.start, w.end).distance - w.thickness / 2
            if d <= tolerance, best == nil || d < best!.1 { best = (w, d) }
        }
        return best?.0
    }
}
