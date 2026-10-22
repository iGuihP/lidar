import SwiftUI
import FloorPlanCore

struct ProjectListView: View {
    @Environment(AppModel.self) private var app
    @State private var path: [UUID] = []
    @State private var askingName = false
    @State private var newName = ""
    @State private var pendingName = ""
    @State private var scanning = false
    @State private var deleting: ProjectSummary?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !app.unreadable.isEmpty {
                    Section {
                        ForEach(app.unreadable, id: \.folderName) { item in
                            Label("Pasta \(item.folderName.prefix(8))… não pôde ser lida. Os arquivos foram preservados.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                ForEach(app.projects) { project in
                    NavigationLink(value: project.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name).font(.headline)
                            Text("Capturado em \(project.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Excluir", role: .destructive) { deleting = project }
                    }
                }
            }
            .overlay {
                if app.projects.isEmpty && app.unreadable.isEmpty {
                    ContentUnavailableView {
                        Label("Nenhuma planta", systemImage: "square.split.bottomrightquarter")
                    } description: {
                        Text("Crie um projeto e escaneie um ambiente com o LiDAR do iPhone.")
                    } actions: {
                        Button("Nova planta") { newName = ""; askingName = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Plantas")
            .navigationDestination(for: UUID.self) { ProjectView(projectID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nova planta", systemImage: "plus") { newName = ""; askingName = true }
                }
            }
            .alert("Nova planta", isPresented: $askingName) {
                TextField("Nome", text: $newName)
                Button("Cancelar", role: .cancel) {}
                Button("Escanear") {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    pendingName = trimmed.isEmpty ? "Planta \(Date().formatted(date: .numeric, time: .shortened))" : trimmed
                    scanning = true
                }
            } message: {
                Text("Dê um nome ao projeto e em seguida escaneie o ambiente.")
            }
            .fullScreenCover(isPresented: $scanning) {
                ScanView { capture in
                    if let id = app.createProject(name: pendingName, from: capture) {
                        path = [id]
                    }
                }
            }
            .confirmationDialog("Excluir \(deleting?.name ?? "")?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Excluir permanentemente", role: .destructive) {
                    if let d = deleting { app.delete(d.id) }
                    deleting = nil
                }
            } message: {
                Text("A captura e as correções deste projeto serão apagadas do aparelho.")
            }
            .alert("Erro", isPresented: Binding(get: { app.errorMessage != nil },
                                                set: { if !$0 { app.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(app.errorMessage ?? "")
            }
        }
    }
}
