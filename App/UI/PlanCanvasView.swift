import SwiftUI
import FloorPlanCore

/// Conversão entre metros da planta e pontos da tela (y cresce para baixo nos dois).
struct PlanViewport: Equatable {
    var scale: Double = 50 // pontos por metro
    var offset: CGPoint = .zero // onde fica o ponto (0, 0) da planta na tela

    func toScreen(_ p: Point2D) -> CGPoint {
        CGPoint(x: offset.x + p.x * scale, y: offset.y + p.y * scale)
    }

    func toPlan(_ s: CGPoint) -> Point2D {
        Point2D(x: (Double(s.x) - Double(offset.x)) / scale, y: (Double(s.y) - Double(offset.y)) / scale)
    }

    static let scaleRange: ClosedRange<Double> = 8...800

    /// Enquadra `bounds` na área de tamanho `size`.
    static func fit(_ bounds: Bounds2D?, in size: CGSize, padding: Double = 48) -> PlanViewport {
        guard let b = bounds, size.width > 0, size.height > 0 else {
            return PlanViewport(scale: 50, offset: CGPoint(x: size.width / 2, y: size.height / 2))
        }
        let w = max(b.width, 0.5), h = max(b.height, 0.5)
        let s = min((Double(size.width) - 2 * padding) / w, (Double(size.height) - 2 * padding) / h)
        let scale = min(max(s, scaleRange.lowerBound), scaleRange.upperBound)
        let c = b.center
        return PlanViewport(scale: scale,
                            offset: CGPoint(x: Double(size.width) / 2 - c.x * scale,
                                            y: Double(size.height) / 2 - c.y * scale))
    }
}

/// Planta 2D vista de cima: zoom (pinça), deslocamento (arrasto), seleção (toque) e, no modo
/// de edição, arrasto de paredes, pontas, aberturas e vértices do ambiente selecionado.
struct PlanCanvasView: View {
    let model: ProjectEditorModel
    /// Planta exibida (editada ou original).
    let plan: FloorPlan
    /// Permite selecionar elementos.
    let interactive: Bool
    /// Permite alterar a geometria.
    let isEditing: Bool
    let showIssues: Bool
    /// Incrementado pelo pai para recentralizar.
    let fitRequest: Int

    @State private var viewport = PlanViewport()
    @State private var didInitialFit = false
    @State private var magnifyBase: PlanViewport?
    @State private var drag: DragMode?
    @State private var preview: (start: Point2D, end: Point2D)?

    private enum DragMode {
        case pan(PlanViewport)
        case moveWall(UUID, last: Point2D)
        case moveEndpoint(UUID, isEnd: Bool)
        case moveOpening(UUID)
        case moveVertex(UUID, Int)
        case addWall(Point2D)
    }

    private enum Hit {
        case endpoint(UUID, isEnd: Bool)
        case roomVertex(UUID, Int)
        case roomEdgeMidpoint(UUID, after: Int)
        case opening(UUID)
        case wall(UUID)
        case room(UUID)
    }

    var body: some View {
        GeometryReader { geo in
            let plan = self.plan
            let selection = model.selection
            let flagged = Set(plan.issues.flatMap(\.targetIDs))
            let viewport = self.viewport
            let preview = self.preview
            Canvas { ctx, size in
                draw(ctx, plan: plan, selection: selection, flagged: flagged, viewport: viewport, preview: preview)
            }
            .background(Color(.systemBackground))
            .contentShape(Rectangle())
            .gesture(dragGesture())
            .simultaneousGesture(magnifyGesture())
            .simultaneousGesture(SpatialTapGesture().onEnded { handleTap(at: $0.location) })
            .onAppear { fitInitially(geo.size) }
            .onChange(of: geo.size) { _, newSize in
                if !didInitialFit { fitInitially(newSize) }
            }
            .onChange(of: fitRequest) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) { fit(geo.size) }
            }
        }
    }

    private func fitInitially(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        fit(size)
        didInitialFit = true
    }

    private func fit(_ size: CGSize) {
        viewport = PlanViewport.fit(plan.bounds, in: size)
    }

    // MARK: - Desenho

    private func draw(_ context: GraphicsContext, plan: FloorPlan, selection: PlanSelection?,
                      flagged: Set<UUID>, viewport vp: PlanViewport,
                      preview: (start: Point2D, end: Point2D)?) {
        var ctx = context
        let s = vp.scale

        // Ambientes.
        for r in plan.rooms where r.outline.count >= 3 {
            var path = Path()
            path.addLines(r.outline.map(vp.toScreen))
            path.closeSubpath()
            let selected = selection == .room(r.id)
            ctx.fill(path, with: .color(selected ? Color.blue.opacity(0.22) : Color(.secondarySystemBackground)))
        }

        // Paredes, com vãos recortados onde há portas/janelas/aberturas.
        ctx.drawLayer { layer in
            for w in plan.walls {
                var p = Path()
                p.move(to: vp.toScreen(w.start))
                p.addLine(to: vp.toScreen(w.end))
                let color: Color
                if selection == .wall(w.id) { color = .blue }
                else if showIssues && flagged.contains(w.id) { color = .orange }
                else { color = Color(.label) }
                layer.stroke(p, with: .color(color),
                             style: StrokeStyle(lineWidth: max(2, w.thickness * s), lineCap: .square))
            }
            layer.blendMode = .clear
            for o in plan.openings {
                guard let w = plan.wall(o.wallID) else { continue }
                var p = Path()
                p.move(to: vp.toScreen(w.point(atOffset: o.offset - o.width / 2)))
                p.addLine(to: vp.toScreen(w.point(atOffset: o.offset + o.width / 2)))
                layer.stroke(p, with: .color(.black),
                             style: StrokeStyle(lineWidth: max(4, (w.thickness + 0.04) * s), lineCap: .butt))
            }
        }

        // Símbolos de portas, janelas e aberturas.
        for o in plan.openings {
            guard let w = plan.wall(o.wallID) else { continue }
            let d = w.direction, n = d.perpendicular
            let a = w.point(atOffset: o.offset - o.width / 2)
            let b = w.point(atOffset: o.offset + o.width / 2)
            let selected = selection == .opening(o.id)
            let color: Color = selected ? .blue : Color(.label)
            let lineWidth: CGFloat = selected ? 2.5 : 1.2

            if selected {
                var halo = Path()
                halo.move(to: vp.toScreen(a))
                halo.addLine(to: vp.toScreen(b))
                ctx.stroke(halo, with: .color(Color.blue.opacity(0.25)),
                           style: StrokeStyle(lineWidth: max(10, (w.thickness + 0.1) * s), lineCap: .butt))
            }

            var p = Path()
            switch o.kind {
            case .door:
                let side = plan.swingNormal(for: o) ?? n
                p.move(to: vp.toScreen(a))
                p.addLine(to: vp.toScreen(a + side * o.width))
                // Arco de giro como polilinha (de a + side*w até b).
                for i in 0...16 {
                    let t = Double(i) / 16 * .pi / 2
                    let pt = a + side * (cos(t) * o.width) + d * (sin(t) * o.width)
                    if i == 0 { p.move(to: vp.toScreen(pt)) } else { p.addLine(to: vp.toScreen(pt)) }
                }
            case .window:
                for k in [-1.0, 1.0] {
                    p.move(to: vp.toScreen(a + n * (w.thickness / 4 * k)))
                    p.addLine(to: vp.toScreen(b + n * (w.thickness / 4 * k)))
                }
                for e in [a, b] {
                    p.move(to: vp.toScreen(e + n * (w.thickness / 2)))
                    p.addLine(to: vp.toScreen(e - n * (w.thickness / 2)))
                }
            case .opening:
                for e in [a, b] {
                    p.move(to: vp.toScreen(e + n * (w.thickness / 2)))
                    p.addLine(to: vp.toScreen(e - n * (w.thickness / 2)))
                }
            }
            ctx.stroke(p, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, dash: o.kind == .opening ? [4, 3] : []))
        }

        // Cotas.
        if s >= 25 {
            for w in plan.walls where w.length >= 0.6 {
                let at = vp.toScreen(w.midpoint + w.direction.perpendicular * (w.thickness / 2 + 0.18))
                var angle = atan2(w.direction.y, w.direction.x)
                if angle > .pi / 2 { angle -= .pi } else if angle < -.pi / 2 { angle += .pi }
                var c = ctx
                c.translateBy(x: at.x, y: at.y)
                c.rotate(by: .radians(angle))
                c.draw(Text(w.length.metersText).font(.system(size: 10)).foregroundColor(.secondary), at: .zero)
            }
        }

        // Nomes e áreas.
        for r in plan.rooms where r.outline.count >= 3 {
            let c = vp.toScreen(r.centroid)
            ctx.draw(Text(r.name).font(.system(size: 15, weight: .semibold)), at: c)
            ctx.draw(Text(r.area.areaText).font(.system(size: 12)).foregroundColor(.secondary),
                     at: CGPoint(x: c.x, y: c.y + 18))
        }

        // Pontos de revisão.
        if showIssues {
            for issue in plan.issues {
                guard let loc = issue.location else { continue }
                let c = vp.toScreen(loc)
                let circle = Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18))
                ctx.fill(circle, with: .color(.orange))
                ctx.draw(Text("!").font(.system(size: 12, weight: .bold)).foregroundColor(.white), at: c)
            }
        }

        // Alças de edição.
        if isEditing {
            switch selection {
            case .wall(let id):
                if let w = plan.wall(id) { for e in [w.start, w.end] { handle(&ctx, at: vp.toScreen(e), filled: false) } }
            case .room(let id), .roomVertex(let id, _):
                if let r = plan.rooms.first(where: { $0.id == id }) {
                    for (i, v) in r.outline.enumerated() {
                        var filled = false
                        if case .roomVertex(_, let sel) = selection, sel == i { filled = true }
                        handle(&ctx, at: vp.toScreen(v), filled: filled, square: true)
                        let next = r.outline[(i + 1) % r.outline.count]
                        let mid = vp.toScreen(Point2D(x: (v.x + next.x) / 2, y: (v.y + next.y) / 2))
                        let plus = Path(ellipseIn: CGRect(x: mid.x - 5, y: mid.y - 5, width: 10, height: 10))
                        ctx.stroke(plus, with: .color(.blue.opacity(0.7)), lineWidth: 1.5)
                    }
                }
            default: break
            }
        }

        // Parede em criação.
        if let pv = preview {
            var p = Path()
            p.move(to: vp.toScreen(pv.start))
            p.addLine(to: vp.toScreen(pv.end))
            ctx.stroke(p, with: .color(.blue), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 4]))
            let mid = vp.toScreen(Point2D(x: (pv.start.x + pv.end.x) / 2, y: (pv.start.y + pv.end.y) / 2))
            ctx.draw(Text(pv.start.distance(to: pv.end).metersText).font(.system(size: 12, weight: .semibold))
                .foregroundColor(.blue), at: CGPoint(x: mid.x, y: mid.y - 14))
        }
    }

    private func handle(_ ctx: inout GraphicsContext, at p: CGPoint, filled: Bool, square: Bool = false) {
        let rect = CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)
        let path = square ? Path(rect) : Path(ellipseIn: rect)
        ctx.fill(path, with: .color(filled ? .blue : Color(.systemBackground)))
        ctx.stroke(path, with: .color(.blue), lineWidth: 2)
    }

    // MARK: - Seleção

    private func hit(at point: CGPoint) -> Hit? {
        let pt = viewport.toPlan(point)
        let s = viewport.scale
        let handleRadius = 18 / s
        let selection = model.selection

        if isEditing {
            if case .wall(let id)? = selection, let w = plan.wall(id) {
                if pt.distance(to: w.start) <= handleRadius { return .endpoint(id, isEnd: false) }
                if pt.distance(to: w.end) <= handleRadius { return .endpoint(id, isEnd: true) }
            }
            var roomID: UUID?
            switch selection {
            case .room(let id)?, .roomVertex(let id, _)?: roomID = id
            default: break
            }
            if let id = roomID, let r = plan.rooms.first(where: { $0.id == id }) {
                for (i, v) in r.outline.enumerated() where pt.distance(to: v) <= handleRadius {
                    return .roomVertex(id, i)
                }
                for (i, v) in r.outline.enumerated() {
                    let next = r.outline[(i + 1) % r.outline.count]
                    let mid = Point2D(x: (v.x + next.x) / 2, y: (v.y + next.y) / 2)
                    if pt.distance(to: mid) <= handleRadius { return .roomEdgeMidpoint(id, after: i) }
                }
            }
        }

        let tolerance = 14 / s
        var bestOpening: (UUID, Double)?
        for o in plan.openings {
            guard let w = plan.wall(o.wallID) else { continue }
            let a = w.point(atOffset: o.offset - o.width / 2), b = w.point(atOffset: o.offset + o.width / 2)
            let d = Geometry.distance(from: pt, toSegment: a, b).distance
            if d <= max(w.thickness / 2, tolerance), bestOpening == nil || d < bestOpening!.1 { bestOpening = (o.id, d) }
        }
        if let o = bestOpening { return .opening(o.0) }

        var bestWall: (UUID, Double)?
        for w in plan.walls {
            let d = Geometry.distance(from: pt, toSegment: w.start, w.end).distance
            if d <= max(w.thickness / 2, tolerance), bestWall == nil || d < bestWall!.1 { bestWall = (w.id, d) }
        }
        if let w = bestWall { return .wall(w.0) }

        if let r = plan.rooms.first(where: { Geometry.contains($0.outline, pt) }) { return .room(r.id) }
        return nil
    }

    private func handleTap(at point: CGPoint) {
        guard interactive, !(isEditing && model.tool == .addWall) else { return }
        switch hit(at: point) {
        case .endpoint(let id, _)?: model.selection = .wall(id)
        case .roomVertex(let id, let i)?: model.selection = .roomVertex(id, i)
        case .roomEdgeMidpoint(let id, _)?: model.selection = .room(id)
        case .opening(let id)?: model.selection = .opening(id)
        case .wall(let id)?: model.selection = .wall(id)
        case .room(let id)?: model.selection = .room(id)
        case nil: model.selection = nil
        }
    }

    // MARK: - Gestos

    private func magnifyGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if magnifyBase == nil { magnifyBase = viewport }
                guard let base = magnifyBase else { return }
                let newScale = min(max(base.scale * Double(value.magnification), PlanViewport.scaleRange.lowerBound),
                                   PlanViewport.scaleRange.upperBound)
                let anchor = value.startLocation
                let planPoint = base.toPlan(anchor)
                viewport.scale = newScale
                viewport.offset = CGPoint(x: Double(anchor.x) - planPoint.x * newScale,
                                          y: Double(anchor.y) - planPoint.y * newScale)
            }
            .onEnded { _ in magnifyBase = nil }
    }

    private func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if drag == nil { drag = beginDrag(at: value.startLocation) }
                updateDrag(value)
            }
            .onEnded { value in
                endDrag(value)
            }
    }

    private func beginDrag(at start: CGPoint) -> DragMode {
        guard isEditing else { return .pan(viewport) }
        let selection = model.selection
        if model.tool == .addWall { return .addWall(snapped(viewport.toPlan(start), anchor: nil, excluding: nil)) }

        switch hit(at: start) {
        case .endpoint(let id, let isEnd)?:
            model.beginGesture()
            return .moveEndpoint(id, isEnd: isEnd)
        case .roomVertex(let id, let i)?:
            model.selection = .roomVertex(id, i)
            model.beginGesture()
            return .moveVertex(id, i)
        case .roomEdgeMidpoint(let id, let i)?:
            guard let r = plan.rooms.first(where: { $0.id == id }) else { return .pan(viewport) }
            let a = r.outline[i], b = r.outline[(i + 1) % r.outline.count]
            model.beginGesture()
            model.gestureEdit { $0.insertRoomVertex(room: id, after: i, at: Point2D(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)) }
            model.selection = .roomVertex(id, i + 1)
            return .moveVertex(id, i + 1)
        case .opening(let id)? where selection == .opening(id):
            model.beginGesture()
            return .moveOpening(id)
        case .wall(let id)? where selection == .wall(id):
            model.beginGesture()
            return .moveWall(id, last: viewport.toPlan(start))
        default:
            return .pan(viewport)
        }
    }

    private func updateDrag(_ value: DragGesture.Value) {
        let current = viewport.toPlan(value.location)
        switch drag {
        case .pan(let base)?:
            viewport.offset = CGPoint(x: base.offset.x + value.translation.width,
                                      y: base.offset.y + value.translation.height)
        case .moveWall(let id, let last)?:
            model.gestureEdit { $0.moveWall(id, by: current - last) }
            drag = .moveWall(id, last: current)
        case .moveEndpoint(let id, let isEnd)?:
            guard let w = plan.wall(id) else { return }
            let anchor = isEnd ? w.start : w.end
            let target = snapped(current, anchor: anchor, excluding: id)
            model.gestureEdit { $0.moveEndpoint(ofWall: id, isEnd: isEnd, to: target) }
        case .moveOpening(let id)?:
            guard let o = plan.openings.first(where: { $0.id == id }), let w = plan.wall(o.wallID) else { return }
            let offset = (current - w.start).dot(w.direction)
            model.gestureEdit { $0.moveOpening(id, toOffset: offset) }
        case .moveVertex(let id, let i)?:
            model.gestureEdit { $0.moveRoomVertex(room: id, index: i, to: current) }
        case .addWall(let start)?:
            preview = (start, snapped(current, anchor: start, excluding: nil))
        case nil:
            break
        }
    }

    private func endDrag(_ value: DragGesture.Value) {
        defer { drag = nil }
        switch drag {
        case .addWall(let start)?:
            let end = snapped(viewport.toPlan(value.location), anchor: start, excluding: nil)
            preview = nil
            var created: UUID?
            model.edit { created = $0.addWall(from: start, to: end) }
            if let created { model.selection = .wall(created) }
            model.tool = .select
        case .moveWall?, .moveEndpoint?, .moveOpening?, .moveVertex?:
            model.endGesture()
        default:
            break
        }
    }

    /// Imã para pontas de outras paredes (14 pt) e alinhamento horizontal/vertical com `anchor` (8 pt).
    private func snapped(_ p: Point2D, anchor: Point2D?, excluding id: UUID?) -> Point2D {
        let s = viewport.scale
        var best: (Point2D, Double)?
        for w in plan.walls where w.id != id {
            for e in [w.start, w.end] {
                let d = p.distance(to: e)
                if d <= 14 / s, best == nil || d < best!.1 { best = (e, d) }
            }
        }
        if let best { return best.0 }
        guard let anchor else { return p }
        var q = p
        if abs(p.x - anchor.x) <= 8 / s { q.x = anchor.x }
        if abs(p.y - anchor.y) <= 8 / s { q.y = anchor.y }
        return q
    }
}
