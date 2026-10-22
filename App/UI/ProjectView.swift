import SwiftUI
import FloorPlanCore

/// Carrega o projeto do disco e mostra a planta.
struct ProjectView: View {
    @Environment(AppModel.self) private var app
    let projectID: UUID
    @State private var model: ProjectEditorModel?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let model {
                ProjectContent(model: model)
            } else if let loadError {
                ContentUnavailableView("Não foi possível abrir o projeto",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .task {
            guard model == nil else { return }
            do {
                model = ProjectEditorModel(project: try app.storage.load(id: projectID), storage: app.storage)
            } catch FloorPlanStorageError.unsupportedSchema(let found, let supported) {
                loadError = "Este projeto foi salvo por uma versão mais nova do app (esquema \(found); esta versão lê até \(supported)). Atualize o app. O arquivo não foi alterado."
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ProjectContent: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: ProjectEditorModel

    @State private var isEditing = false
    @State private var showOriginal = false
    @State private var showIssues = true
    @State private var fitRequest = 0
    @State private var showIssuesList = false
    @State private var showInspector = false
    @State private var shareItem: ShareItem?
    @State private var renamingProject = false
    @State private var renamingRoom = false
    @State private var nameDraft = ""
    @State private var confirmReset = false
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                PlanCanvasView(model: model,
                               plan: showOriginal ? model.original : model.plan,
                               interactive: !showOriginal,
                               isEditing: isEditing && !showOriginal,
                               showIssues: showIssues,
                               fitRequest: fitRequest)
                infoOverlay
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                viewControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
            }
            if isEditing && !showOriginal {
                Divider()
                editBar
            }
        }
        .navigationTitle(model.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Concluir" : "Editar") {
                    isEditing.toggle()
                    model.tool = .select
                    if isEditing { showOriginal = false }
                }
            }
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .sheet(isPresented: $showIssuesList) { issuesSheet }
        .sheet(isPresented: $showInspector) {
            NavigationStack { CaptureInspectorView(model: model) }
        }
        .sheet(item: $shareItem) { item in ShareSheet(url: item.url) }
        .alert("Renomear projeto", isPresented: $renamingProject) {
            TextField("Nome", text: $nameDraft)
            Button("Cancelar", role: .cancel) {}
            Button("Salvar") { model.rename(to: nameDraft) }
        }
        .alert("Renomear ambiente", isPresented: $renamingRoom) {
            TextField("Nome", text: $nameDraft)
            Button("Cancelar", role: .cancel) {}
            Button("Salvar") {
                if case .room(let id)? = model.selection {
                    model.edit { $0.renameRoom(id, to: nameDraft) }
                }
            }
        }
        .confirmationDialog("Descartar todas as correções e voltar à geometria original da captura?",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Restaurar original", role: .destructive) { model.resetToOriginal() }
        } message: {
            Text("Você pode desfazer esta ação.")
        }
        .alert("Erro", isPresented: Binding(get: { model.errorMessage != nil || exportError != nil },
                                            set: { if !$0 { model.errorMessage = nil; exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? exportError ?? "")
        }
    }

    // MARK: - Menu

    private var menu: some View {
        Menu {
            Button("Renomear projeto", systemImage: "pencil") {
                nameDraft = model.project.name
                renamingProject = true
            }
            Divider()
            Button("Exportar JSON", systemImage: "curlybraces") { export(.json) }
            Button("Exportar SVG", systemImage: "square.and.arrow.up") { export(.svg) }
            if model.rawCaptureJSON() != nil {
                Button("Exportar JSON bruto do RoomPlan", systemImage: "doc") { export(.raw) }
            }
            Divider()
            Button("Dados da captura", systemImage: "list.bullet.rectangle") { showInspector = true }
            Button("Restaurar geometria original", systemImage: "arrow.uturn.backward.circle", role: .destructive) {
                confirmReset = true
            }
            .disabled(!model.editor.hasChanges)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Sobreposições

    private var infoOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showOriginal {
                Label("Geometria original da captura (somente leitura)", systemImage: "eye")
                    .font(.footnote.weight(.semibold))
            }
            Text(selectionDescription ?? summary)
                .font(.footnote)
            Text("Planta estimada a partir de LiDAR; sem garantia de precisão arquitetônica.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .allowsHitTesting(false)
    }

    private var summary: String {
        let plan = showOriginal ? model.original : model.plan
        let area = plan.rooms.map(\.area).reduce(0, +)
        return "\(plan.rooms.count) ambiente(s) · \(plan.walls.count) paredes · \(plan.openings.count) aberturas · \(area.areaText)"
    }

    private var selectionDescription: String? {
        let plan = model.plan
        switch model.selection {
        case .wall(let id)?:
            guard let w = plan.wall(id) else { return nil }
            return "Parede · \(w.length.metersText) · espessura \(Int((w.thickness * 100).rounded())) cm (estimada)"
        case .opening(let id)?:
            guard let o = plan.openings.first(where: { $0.id == id }) else { return nil }
            return "\(o.kind.label) · largura \(o.width.metersText)"
        case .room(let id)?:
            guard let r = plan.rooms.first(where: { $0.id == id }) else { return nil }
            return "\(r.name) · \(r.area.areaText)"
        case .roomVertex(_, let i)?:
            return "Vértice \(i + 1) do contorno"
        case nil:
            return nil
        }
    }

    private var viewControls: some View {
        let count = (showOriginal ? model.original : model.plan).issues.count
        return VStack(spacing: 10) {
            circleButton("scope") { fitRequest += 1 }
            circleButton(showOriginal ? "eye.fill" : "eye") {
                showOriginal.toggle()
                if showOriginal { isEditing = false }
            }
            circleButton("exclamationmark.triangle", badge: count) { showIssuesList = true }
        }
    }

    private func circleButton(_ symbol: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.orange, in: Circle())
                    }
                }
        }
    }

    // MARK: - Barra de edição

    private var editBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.editor.canUndo)
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.editor.canRedo)
                Divider().frame(height: 24)
                Button(model.tool == .addWall ? "Cancelar" : "Nova parede", systemImage: "plus.square") {
                    model.tool = model.tool == .addWall ? .select : .addWall
                    model.selection = nil
                }
                selectionTools
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var selectionTools: some View {
        switch model.selection {
        case .wall(let id)?:
            if let wall = model.plan.wall(id) {
                ForEach(Opening.Kind.allCases, id: \.self) { kind in
                    Button("+ \(kind.label)") { addOpening(kind, to: wall) }
                }
                Menu("Espessura") {
                    ForEach([0.075, 0.10, 0.15, 0.20], id: \.self) { t in
                        Button("\(Int((t * 100).rounded())) cm") { model.edit { $0.setWallThickness(id, to: t) } }
                    }
                }
                Button("Excluir parede", systemImage: "trash", role: .destructive) {
                    model.edit { $0.removeWall(id) }
                }
            }
        case .opening(let id)?:
            if let o = model.plan.openings.first(where: { $0.id == id }) {
                Menu(o.kind.label) {
                    ForEach(Opening.Kind.allCases, id: \.self) { kind in
                        Button(kind.label) { model.edit { $0.setOpeningKind(id, to: kind) } }
                    }
                }
                Button { model.edit { $0.resizeOpening(id, width: o.width - 0.1) } } label: { Image(systemName: "minus") }
                Text(o.width.metersText).font(.footnote.monospacedDigit())
                Button { model.edit { $0.resizeOpening(id, width: o.width + 0.1) } } label: { Image(systemName: "plus") }
                Button("Excluir", systemImage: "trash", role: .destructive) { model.edit { $0.removeOpening(id) } }
            }
        case .room(let id)?:
            Button("Renomear", systemImage: "pencil") {
                nameDraft = model.plan.rooms.first(where: { $0.id == id })?.name ?? ""
                renamingRoom = true
            }
            Button("Contorno pelas paredes", systemImage: "square.dashed") {
                model.edit { $0.rebuildRoomOutlineFromWalls(room: id) }
            }
        case .roomVertex(let id, let i)?:
            Button("Remover vértice", systemImage: "minus.circle", role: .destructive) {
                model.edit { $0.removeRoomVertex(room: id, index: i) }
            }
        case nil:
            Text(model.tool == .addWall ? "Arraste no plano para desenhar a parede" : "Toque em um elemento para editar")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func addOpening(_ kind: Opening.Kind, to wall: Wall) {
        var created: UUID?
        model.edit { created = $0.addOpening(kind: kind, onWall: wall.id, offset: wall.length / 2) }
        if let created { model.selection = .opening(created) }
    }

    // MARK: - Pendências

    private var issuesSheet: some View {
        NavigationStack {
            let plan = showOriginal ? model.original : model.plan
            List {
                if plan.issues.isEmpty {
                    ContentUnavailableView("Nenhuma pendência", systemImage: "checkmark.circle",
                                           description: Text("O RoomPlan não sinalizou elementos para revisão. Ainda assim, confira a planta com medições reais."))
                }
                ForEach(plan.issues) { issue in
                    Button {
                        select(issue)
                        showIssuesList = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(issue.title, systemImage: issue.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle")
                                .foregroundStyle(issue.severity == .warning ? .orange : .secondary)
                            Text(issue.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if !showOriginal {
                            Button("Dispensar") { model.edit { $0.dismissIssue(issue.id) } }
                        }
                    }
                }
            }
            .navigationTitle("Pontos de revisão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("OK") { showIssuesList = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func select(_ issue: ReviewIssue) {
        guard !showOriginal, let target = issue.targetIDs.first else { return }
        if model.plan.wall(target) != nil { model.selection = .wall(target) }
        else if model.plan.openings.contains(where: { $0.id == target }) { model.selection = .opening(target) }
    }

    // MARK: - Exportação

    private enum ExportKind { case json, svg, raw }

    private func export(_ kind: ExportKind) {
        do {
            let project = model.currentProject
            let base = fileBaseName(project)
            let data: Data
            let ext: String
            switch kind {
            case .json:
                data = try FloorPlanExporter.json(project)
                ext = "json"
            case .svg:
                data = Data(FloorPlanExporter.svg(project).utf8)
                ext = "svg"
            case .raw:
                guard let raw = model.rawCaptureJSON() else { return }
                data = raw
                ext = "roomplan.json"
            }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exports/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(base).\(ext)")
            try data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch {
            exportError = "Falha ao exportar: \(error.localizedDescription)"
        }
    }

    private func fileBaseName(_ project: FloorPlanProject) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = String(project.name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "planta" : cleaned
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
