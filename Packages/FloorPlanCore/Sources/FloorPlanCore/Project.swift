import Foundation

/// Descrição autoexplicativa do sistema de coordenadas, gravada em todo projeto/exportação.
public struct CoordinateSystemInfo: Codable, Equatable, Sendable {
    public var name: String
    public var origin: String
    public var xAxis: String
    public var yAxis: String
    public var view: String

    public static let plan = CoordinateSystemInfo(
        name: "floorplan-topdown-v1",
        origin: "Origem arbitrária da sessão AR da captura (não é um ponto físico do prédio).",
        xAxis: "X do mundo ARKit (para a direita na vista de cima).",
        yAxis: "Z do mundo ARKit (para baixo na vista de cima; compatível com SVG).",
        view: "Vista de cima, sem espelhamento. Unidade: metros."
    )
}

public enum LengthUnit: String, Codable, Sendable { case meters }

/// Projeto salvo em disco (`project.json`). Reúne a geometria original (captura + planta gerada)
/// e a geometria editada.
public struct FloorPlanProject: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var units: LengthUnit
    public var coordinateSystem: CoordinateSystemInfo
    public var captures: [CaptureRecord]
    public var generatorSettings: GeneratorSettings
    /// Planta gerada automaticamente a partir das capturas. Imutável.
    public var original: FloorPlan
    /// Planta com as correções do usuário.
    public var edited: FloorPlan

    public init(schemaVersion: Int = FloorPlanProject.currentSchemaVersion, id: UUID = UUID(),
                name: String, createdAt: Date, updatedAt: Date, captures: [CaptureRecord],
                generatorSettings: GeneratorSettings, original: FloorPlan, edited: FloorPlan) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.units = .meters
        self.coordinateSystem = .plan
        self.captures = captures
        self.generatorSettings = generatorSettings
        self.original = original
        self.edited = edited
    }

    /// Cria um projeto de ambiente único a partir de uma captura: normaliza e gera a planta.
    public static func make(name: String, capture: CaptureRecord, roomName: String,
                            settings: GeneratorSettings = GeneratorSettings(),
                            now: Date = Date()) -> FloorPlanProject {
        let plan = FloorPlanGenerator.generate(captures: [capture], roomNames: [roomName], settings: settings)
        return FloorPlanProject(name: name, createdAt: capture.capturedAt, updatedAt: now,
                                captures: [capture], generatorSettings: settings,
                                original: plan, edited: plan)
    }

    public var hasUserEdits: Bool { original != edited }
}

/// Resumo leve para listagem (decodifica só alguns campos do `project.json`).
public struct ProjectSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var schemaVersion: Int
}
