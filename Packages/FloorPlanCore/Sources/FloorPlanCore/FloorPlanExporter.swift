import Foundation

// MARK: - Contrato de exportação JSON (documentado em docs/SCHEMA.md)

/// Documento de exportação. Desacoplado do modelo interno: mudanças internas não quebram
/// integrações; mudanças aqui exigem incrementar `schemaVersion`.
public struct FloorPlanExport: Codable, Equatable, Sendable {
    public static let formatIdentifier = "ios-floorplan-scanner.plan"
    public static let currentSchemaVersion = 1

    public struct ProjectInfo: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var capturedAt: Date
        public var updatedAt: Date
    }

    public struct CaptureInfo: Codable, Equatable, Sendable {
        public var id: UUID
        public var capturedAt: Date
        public var device: DeviceMetadata
        public var roomPlanVersion: Int
    }

    public struct WallExport: Codable, Equatable, Sendable {
        public var id: UUID
        public var start: Point2D
        public var end: Point2D
        public var lengthMeters: Double
        public var thicknessMeters: Double
        /// `true` quando a espessura é o valor padrão estimado (sempre, na versão 1).
        public var thicknessIsEstimated: Bool
        public var heightMeters: Double?
        public var origin: String
    }

    public struct OpeningExport: Codable, Equatable, Sendable {
        public var id: UUID
        /// `door`, `window` ou `opening`.
        public var kind: String
        public var wallId: UUID
        /// Distância do início da parede (`start`) até o centro da abertura.
        public var offsetMeters: Double
        public var widthMeters: Double
        public var heightMeters: Double
        public var sillHeightMeters: Double
        public var isOpen: Bool?
        /// Centro da abertura no plano.
        public var center: Point2D
    }

    public struct RoomExport: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var areaSquareMeters: Double
        public var outline: [Point2D]
        public var wallIds: [UUID]
    }

    public struct IssueExport: Codable, Equatable, Sendable {
        public var id: UUID
        public var kind: String
        public var severity: String
        public var targetIds: [UUID]
        public var location: Point2D?
        public var value: Double?
    }

    public struct PlanExport: Codable, Equatable, Sendable {
        public var bounds: Bounds2D?
        public var walls: [WallExport]
        public var openings: [OpeningExport]
        public var rooms: [RoomExport]
        public var issues: [IssueExport]
    }

    public var format: String
    public var schemaVersion: Int
    public var exportedAt: Date
    public var project: ProjectInfo
    public var units: String
    public var coordinateSystem: CoordinateSystemInfo
    public var captures: [CaptureInfo]
    /// `true` se a planta editada difere da gerada automaticamente.
    public var hasUserEdits: Bool
    public var disclaimer: String
    public var edited: PlanExport
    public var original: PlanExport?
}

public enum FloorPlanExporter {
    public static let disclaimer =
        "Planta estimada a partir de uma captura LiDAR (Apple RoomPlan). Não é um levantamento " +
        "arquitetônico; dimensões não foram validadas por medição."

    // MARK: JSON

    public static func exportDocument(_ project: FloorPlanProject, includeOriginal: Bool = true,
                                      now: Date = Date()) -> FloorPlanExport {
        FloorPlanExport(
            format: FloorPlanExport.formatIdentifier,
            schemaVersion: FloorPlanExport.currentSchemaVersion,
            exportedAt: now,
            project: .init(id: project.id, name: project.name, capturedAt: project.createdAt,
                           updatedAt: project.updatedAt),
            units: project.units.rawValue,
            coordinateSystem: project.coordinateSystem,
            captures: project.captures.map {
                .init(id: $0.id, capturedAt: $0.capturedAt, device: $0.device,
                      roomPlanVersion: $0.snapshot.roomPlanVersion)
            },
            hasUserEdits: project.hasUserEdits,
            disclaimer: disclaimer,
            edited: planExport(project.edited),
            original: includeOriginal ? planExport(project.original) : nil)
    }

    public static func json(_ project: FloorPlanProject, includeOriginal: Bool = true,
                            now: Date = Date()) throws -> Data {
        try FloorPlanCoding.encoder().encode(exportDocument(project, includeOriginal: includeOriginal, now: now))
    }

    private static func planExport(_ plan: FloorPlan) -> FloorPlanExport.PlanExport {
        .init(
            bounds: plan.bounds,
            walls: plan.walls.map {
                .init(id: $0.id, start: $0.start, end: $0.end, lengthMeters: $0.length,
                      thicknessMeters: $0.thickness, thicknessIsEstimated: true,
                      heightMeters: $0.height, origin: $0.origin.rawValue)
            },
            openings: plan.openings.compactMap { o in
                guard let w = plan.wall(o.wallID) else { return nil }
                return .init(id: o.id, kind: o.kind.rawValue, wallId: o.wallID, offsetMeters: o.offset,
                             widthMeters: o.width, heightMeters: o.height, sillHeightMeters: o.sillHeight,
                             isOpen: o.isOpen, center: w.point(atOffset: o.offset))
            },
            rooms: plan.rooms.map {
                .init(id: $0.id, name: $0.name, areaSquareMeters: $0.area, outline: $0.outline, wallIds: $0.wallIDs)
            },
            issues: plan.issues.map {
                .init(id: $0.id, kind: $0.kind.rawValue, severity: $0.severity.rawValue,
                      targetIds: $0.targetIDs, location: $0.location, value: $0.value)
            })
    }

    // MARK: SVG

    public struct SVGOptions: Equatable, Sendable {
        public enum Source: Sendable { case edited, original }
        public var source: Source = .edited
        /// Denominador da escala impressa (50 → 1:50, 1 m = 20 mm no papel).
        public var scaleDenominator: Double = 50
        public var showDimensions = true
        public var showRoomLabels = true
        public var showIssues = false
        public var showScaleBar = true
        /// Margem ao redor da planta, em metros.
        public var margin: Double = 0.6
        public var footerNote: String? = FloorPlanExporter.disclaimer

        public init() {}
    }

    /// SVG vetorial. Unidades do `viewBox`: **centímetros**; tamanho físico (`width`/`height`) em mm
    /// segundo `scaleDenominator`. Y cresce para baixo, igual ao sistema de coordenadas da planta.
    public static func svg(_ project: FloorPlanProject, options: SVGOptions = SVGOptions()) -> String {
        let plan = options.source == .edited ? project.edited : project.original
        return svg(plan: plan, title: project.name, projectID: project.id, options: options)
    }

    public static func svg(plan: FloorPlan, title: String, projectID: UUID? = nil,
                           options: SVGOptions = SVGOptions()) -> String {
        let bounds = plan.bounds ?? Bounds2D(min: .zero, max: Point2D(x: 1, y: 1))
        let m = options.margin
        let minX = bounds.min.x - m, minY = bounds.min.y - m
        let w = bounds.width + 2 * m
        let footerFontSize = 10.0 // cm no viewBox
        let footerLines = options.footerNote.map {
            wrap($0, maxChars: max(20, Int(w * 100 / (footerFontSize * 0.52))))
        } ?? []
        let footer: Double = footerLines.isEmpty ? 0 : 0.15 + Double(footerLines.count) * footerFontSize * 1.3 / 100
        let h = bounds.height + 2 * m + footer

        func cm(_ v: Double) -> String { fmt(v * 100) }
        func pt(_ p: Point2D) -> String { "\(cm(p.x)),\(cm(p.y))" }
        func pts(_ ps: [Point2D]) -> String { ps.map(pt).joined(separator: " ") }

        let mmPerMeter = 1000 / options.scaleDenominator
        var out = ""
        out += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<svg xmlns=\"http://www.w3.org/2000/svg\" "
        out += "width=\"\(fmt(w * mmPerMeter))mm\" height=\"\(fmt(h * mmPerMeter))mm\" "
        out += "viewBox=\"\(cm(minX)) \(cm(minY)) \(cm(w)) \(cm(h))\" "
        out += "font-family=\"Helvetica, Arial, sans-serif\""
        if let projectID { out += " data-project-id=\"\(projectID.uuidString)\"" }
        out += " data-schema-version=\"\(FloorPlanExport.currentSchemaVersion)\" data-unit=\"cm\">\n"
        out += "<title>\(escape(title))</title>\n"
        out += "<desc>\(escape(disclaimer)) viewBox em centímetros; escala impressa 1:\(fmt(options.scaleDenominator, digits: 0)).</desc>\n"
        out += "<rect x=\"\(cm(minX))\" y=\"\(cm(minY))\" width=\"\(cm(w))\" height=\"\(cm(h))\" fill=\"#ffffff\"/>\n"

        // Ambientes.
        out += "<g id=\"rooms\">\n"
        for r in plan.rooms where r.outline.count >= 3 {
            out += "<polygon data-room-id=\"\(r.id.uuidString)\" points=\"\(pts(r.outline))\" fill=\"#eef2f6\" stroke=\"none\"/>\n"
        }
        out += "</g>\n"

        // Máscara: abre vãos nas paredes onde há porta/janela/abertura.
        let gapPolys: [(Opening, [Point2D])] = plan.openings.compactMap { o in
            guard let wall = plan.wall(o.wallID) else { return nil }
            return (o, rect(center: wall.point(atOffset: o.offset), along: wall.direction,
                            length: o.width, across: wall.thickness + 0.04))
        }
        out += "<defs><mask id=\"wall-mask\" maskUnits=\"userSpaceOnUse\" "
        out += "x=\"\(cm(minX))\" y=\"\(cm(minY))\" width=\"\(cm(w))\" height=\"\(cm(h))\">\n"
        out += "<rect x=\"\(cm(minX))\" y=\"\(cm(minY))\" width=\"\(cm(w))\" height=\"\(cm(h))\" fill=\"white\"/>\n"
        for (_, poly) in gapPolys { out += "<polygon points=\"\(pts(poly))\" fill=\"black\"/>\n" }
        out += "</mask></defs>\n"

        // Paredes (linhas com espessura; cantos quadrados fecham as quinas).
        out += "<g id=\"walls\" mask=\"url(#wall-mask)\" stroke=\"#222222\" stroke-linecap=\"square\" fill=\"none\">\n"
        for wl in plan.walls {
            out += "<line data-wall-id=\"\(wl.id.uuidString)\" x1=\"\(cm(wl.start.x))\" y1=\"\(cm(wl.start.y))\" "
            out += "x2=\"\(cm(wl.end.x))\" y2=\"\(cm(wl.end.y))\" stroke-width=\"\(cm(wl.thickness))\"/>\n"
        }
        out += "</g>\n"

        // Portas, janelas, aberturas.
        out += "<g id=\"openings\" fill=\"none\" stroke=\"#222222\" stroke-width=\"1.5\">\n"
        for o in plan.openings {
            guard let wall = plan.wall(o.wallID) else { continue }
            let c = wall.point(atOffset: o.offset)
            let d = wall.direction, n = d.perpendicular
            let a = c - d * (o.width / 2), b = c + d * (o.width / 2)
            out += "<g data-opening-id=\"\(o.id.uuidString)\" data-kind=\"\(o.kind.rawValue)\">\n"
            switch o.kind {
            case .door:
                // Esquema de porta: folha a 90° e arco de giro, abrindo para o lado do ambiente mais
                // próximo (o sentido real de abertura não é capturado pelo RoomPlan).
                var side = n
                if let room = plan.rooms.min(by: { centroid($0.outline).distance(to: c) < centroid($1.outline).distance(to: c) }),
                   (centroid(room.outline) - c).dot(n) < 0 {
                    side = n * -1
                }
                let leafEnd = a + side * o.width
                let sweep = side.cross(d) > 0 ? 1 : 0
                out += "<line x1=\"\(cm(a.x))\" y1=\"\(cm(a.y))\" x2=\"\(cm(leafEnd.x))\" y2=\"\(cm(leafEnd.y))\"/>\n"
                out += "<path d=\"M \(pt(leafEnd)) A \(cm(o.width)) \(cm(o.width)) 0 0 \(sweep) \(pt(b))\" stroke-width=\"0.8\"/>\n"
            case .window:
                let inner = wall.thickness / 4
                for s in [-1.0, 1.0] {
                    let p1 = a + n * (inner * s), p2 = b + n * (inner * s)
                    out += "<line x1=\"\(cm(p1.x))\" y1=\"\(cm(p1.y))\" x2=\"\(cm(p2.x))\" y2=\"\(cm(p2.y))\" stroke-width=\"1\"/>\n"
                }
                for e in [a, b] {
                    let p1 = e + n * (wall.thickness / 2), p2 = e - n * (wall.thickness / 2)
                    out += "<line x1=\"\(cm(p1.x))\" y1=\"\(cm(p1.y))\" x2=\"\(cm(p2.x))\" y2=\"\(cm(p2.y))\" stroke-width=\"1\"/>\n"
                }
            case .opening:
                for e in [a, b] {
                    let p1 = e + n * (wall.thickness / 2), p2 = e - n * (wall.thickness / 2)
                    out += "<line x1=\"\(cm(p1.x))\" y1=\"\(cm(p1.y))\" x2=\"\(cm(p2.x))\" y2=\"\(cm(p2.y))\" stroke-width=\"1\" stroke-dasharray=\"4 3\"/>\n"
                }
            }
            out += "</g>\n"
        }
        out += "</g>\n"

        // Cotas.
        if options.showDimensions {
            out += "<g id=\"dimensions\" font-size=\"12\" fill=\"#444444\" text-anchor=\"middle\">\n"
            for wl in plan.walls where wl.length >= 0.4 {
                let n = wl.direction.perpendicular
                let at = wl.midpoint + n * (wl.thickness / 2 + 0.14)
                var angle = atan2(wl.direction.y, wl.direction.x) * 180 / .pi
                if angle > 90 { angle -= 180 } else if angle < -90 { angle += 180 }
                out += "<text transform=\"translate(\(cm(at.x)) \(cm(at.y))) rotate(\(fmt(angle, digits: 1)))\" "
                out += "dominant-baseline=\"middle\">\(fmt(wl.length, digits: 2)) m</text>\n"
            }
            out += "</g>\n"
        }

        // Nomes e áreas.
        if options.showRoomLabels {
            out += "<g id=\"labels\" text-anchor=\"middle\" fill=\"#111111\">\n"
            for r in plan.rooms where r.outline.count >= 3 {
                let c = centroid(r.outline)
                out += "<text x=\"\(cm(c.x))\" y=\"\(cm(c.y))\" font-size=\"22\" font-weight=\"bold\">\(escape(r.name))</text>\n"
                out += "<text x=\"\(cm(c.x))\" y=\"\(fmt(c.y * 100 + 24))\" font-size=\"16\">\(fmt(r.area, digits: 2)) m²</text>\n"
            }
            out += "</g>\n"
        }

        // Pontos de revisão.
        if options.showIssues {
            out += "<g id=\"issues\" fill=\"none\" stroke=\"#d9822b\" stroke-width=\"2\">\n"
            for i in plan.issues {
                guard let p = i.location else { continue }
                out += "<circle data-issue=\"\(i.kind.rawValue)\" cx=\"\(cm(p.x))\" cy=\"\(cm(p.y))\" r=\"12\"/>\n"
            }
            out += "</g>\n"
        }

        // Barra de escala (1 m) e nota.
        if options.showScaleBar {
            let x0 = bounds.min.x, y0 = bounds.max.y + m * 0.6
            out += "<g id=\"scale\" stroke=\"#222222\" stroke-width=\"2\" fill=\"#222222\" font-size=\"12\">\n"
            out += "<line x1=\"\(cm(x0))\" y1=\"\(cm(y0))\" x2=\"\(cm(x0 + 1))\" y2=\"\(cm(y0))\"/>\n"
            out += "<text x=\"\(cm(x0 + 1) )\" y=\"\(fmt(y0 * 100 + 4))\" stroke=\"none\" dx=\"6\">1 m</text>\n"
            out += "</g>\n"
        }
        if !footerLines.isEmpty {
            let top = minY + h - footer + 0.1
            for (i, line) in footerLines.enumerated() {
                let y = top * 100 + footerFontSize * 1.3 * Double(i + 1)
                out += "<text x=\"\(cm(minX + 0.1))\" y=\"\(fmt(y))\" font-size=\"\(fmt(footerFontSize, digits: 0))\" fill=\"#666666\">\(escape(line))</text>\n"
            }
        }
        out += "</svg>\n"
        return out
    }

    // MARK: - Helpers

    private static func wrap(_ text: String, maxChars: Int) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            if line.isEmpty { line = String(word) }
            else if line.count + 1 + word.count <= maxChars { line += " " + word }
            else { lines.append(line); line = String(word) }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    private static func rect(center c: Point2D, along d: Point2D, length: Double, across: Double) -> [Point2D] {
        let n = d.perpendicular
        let hl = length / 2, ha = across / 2
        return [c - d * hl - n * ha, c + d * hl - n * ha, c + d * hl + n * ha, c - d * hl + n * ha]
    }

    private static func centroid(_ poly: [Point2D]) -> Point2D {
        let a = Geometry.signedArea(poly)
        guard abs(a) > 1e-9 else { return Bounds2D(points: poly)?.center ?? .zero }
        var cx = 0.0, cy = 0.0
        for i in poly.indices {
            let p = poly[i], q = poly[(i + 1) % poly.count]
            let f = p.x * q.y - q.x * p.y
            cx += (p.x + q.x) * f
            cy += (p.y + q.y) * f
        }
        return Point2D(x: cx / (6 * a), y: cy / (6 * a))
    }

    /// Formato numérico independente de locale.
    private static func fmt(_ v: Double, digits: Int = 1) -> String {
        var s = String(format: "%.\(digits)f", v)
        if s == "-0.0" || s == "-0" || s == "-0.00" { s = String(s.dropFirst()) }
        return s
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
