import Foundation

/// Cópia fiel, independente de RoomPlan/simd, do que a API retornou para um ambiente.
/// É a "geometria original": nunca é alterada depois de criada.
///
/// Convenções (as mesmas do `CapturedRoom` da Apple):
/// - `transform`: 16 valores, **column-major** (`m[coluna * 4 + linha]`), espaço do mundo ARKit (Y para cima, metros).
/// - `dimensions`: `[x, y, z]` da superfície no seu espaço local (largura, altura, profundidade).
public struct CapturedRoomSnapshot: Codable, Equatable, Sendable {
    public var roomID: UUID
    public var story: Int
    /// `CapturedRoom.version` informado pelo RoomPlan.
    public var roomPlanVersion: Int
    public var surfaces: [SurfaceSnapshot]
    public var objects: [ObjectSnapshot]
    /// Rótulos de `CapturedRoom.sections` (tipo de cômodo estimado), quando existirem.
    public var sections: [String]

    public init(roomID: UUID = UUID(), story: Int = 0, roomPlanVersion: Int = 0,
                surfaces: [SurfaceSnapshot], objects: [ObjectSnapshot] = [], sections: [String] = []) {
        self.roomID = roomID
        self.story = story
        self.roomPlanVersion = roomPlanVersion
        self.surfaces = surfaces
        self.objects = objects
        self.sections = sections
    }
}

public struct SurfaceSnapshot: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case wall, door, window, opening, floor }
    public enum Confidence: String, Codable, Sendable { case low, medium, high }
    public enum Edge: String, Codable, Sendable { case top, left, bottom, right }

    public var id: UUID
    public var parentID: UUID?
    public var kind: Kind
    /// Só para portas (`.door(isOpen:)`).
    public var isDoorOpen: Bool?
    public var confidence: Confidence
    public var transform: [Double]
    public var dimensions: [Double]
    /// Vértices no espaço local da superfície (`polygonCorners`), quando existirem.
    public var polygonCorners: [[Double]]
    public var completedEdges: [Edge]
    public var isCurved: Bool

    public init(id: UUID = UUID(), parentID: UUID? = nil, kind: Kind, isDoorOpen: Bool? = nil,
                confidence: Confidence = .high, transform: [Double], dimensions: [Double],
                polygonCorners: [[Double]] = [], completedEdges: [Edge] = [.top, .left, .bottom, .right],
                isCurved: Bool = false) {
        self.id = id
        self.parentID = parentID
        self.kind = kind
        self.isDoorOpen = isDoorOpen
        self.confidence = confidence
        self.transform = transform
        self.dimensions = dimensions
        self.polygonCorners = polygonCorners
        self.completedEdges = completedEdges
        self.isCurved = isCurved
    }
}

/// Objetos detectados (móveis etc.). Guardados na captura; ainda não entram na planta 2D.
public struct ObjectSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var category: String
    public var confidence: SurfaceSnapshot.Confidence
    public var transform: [Double]
    public var dimensions: [Double]

    public init(id: UUID = UUID(), category: String, confidence: SurfaceSnapshot.Confidence = .high,
                transform: [Double], dimensions: [Double]) {
        self.id = id
        self.category = category
        self.confidence = confidence
        self.transform = transform
        self.dimensions = dimensions
    }
}

/// Metadados do aparelho e da captura, quando disponíveis.
public struct DeviceMetadata: Codable, Equatable, Sendable {
    /// Identificador de hardware (ex.: `iPhone16,2`).
    public var deviceModel: String
    public var systemName: String
    public var systemVersion: String
    public var appVersion: String
    public var lidarSupported: Bool

    public init(deviceModel: String, systemName: String, systemVersion: String,
                appVersion: String, lidarSupported: Bool) {
        self.deviceModel = deviceModel
        self.systemName = systemName
        self.systemVersion = systemVersion
        self.appVersion = appVersion
        self.lidarSupported = lidarSupported
    }

    public static let unknown = DeviceMetadata(deviceModel: "unknown", systemName: "unknown",
                                               systemVersion: "unknown", appVersion: "unknown",
                                               lidarSupported: false)
}

/// Uma captura (um ambiente) dentro do projeto. A versão 1 usa exatamente uma.
public struct CaptureRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var capturedAt: Date
    public var device: DeviceMetadata
    public var snapshot: CapturedRoomSnapshot
    /// Posição da captura no plano do projeto (alinhamento entre ambientes: Fase 6).
    public var placement: Transform2D
    /// Nome do arquivo com o JSON bruto `Codable` da Apple (`CapturedRoom`), ao lado do `project.json`.
    public var rawCaptureFile: String?

    public init(id: UUID = UUID(), capturedAt: Date, device: DeviceMetadata,
                snapshot: CapturedRoomSnapshot, placement: Transform2D = .identity,
                rawCaptureFile: String? = nil) {
        self.id = id
        self.capturedAt = capturedAt
        self.device = device
        self.snapshot = snapshot
        self.placement = placement
        self.rawCaptureFile = rawCaptureFile
    }
}
