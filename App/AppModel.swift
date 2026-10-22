import Foundation
import Observation
import FloorPlanCore

/// Estado global do app: projetos salvos em `Documents/FloorPlans`.
@Observable
@MainActor
final class AppModel {
    let storage: FloorPlanStorage
    private(set) var projects: [ProjectSummary] = []
    private(set) var unreadable: [UnreadableProject] = []
    var errorMessage: String?

    init(storage: FloorPlanStorage? = nil) {
        if let storage {
            self.storage = storage
        } else if let root = try? FloorPlanStorage.defaultRoot() {
            self.storage = FloorPlanStorage(rootURL: root)
        } else {
            self.storage = FloorPlanStorage(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("FloorPlans"))
            errorMessage = "Não foi possível acessar a pasta de documentos. Os projetos desta sessão não serão preservados."
        }
        reload()
    }

    func reload() {
        do {
            let listing = try storage.list()
            projects = listing.projects
            unreadable = listing.unreadable
        } catch {
            errorMessage = "Falha ao listar projetos: \(error.localizedDescription)"
        }
    }

    /// Cria e salva um projeto de ambiente único a partir de uma captura.
    func createProject(name: String, from capture: CaptureResult) -> UUID? {
        let rawName = "capture-\(capture.id.uuidString).roomplan.json"
        let record = CaptureRecord(id: capture.id, capturedAt: capture.capturedAt, device: capture.device,
                                   snapshot: capture.snapshot, rawCaptureFile: rawName)
        let project = FloorPlanProject.make(name: name, capture: record, roomName: "Ambiente 1")
        do {
            try storage.save(project, rawFiles: [rawName: capture.rawRoomPlanJSON])
            reload()
            return project.id
        } catch {
            errorMessage = "Falha ao salvar o projeto: \(error.localizedDescription)"
            return nil
        }
    }

    func delete(_ id: UUID) {
        do {
            try storage.delete(id: id)
            reload()
        } catch {
            errorMessage = "Falha ao excluir: \(error.localizedDescription)"
        }
    }
}
