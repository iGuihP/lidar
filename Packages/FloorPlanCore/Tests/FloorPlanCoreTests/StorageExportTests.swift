import XCTest
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import FloorPlanCore

final class StorageTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fp-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSaveLoadRoundTripPreservesEverything() throws {
        let storage = FloorPlanStorage(rootURL: root)
        var project = Fixtures.project()
        var editor = FloorPlanEditor(original: project.original)
        editor.renameRoom(editor.plan.rooms[0].id, to: "Sala 1")
        project.edited = editor.plan
        let raw = Data("{\"roomplan\":true}".utf8)

        try storage.save(project, rawFiles: ["capture.roomplan.json": raw])
        let loaded = try storage.load(id: project.id)
        XCTAssertEqual(loaded, project)
        XCTAssertTrue(loaded.hasUserEdits)
        XCTAssertEqual(try storage.rawFile(projectID: project.id, name: "capture.roomplan.json"), raw)
    }

    func testListSortsByUpdatedAtAndDeleteRemovesFolder() throws {
        let storage = FloorPlanStorage(rootURL: root)
        XCTAssertEqual(try storage.list().projects, [])
        var a = Fixtures.project(); a.name = "A"; a.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var b = Fixtures.project(); b.name = "B"; b.updatedAt = Date(timeIntervalSince1970: 1_700_005_000)
        try storage.save(a)
        try storage.save(b)
        XCTAssertEqual(try storage.list().projects.map(\.name), ["B", "A"])

        try storage.delete(id: a.id)
        XCTAssertEqual(try storage.list().projects.map(\.name), ["B"])
        XCTAssertThrowsError(try storage.load(id: a.id)) { XCTAssertEqual($0 as? FloorPlanStorageError, .notFound(a.id)) }
        XCTAssertThrowsError(try storage.delete(id: a.id))
    }

    func testNewerSchemaIsRejectedNotOverwritten() throws {
        let storage = FloorPlanStorage(rootURL: root)
        let project = Fixtures.project()
        try storage.save(project)
        let file = storage.folder(for: project.id).appendingPathComponent("project.json")
        var text = try String(contentsOf: file, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
        try text.write(to: file, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try storage.load(id: project.id)) {
            XCTAssertEqual($0 as? FloorPlanStorageError, .unsupportedSchema(found: 99, supported: 1))
        }
        let listing = try storage.list()
        XCTAssertTrue(listing.projects.isEmpty)
        XCTAssertEqual(listing.unreadable.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "arquivo não pode ser apagado")
    }

    func testCorruptedProjectIsReportedAndOthersStillListed() throws {
        let storage = FloorPlanStorage(rootURL: root)
        let good = Fixtures.project()
        try storage.save(good)
        let badDir = root.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: badDir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: badDir.appendingPathComponent("project.json"))

        let listing = try storage.list()
        XCTAssertEqual(listing.projects.map(\.id), [good.id])
        XCTAssertEqual(listing.unreadable.map(\.folderName), ["broken"])
    }

    func testRawFileNamesCannotEscapeProjectFolder() {
        let storage = FloorPlanStorage(rootURL: root)
        XCTAssertThrowsError(try storage.save(Fixtures.project(), rawFiles: ["../evil.json": Data()]))
    }
}

final class ExporterTests: XCTestCase {
    func testJSONExportContract() throws {
        var project = Fixtures.project()
        var editor = FloorPlanEditor(original: project.original)
        editor.renameRoom(editor.plan.rooms[0].id, to: "Sala <1> & \"2\"")
        project.edited = editor.plan

        let data = try FloorPlanExporter.json(project, now: Date(timeIntervalSince1970: 1_700_000_200))
        let doc = try FloorPlanCoding.decoder().decode(FloorPlanExport.self, from: data)
        XCTAssertEqual(doc.format, "ios-floorplan-scanner.plan")
        XCTAssertEqual(doc.schemaVersion, 1)
        XCTAssertEqual(doc.units, "meters")
        XCTAssertTrue(doc.hasUserEdits)
        XCTAssertEqual(doc.edited.rooms[0].name, "Sala <1> & \"2\"")
        XCTAssertEqual(doc.original?.rooms[0].name, "Sala")
        XCTAssertEqual(doc.edited.rooms[0].areaSquareMeters, 12, accuracy: 1e-6)
        XCTAssertEqual(doc.edited.walls.count, 4)
        XCTAssertEqual(Set(doc.edited.openings.map(\.kind)), ["door", "window"])
        XCTAssertTrue(doc.edited.walls.allSatisfy { $0.thicknessIsEstimated })
        XCTAssertEqual(doc.captures[0].device.deviceModel, "test")

        // Chaves de topo estáveis (contrato).
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["format", "schemaVersion", "exportedAt", "project", "units", "coordinateSystem",
                    "captures", "hasUserEdits", "disclaimer", "edited", "original"] {
            XCTAssertNotNil(obj[key], "chave \(key) ausente")
        }
        let without = try FloorPlanCoding.decoder().decode(
            FloorPlanExport.self, from: FloorPlanExporter.json(project, includeOriginal: false))
        XCTAssertNil(without.original)
    }

    func testSVGIsWellFormedAndContainsGeometry() throws {
        var project = Fixtures.project()
        var editor = FloorPlanEditor(original: project.original)
        editor.renameRoom(editor.plan.rooms[0].id, to: "Sala <1> & \"2\"")
        project.edited = editor.plan

        var options = FloorPlanExporter.SVGOptions()
        options.showIssues = true
        let svg = FloorPlanExporter.svg(project, options: options)

        let parser = XMLParser(data: Data(svg.utf8))
        XCTAssertTrue(parser.parse(), "SVG inválido: \(String(describing: parser.parserError)) \n\(svg)")
        XCTAssertEqual(svg.components(separatedBy: "<line data-wall-id").count - 1, 4)
        XCTAssertTrue(svg.contains("data-kind=\"door\""))
        XCTAssertTrue(svg.contains("data-kind=\"window\""))
        XCTAssertTrue(svg.contains("Sala &lt;1&gt; &amp; &quot;2&quot;"))
        XCTAssertTrue(svg.contains("12.00 m²"))
        XCTAssertTrue(svg.contains("mm\""))
        for bad in ["=\"nan", "=\"-nan", "=\"inf", "=\"-inf", " nan", ",nan", " inf", ",inf"] {
            XCTAssertFalse(svg.contains(bad), "valor numérico inválido (\(bad)) no SVG")
        }

        let original = FloorPlanExporter.svg(project, options: {
            var o = FloorPlanExporter.SVGOptions(); o.source = .original; return o
        }())
        XCTAssertTrue(original.contains("<text x="))
        XCTAssertFalse(original.contains("Sala &lt;1&gt;"))
    }

    func testSVGScaleMatchesPhysicalSize() throws {
        let plan = FloorPlan(walls: [Wall(start: .zero, end: Point2D(x: 5, y: 0), thickness: 0.1)])
        var o = FloorPlanExporter.SVGOptions()
        o.margin = 0; o.footerNote = nil; o.scaleDenominator = 100
        let svg = FloorPlanExporter.svg(plan: plan, title: "t", options: o)
        // Parede de 5 m + meia espessura = bounds de altura 0,1 m; escala 1:100 => 5 m = 50 mm.
        XCTAssertTrue(svg.contains("width=\"50.0mm\""), svg)
        XCTAssertTrue(svg.contains("viewBox=\"0.0 -5.0 500.0 10.0\""), svg)
    }

    /// Com `FP_SVG_OUT=/caminho/arquivo.svg` grava o SVG da fixture para inspeção visual.
    func testWriteSampleSVGWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["FP_SVG_OUT"] else { return }
        var o = FloorPlanExporter.SVGOptions()
        o.showIssues = true
        try FloorPlanExporter.svg(Fixtures.project(), options: o).write(toFile: path, atomically: true, encoding: .utf8)
    }

    func testSVGOfEmptyPlanDoesNotCrash() {
        let svg = FloorPlanExporter.svg(plan: FloorPlan(), title: "vazio")
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
    }
}
