import Foundation

public enum FloorPlanCoding {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

public enum FloorPlanStorageError: Error, Equatable {
    case notFound(UUID)
    /// O projeto foi gravado por uma versão mais nova do app.
    case unsupportedSchema(found: Int, supported: Int)
    case unreadable(String)
}

public struct UnreadableProject: Equatable, Sendable {
    public var folderName: String
    public var reason: String
}

public struct ProjectListing: Equatable, Sendable {
    public var projects: [ProjectSummary]
    /// Pastas que existem em disco mas não puderam ser lidas. Nunca são apagadas automaticamente.
    public var unreadable: [UnreadableProject]
}

/// Persistência local: uma pasta por projeto.
///
/// ```
/// <root>/<project-id>/project.json          (FloorPlanProject)
/// <root>/<project-id>/<capture>.roomplan.json (JSON bruto Codable do CapturedRoom, opcional)
/// ```
/// Gravações são atômicas; o JSON bruto é escrito antes do `project.json`, então um projeto
/// nunca referencia um arquivo que não existe.
public final class FloorPlanStorage: @unchecked Sendable {
    public static let projectFileName = "project.json"

    public let rootURL: URL
    private let fileManager = FileManager.default

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// `Documents/FloorPlans` do app.
    public static func defaultRoot() throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return docs.appendingPathComponent("FloorPlans", isDirectory: true)
    }

    public func folder(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Grava o projeto. `rawFiles` mapeia nome de arquivo → bytes (ex.: JSON bruto do RoomPlan).
    public func save(_ project: FloorPlanProject, rawFiles: [String: Data] = [:]) throws {
        let dir = folder(for: project.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, data) in rawFiles {
            guard name == (name as NSString).lastPathComponent, !name.isEmpty else {
                throw FloorPlanStorageError.unreadable("Nome de arquivo inválido: \(name)")
            }
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
        let data = try FloorPlanCoding.encoder().encode(project)
        try data.write(to: dir.appendingPathComponent(Self.projectFileName), options: .atomic)
    }

    public func load(id: UUID) throws -> FloorPlanProject {
        let url = folder(for: id).appendingPathComponent(Self.projectFileName)
        guard fileManager.fileExists(atPath: url.path) else { throw FloorPlanStorageError.notFound(id) }
        return try Self.decodeProject(Data(contentsOf: url))
    }

    public func rawFile(projectID: UUID, name: String) throws -> Data {
        let url = folder(for: projectID).appendingPathComponent((name as NSString).lastPathComponent)
        return try Data(contentsOf: url)
    }

    public func delete(id: UUID) throws {
        let dir = folder(for: id)
        guard fileManager.fileExists(atPath: dir.path) else { throw FloorPlanStorageError.notFound(id) }
        try fileManager.removeItem(at: dir)
    }

    /// Lista os projetos, do mais recentemente alterado para o mais antigo.
    public func list() throws -> ProjectListing {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return ProjectListing(projects: [], unreadable: [])
        }
        let folders = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey])
        var projects: [ProjectSummary] = []
        var unreadable: [UnreadableProject] = []
        for dir in folders {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let file = dir.appendingPathComponent(Self.projectFileName)
            do {
                let data = try Data(contentsOf: file)
                try Self.checkSchema(data)
                projects.append(try FloorPlanCoding.decoder().decode(ProjectSummary.self, from: data))
            } catch {
                unreadable.append(UnreadableProject(folderName: dir.lastPathComponent,
                                                    reason: String(describing: error)))
            }
        }
        projects.sort { $0.updatedAt > $1.updatedAt }
        return ProjectListing(projects: projects, unreadable: unreadable)
    }

    // MARK: - Esquema

    private struct SchemaProbe: Decodable { var schemaVersion: Int }

    private static func checkSchema(_ data: Data) throws {
        let probe = try FloorPlanCoding.decoder().decode(SchemaProbe.self, from: data)
        if probe.schemaVersion > FloorPlanProject.currentSchemaVersion {
            throw FloorPlanStorageError.unsupportedSchema(found: probe.schemaVersion,
                                                          supported: FloorPlanProject.currentSchemaVersion)
        }
    }

    /// Ponto único para migrações futuras (`schemaVersion` < atual). Hoje só existe a versão 1.
    static func decodeProject(_ data: Data) throws -> FloorPlanProject {
        try checkSchema(data)
        return try FloorPlanCoding.decoder().decode(FloorPlanProject.self, from: data)
    }
}
