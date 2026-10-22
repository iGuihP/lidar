import Foundation

public struct GeneratorSettings: Codable, Equatable, Sendable {
    /// Espessura visual padrão das paredes (m). Estimativa: o RoomPlan não mede espessura.
    public var wallThickness: Double = 0.10
    /// Distância máxima (m) para fechar/ajustar um canto entre duas paredes.
    public var cornerSnapTolerance: Double = 0.30
    /// Paredes menores que isso (m) são descartadas como ruído.
    public var minWallLength: Double = 0.10
    /// |seno| mínimo do ângulo entre duas paredes para tratá-las como não paralelas (~15°).
    public var minNonParallelSine: Double = 0.26
    /// Uma ponta de parede a mais que isso (m) de qualquer outra parede é "canto aberto".
    public var openEndTolerance: Double = 0.15
    /// Distância máxima (m) para associar a uma parede uma abertura sem parede-pai válida.
    public var orphanOpeningTolerance: Double = 0.30
    public var generatorVersion: Int = 1

    public init() {}
}

/// Gera a planta 2D (paredes, aberturas, ambientes e alertas) a partir da geometria normalizada.
public enum FloorPlanGenerator {
    public static func generate(captures: [CaptureRecord], roomNames: [String] = [],
                                settings: GeneratorSettings = GeneratorSettings()) -> FloorPlan {
        var plan = FloorPlan()
        for (i, capture) in captures.enumerated() {
            let name = i < roomNames.count ? roomNames[i] : "Ambiente \(i + 1)"
            let part = generate(normalized: GeometryNormalizer.normalize(capture), roomName: name, settings: settings)
            plan.walls += part.walls
            plan.openings += part.openings
            plan.rooms += part.rooms
            plan.issues += part.issues
        }
        return plan
    }

    public static func generate(normalized n: NormalizedCapture, roomName: String,
                                settings s: GeneratorSettings = GeneratorSettings()) -> FloorPlan {
        var issues = n.warnings
        var walls: [Wall] = []

        for seg in n.walls {
            let mid = Point2D(x: (seg.start.x + seg.end.x) / 2, y: (seg.start.y + seg.end.y) / 2)
            if seg.length < s.minWallLength {
                issues.append(ReviewIssue(kind: .shortWall, severity: .info, targetIDs: [seg.surfaceID],
                                          location: mid, value: seg.length))
                continue
            }
            let wall = Wall(start: seg.start, end: seg.end, thickness: s.wallThickness,
                            height: seg.height, sourceSurfaceID: seg.surfaceID)
            walls.append(wall)
            if seg.confidence == .low {
                issues.append(ReviewIssue(kind: .lowConfidence, targetIDs: [wall.id], location: mid))
            }
            if seg.hasIncompleteEnds {
                issues.append(ReviewIssue(kind: .incompleteEdges, targetIDs: [wall.id], location: mid))
            }
            if seg.isCurved {
                issues.append(ReviewIssue(kind: .curvedWall, targetIDs: [wall.id], location: mid))
            }
        }

        if walls.isEmpty {
            issues.append(ReviewIssue(kind: .noWalls))
        }

        let snapped = snapCorners(&walls, settings: s)
        issues += openEnds(walls: walls, snapped: snapped, settings: s)

        var openings: [Opening] = []
        for o in n.openings {
            guard let wall = hostWall(for: o, in: walls, settings: s) else {
                issues.append(ReviewIssue(kind: .orphanOpening, targetIDs: [o.surfaceID], location: o.center))
                continue
            }
            let width = min(o.width, wall.length)
            let rawOffset = (o.center - wall.start).dot(wall.direction)
            let offset = min(max(rawOffset, width / 2), wall.length - width / 2)
            let opening = Opening(kind: o.kind, wallID: wall.id, offset: offset, width: width,
                                  height: o.height, sillHeight: o.sillHeight, isOpen: o.isOpen,
                                  sourceSurfaceID: o.surfaceID)
            openings.append(opening)
            if o.confidence == .low {
                issues.append(ReviewIssue(kind: .lowConfidence, targetIDs: [opening.id], location: o.center))
            }
        }

        var rooms: [Room] = []
        if let loop = closedLoop(walls) {
            rooms.append(Room(name: roomName, outline: loop.outline, wallIDs: loop.wallIDs, captureID: n.captureID))
        } else if !walls.isEmpty {
            // Sem laço fechado: usa o piso do RoomPlan ou, em último caso, o fecho convexo das paredes.
            let floor = n.floorPolygons.max { abs(Geometry.signedArea($0)) < abs(Geometry.signedArea($1)) }
            var outline = floor ?? Geometry.convexHull(walls.flatMap { [$0.start, $0.end] })
            if outline.count >= 3 {
                if Geometry.signedArea(outline) < 0 { outline.reverse() }
                rooms.append(Room(name: roomName, outline: outline, captureID: n.captureID))
            }
            issues.append(ReviewIssue(kind: .openRoomOutline))
        }

        return FloorPlan(walls: walls, openings: openings, rooms: rooms, issues: issues)
    }

    // MARK: - Cantos

    private struct End: Hashable {
        var wall: Int
        var isEnd: Bool
    }

    private struct Candidate {
        var cost: Double
        var a: End
        var b: End?
        var point: Point2D
    }

    private static func endpoint(_ w: Wall, _ e: End) -> Point2D { e.isEnd ? w.end : w.start }

    private static func nearestEnd(of w: Wall, index: Int, to p: Point2D) -> (end: End, distance: Double) {
        let ds = p.distance(to: w.start), de = p.distance(to: w.end)
        return ds <= de ? (End(wall: index, isEnd: false), ds) : (End(wall: index, isEnd: true), de)
    }

    /// Fecha cantos: estende/apara as pontas de paredes que quase se encontram para o ponto de
    /// interseção (cantos em L, T e paredes colineares). Retorna as pontas ajustadas.
    private static func snapCorners(_ walls: inout [Wall], settings s: GeneratorSettings) -> Set<End> {
        let tol = s.cornerSnapTolerance
        var corners: [Candidate] = []
        var tees: [Candidate] = []

        for i in walls.indices {
            for j in walls.indices where j > i {
                let wi = walls[i], wj = walls[j]
                let di = wi.direction, dj = wj.direction
                let denom = di.cross(dj)

                if abs(denom) < s.minNonParallelSine {
                    // Quase paralelas: só une pontas colineares que quase se tocam.
                    for ai in [false, true] {
                        for bj in [false, true] {
                            let ea = End(wall: i, isEnd: ai), eb = End(wall: j, isEnd: bj)
                            let pa = endpoint(wi, ea), pb = endpoint(wj, eb)
                            let gap = pa.distance(to: pb)
                            let lateral = abs((pb - pa).cross(di))
                            if gap <= tol && lateral <= tol {
                                corners.append(Candidate(cost: gap, a: ea, b: eb,
                                                         point: Point2D(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)))
                            }
                        }
                    }
                    continue
                }

                let w = wj.start - wi.start
                let t = w.cross(dj) / denom
                let u = w.cross(di) / denom
                let p = wi.start + di * t
                let (ei, dI) = nearestEnd(of: wi, index: i, to: p)
                let (ej, dJ) = nearestEnd(of: wj, index: j, to: p)

                if dI <= tol && dJ <= tol {
                    corners.append(Candidate(cost: dI + dJ, a: ei, b: ej, point: p))
                } else if dI <= tol && u >= -tol && u <= wj.length + tol {
                    tees.append(Candidate(cost: dI, a: ei, b: nil, point: p))
                } else if dJ <= tol && t >= -tol && t <= wi.length + tol {
                    tees.append(Candidate(cost: dJ, a: ej, b: nil, point: p))
                }
            }
        }

        var used = Set<End>()
        func move(_ e: End, to p: Point2D) {
            if e.isEnd { walls[e.wall].end = p } else { walls[e.wall].start = p }
            used.insert(e)
        }
        for c in corners.sorted(by: { $0.cost < $1.cost }) {
            guard let b = c.b, !used.contains(c.a), !used.contains(b) else { continue }
            move(c.a, to: c.point)
            move(b, to: c.point)
        }
        for c in tees.sorted(by: { $0.cost < $1.cost }) where !used.contains(c.a) {
            move(c.a, to: c.point)
        }
        return used
    }

    /// Pontas que não foram ajustadas e não encostam em nenhuma outra parede.
    private static func openEnds(walls: [Wall], snapped: Set<End>, settings s: GeneratorSettings) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        for i in walls.indices {
            for isEnd in [false, true] {
                let e = End(wall: i, isEnd: isEnd)
                guard !snapped.contains(e) else { continue }
                let p = endpoint(walls[i], e)
                let touches = walls.indices.contains { j in
                    j != i && Geometry.distance(from: p, toSegment: walls[j].start, walls[j].end).distance <= s.openEndTolerance
                }
                if !touches {
                    issues.append(ReviewIssue(kind: .openCorner, targetIDs: [walls[i].id], location: p))
                }
            }
        }
        return issues
    }

    // MARK: - Aberturas

    private static func hostWall(for o: NormalizedCapture.OpeningItem, in walls: [Wall],
                                 settings s: GeneratorSettings) -> Wall? {
        if let pid = o.parentID, let w = walls.first(where: { $0.sourceSurfaceID == pid }) { return w }
        var best: (Wall, Double)?
        for w in walls {
            let d = Geometry.distance(from: o.center, toSegment: w.start, w.end).distance
            if d <= s.orphanOpeningTolerance, best == nil || d < best!.1 { best = (w, d) }
        }
        return best?.0
    }

    // MARK: - Contorno

    private struct NodeKey: Hashable {
        var x: Int
        var y: Int
        init(_ p: Point2D) {
            x = Int((p.x * 10_000).rounded())
            y = Int((p.y * 10_000).rounded())
        }
    }

    /// Maior laço fechado simples formado pelas paredes (todo nó com exatamente 2 paredes).
    static func closedLoop(_ walls: [Wall]) -> (outline: [Point2D], wallIDs: [UUID])? {
        var adjacency: [NodeKey: [(other: NodeKey, wall: Int)]] = [:]
        var position: [NodeKey: Point2D] = [:]
        for (i, w) in walls.enumerated() {
            let a = NodeKey(w.start), b = NodeKey(w.end)
            guard a != b else { continue }
            adjacency[a, default: []].append((b, i))
            adjacency[b, default: []].append((a, i))
            position[a] = w.start
            position[b] = w.end
        }

        var visited = Set<NodeKey>()
        var best: (outline: [Point2D], wallIDs: [UUID], area: Double)?

        for startKey in adjacency.keys.sorted(by: { ($0.x, $0.y) < ($1.x, $1.y) }) where !visited.contains(startKey) {
            // Componente conexo.
            var component: [NodeKey] = []
            var stack = [startKey]
            visited.insert(startKey)
            while let n = stack.popLast() {
                component.append(n)
                for (m, _) in adjacency[n] ?? [] where !visited.contains(m) {
                    visited.insert(m)
                    stack.append(m)
                }
            }
            guard component.count >= 3, component.allSatisfy({ adjacency[$0]?.count == 2 }) else { continue }

            // Percorre o ciclo.
            var keys: [NodeKey] = [startKey]
            var wallIdx: [Int] = []
            var prevWall = -1
            var current = startKey
            while true {
                guard let step = adjacency[current]?.first(where: { $0.wall != prevWall }) else { break }
                wallIdx.append(step.wall)
                prevWall = step.wall
                current = step.other
                if current == startKey { break }
                keys.append(current)
                if keys.count > component.count { break }
            }
            guard current == startKey, keys.count == component.count else { continue }

            var outline = keys.compactMap { position[$0] }
            var ids = wallIdx.map { walls[$0].id }
            let area = Geometry.signedArea(outline)
            if area < 0 {
                outline.reverse()
                ids.reverse()
            }
            if best == nil || abs(area) > best!.area {
                best = (outline, ids, abs(area))
            }
        }
        return best.map { ($0.outline, $0.wallIDs) }
    }
}
