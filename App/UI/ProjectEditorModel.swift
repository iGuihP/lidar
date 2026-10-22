import Foundation
import Observation
import FloorPlanCore

enum PlanSelection: Hashable {
    case wall(UUID)
    case opening(UUID)
    case room(UUID)
    case roomVertex(UUID, Int)
}

enum PlanTool: Equatable {
    case select
    case addWall
}

/// Liga o `FloorPlanEditor` (lógica pura) ao disco e à UI. Cada edição é gravada em seguida;
/// durante um arrasto só é gravado ao soltar.
@Observable
@MainActor
final class ProjectEditorModel {
    private(set) var project: FloorPlanProject
    private(set) var editor: FloorPlanEditor
    var selection: PlanSelection?
    var tool: PlanTool = .select
    var errorMessage: String?
    private let storage: FloorPlanStorage

    init(project: FloorPlanProject, storage: FloorPlanStorage) {
        self.project = project
        self.storage = storage
        self.editor = FloorPlanEditor(original: project.original, edited: project.edited)
    }

    var plan: FloorPlan { editor.plan }
    var original: FloorPlan { editor.original }

    // MARK: Edição

    /// Edição discreta (um toque/botão): aplica e grava.
    func edit(_ change: (inout FloorPlanEditor) -> Void) {
        change(&editor)
        dropStaleSelection()
        persist()
    }

    func beginGesture() { editor.beginGesture() }

    /// Dentro de um arrasto: aplica sem gravar.
    func gestureEdit(_ change: (inout FloorPlanEditor) -> Void) {
        change(&editor)
    }

    func endGesture() {
        editor.endGesture()
        dropStaleSelection()
        persist()
    }

    func undo() { edit { $0.undo() } }
    func redo() { edit { $0.redo() } }
    func resetToOriginal() { edit { $0.resetToOriginal() } }

    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        project.name = trimmed
        persist()
    }

    /// Projeto com a planta editada atual (para exportar).
    var currentProject: FloorPlanProject {
        var p = project
        p.edited = editor.plan
        return p
    }

    func rawCaptureJSON() -> Data? {
        guard let name = project.captures.first?.rawCaptureFile else { return nil }
        return try? storage.rawFile(projectID: project.id, name: name)
    }

    // MARK: Interno

    private func dropStaleSelection() {
        switch selection {
        case .wall(let id): if plan.wall(id) == nil { selection = nil }
        case .opening(let id): if !plan.openings.contains(where: { $0.id == id }) { selection = nil }
        case .room(let id): if !plan.rooms.contains(where: { $0.id == id }) { selection = nil }
        case .roomVertex(let id, let i):
            if plan.rooms.first(where: { $0.id == id })?.outline.indices.contains(i) != true { selection = nil }
        case nil: break
        }
    }

    private func persist() {
        project.edited = editor.plan
        project.updatedAt = Date()
        do {
            try storage.save(project)
        } catch {
            errorMessage = "Falha ao salvar: \(error.localizedDescription)"
        }
    }
}
