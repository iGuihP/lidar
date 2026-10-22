import Foundation

/// Edita a planta (geometria "editada") com desfazer/refazer. A geometria original nunca muda:
/// `original` é só referência para "restaurar".
///
/// Tipo-valor: guarde-o em um `@Observable`/`ObservableObject` na camada de UI.
///
/// Arrastos: chame `beginGesture()` ao tocar e `endGesture()` ao soltar para que o gesto inteiro
/// vire **uma** entrada no histórico.
public struct FloorPlanEditor: Equatable, Sendable {
    public private(set) var plan: FloorPlan
    public let original: FloorPlan

    private var undoStack: [FloorPlan] = []
    private var redoStack: [FloorPlan] = []
    private var gestureBaseline: FloorPlan?
    private let historyLimit = 200

    /// Pontas com distância menor que isto (m) são consideradas conectadas.
    public static let connectionTolerance = 1e-4

    public init(original: FloorPlan, edited: FloorPlan? = nil) {
        self.original = original
        self.plan = edited ?? original
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var hasChanges: Bool { plan != original }

    // MARK: - Histórico

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(plan)
        plan = previous
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(plan)
        plan = next
    }

    public mutating func beginGesture() {
        guard gestureBaseline == nil else { return }
        gestureBaseline = plan
    }

    public mutating func endGesture() {
        guard let base = gestureBaseline else { return }
        gestureBaseline = nil
        if base != plan { push(base) }
    }

    private mutating func push(_ snapshot: FloorPlan) {
        undoStack.append(snapshot)
        if undoStack.count > historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Aplica uma mutação registrando o estado anterior (a menos que esteja dentro de um gesto).
    @discardableResult
    private mutating func edit(_ change: (inout FloorPlan) -> Bool) -> Bool {
        var copy = plan
        guard change(&copy), copy != plan else { return false }
        if gestureBaseline == nil { push(plan) }
        plan = copy
        return true
    }

    public mutating func resetToOriginal() {
        let source = original
        edit { p in
            p = source
            return true
        }
    }

    // MARK: - Paredes

    /// Move a parede inteira. Pontas de outras paredes coladas nas pontas desta acompanham,
    /// assim como vértices de contorno de ambientes que coincidiam.
    @discardableResult
    public mutating func moveWall(_ id: UUID, by delta: Point2D, dragConnected: Bool = true) -> Bool {
        edit { p in
            guard let i = p.walls.firstIndex(where: { $0.id == id }) else { return false }
            let oldStart = p.walls[i].start, oldEnd = p.walls[i].end
            p.walls[i].start = oldStart + delta
            p.walls[i].end = oldEnd + delta
            if dragConnected {
                Self.follow(&p, except: id, from: oldStart, to: oldStart + delta)
                Self.follow(&p, except: id, from: oldEnd, to: oldEnd + delta)
            }
            Self.clearIssues(&p, targeting: [id])
            return true
        }
    }

    /// Move uma ponta de parede. As pontas conectadas acompanham.
    @discardableResult
    public mutating func moveEndpoint(ofWall id: UUID, isEnd: Bool, to point: Point2D,
                                      dragConnected: Bool = true) -> Bool {
        edit { p in
            guard let i = p.walls.firstIndex(where: { $0.id == id }) else { return false }
            let old = isEnd ? p.walls[i].end : p.walls[i].start
            if isEnd { p.walls[i].end = point } else { p.walls[i].start = point }
            if dragConnected { Self.follow(&p, except: id, from: old, to: point) }
            Self.clampOpenings(&p, onWalls: Set([id]))
            Self.clearIssues(&p, targeting: [id])
            return true
        }
    }

    @discardableResult
    public mutating func addWall(from a: Point2D, to b: Point2D, thickness: Double = 0.10,
                                 id: UUID = UUID()) -> UUID? {
        guard a.distance(to: b) > 1e-3 else { return nil }
        let ok = edit { p in
            p.walls.append(Wall(id: id, start: a, end: b, thickness: thickness, origin: .userAdded))
            return true
        }
        return ok ? id : nil
    }

    /// Remove a parede e as aberturas que estavam nela.
    @discardableResult
    public mutating func removeWall(_ id: UUID) -> Bool {
        edit { p in
            guard p.walls.contains(where: { $0.id == id }) else { return false }
            let openingIDs = p.openings.filter { $0.wallID == id }.map(\.id)
            p.walls.removeAll { $0.id == id }
            p.openings.removeAll { $0.wallID == id }
            for r in p.rooms.indices { p.rooms[r].wallIDs.removeAll { $0 == id } }
            Self.clearIssues(&p, targeting: Set([id] + openingIDs))
            return true
        }
    }

    @discardableResult
    public mutating func setWallThickness(_ id: UUID, to value: Double) -> Bool {
        edit { p in
            guard let i = p.walls.firstIndex(where: { $0.id == id }), value > 0 else { return false }
            p.walls[i].thickness = value
            return true
        }
    }

    // MARK: - Aberturas

    @discardableResult
    public mutating func addOpening(kind: Opening.Kind, onWall wallID: UUID, offset: Double,
                                    width: Double? = nil, id: UUID = UUID()) -> UUID? {
        let ok = edit { p in
            guard let wall = p.wall(wallID), wall.length > 0 else { return false }
            let w = min(width ?? Self.defaultWidth(for: kind), wall.length)
            let clamped = min(max(offset, w / 2), wall.length - w / 2)
            let defaults = Self.defaultSize(for: kind)
            p.openings.append(Opening(id: id, kind: kind, wallID: wallID, offset: clamped, width: w,
                                      height: defaults.height, sillHeight: defaults.sill))
            return true
        }
        return ok ? id : nil
    }

    /// Move o centro da abertura ao longo da parede (e opcionalmente a muda para outra parede).
    @discardableResult
    public mutating func moveOpening(_ id: UUID, toOffset offset: Double, onWall newWallID: UUID? = nil) -> Bool {
        edit { p in
            guard let i = p.openings.firstIndex(where: { $0.id == id }) else { return false }
            let wallID = newWallID ?? p.openings[i].wallID
            guard let wall = p.wall(wallID) else { return false }
            let w = min(p.openings[i].width, wall.length)
            p.openings[i].wallID = wallID
            p.openings[i].width = w
            p.openings[i].offset = min(max(offset, w / 2), wall.length - w / 2)
            Self.clearIssues(&p, targeting: [id])
            return true
        }
    }

    @discardableResult
    public mutating func resizeOpening(_ id: UUID, width: Double) -> Bool {
        edit { p in
            guard let i = p.openings.firstIndex(where: { $0.id == id }),
                  let wall = p.wall(p.openings[i].wallID), width > 0.05 else { return false }
            let w = min(width, wall.length)
            p.openings[i].width = w
            p.openings[i].offset = min(max(p.openings[i].offset, w / 2), wall.length - w / 2)
            Self.clearIssues(&p, targeting: [id])
            return true
        }
    }

    @discardableResult
    public mutating func setOpeningKind(_ id: UUID, to kind: Opening.Kind) -> Bool {
        edit { p in
            guard let i = p.openings.firstIndex(where: { $0.id == id }) else { return false }
            let d = Self.defaultSize(for: kind)
            p.openings[i].kind = kind
            p.openings[i].height = d.height
            p.openings[i].sillHeight = d.sill
            Self.clearIssues(&p, targeting: [id])
            return true
        }
    }

    @discardableResult
    public mutating func removeOpening(_ id: UUID) -> Bool {
        edit { p in
            guard p.openings.contains(where: { $0.id == id }) else { return false }
            p.openings.removeAll { $0.id == id }
            Self.clearIssues(&p, targeting: [id])
            return true
        }
    }

    // MARK: - Ambientes

    @discardableResult
    public mutating func renameRoom(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return edit { p in
            guard let i = p.rooms.firstIndex(where: { $0.id == id }), !trimmed.isEmpty else { return false }
            p.rooms[i].name = trimmed
            return true
        }
    }

    @discardableResult
    public mutating func moveRoomVertex(room id: UUID, index: Int, to point: Point2D) -> Bool {
        edit { p in
            guard let r = p.rooms.firstIndex(where: { $0.id == id }),
                  p.rooms[r].outline.indices.contains(index) else { return false }
            p.rooms[r].outline[index] = point
            return true
        }
    }

    /// Insere um vértice depois de `index`.
    @discardableResult
    public mutating func insertRoomVertex(room id: UUID, after index: Int, at point: Point2D) -> Bool {
        edit { p in
            guard let r = p.rooms.firstIndex(where: { $0.id == id }),
                  p.rooms[r].outline.indices.contains(index) else { return false }
            p.rooms[r].outline.insert(point, at: index + 1)
            return true
        }
    }

    /// Remove um vértice (o contorno precisa manter ao menos 3).
    @discardableResult
    public mutating func removeRoomVertex(room id: UUID, index: Int) -> Bool {
        edit { p in
            guard let r = p.rooms.firstIndex(where: { $0.id == id }),
                  p.rooms[r].outline.count > 3, p.rooms[r].outline.indices.contains(index) else { return false }
            p.rooms[r].outline.remove(at: index)
            return true
        }
    }

    /// Recalcula o contorno do ambiente a partir das paredes, se formarem um laço fechado.
    @discardableResult
    public mutating func rebuildRoomOutlineFromWalls(room id: UUID) -> Bool {
        edit { p in
            guard let r = p.rooms.firstIndex(where: { $0.id == id }),
                  let loop = FloorPlanGenerator.closedLoop(p.walls) else { return false }
            p.rooms[r].outline = loop.outline
            p.rooms[r].wallIDs = loop.wallIDs
            p.issues.removeAll { $0.kind == .openRoomOutline }
            return true
        }
    }

    @discardableResult
    public mutating func dismissIssue(_ id: UUID) -> Bool {
        edit { p in
            let before = p.issues.count
            p.issues.removeAll { $0.id == id }
            return p.issues.count != before
        }
    }

    // MARK: - Internos

    private static func defaultWidth(for kind: Opening.Kind) -> Double {
        switch kind {
        case .door: return 0.90
        case .window: return 1.20
        case .opening: return 1.00
        }
    }

    private static func defaultSize(for kind: Opening.Kind) -> (height: Double, sill: Double) {
        switch kind {
        case .door: return (2.10, 0)
        case .window: return (1.20, 0.90)
        case .opening: return (2.10, 0)
        }
    }

    private static func near(_ a: Point2D, _ b: Point2D) -> Bool {
        a.distance(to: b) <= connectionTolerance
    }

    /// Move pontas de paredes e vértices de contorno que coincidiam com `from` para `to`.
    private static func follow(_ p: inout FloorPlan, except id: UUID, from: Point2D, to: Point2D) {
        var touched = Set<UUID>()
        for i in p.walls.indices where p.walls[i].id != id {
            if near(p.walls[i].start, from) { p.walls[i].start = to; touched.insert(p.walls[i].id) }
            if near(p.walls[i].end, from) { p.walls[i].end = to; touched.insert(p.walls[i].id) }
        }
        for r in p.rooms.indices {
            for v in p.rooms[r].outline.indices where near(p.rooms[r].outline[v], from) {
                p.rooms[r].outline[v] = to
            }
        }
        clampOpenings(&p, onWalls: touched)
        clearIssues(&p, targeting: touched)
    }

    private static func clampOpenings(_ p: inout FloorPlan, onWalls ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for i in p.openings.indices where ids.contains(p.openings[i].wallID) {
            guard let wall = p.wall(p.openings[i].wallID) else { continue }
            let w = min(p.openings[i].width, wall.length)
            p.openings[i].width = w
            p.openings[i].offset = min(max(p.openings[i].offset, w / 2), max(w / 2, wall.length - w / 2))
        }
    }

    /// Um item corrigido pelo usuário deixa de estar "pendente de revisão".
    private static func clearIssues(_ p: inout FloorPlan, targeting ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        p.issues.removeAll { issue in issue.targetIDs.contains { ids.contains($0) } }
    }
}
