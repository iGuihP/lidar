import SwiftUI
import FloorPlanCore

/// Fase 1: mostra os dados reais retornados pelo RoomPlan (sem processamento), para validar a
/// captura em dispositivo e coletar fixtures reais para os testes.
struct CaptureInspectorView: View {
    let model: ProjectEditorModel
    @Environment(\.dismiss) private var dismiss

    private var capture: CaptureRecord? { model.project.captures.first }

    var body: some View {
        List {
            if let capture {
                Section("Captura") {
                    row("Data", capture.capturedAt.formatted(date: .abbreviated, time: .standard))
                    row("Aparelho", capture.device.deviceModel)
                    row("Sistema", "\(capture.device.systemName) \(capture.device.systemVersion)")
                    row("App", capture.device.appVersion)
                    row("LiDAR", capture.device.lidarSupported ? "sim" : "não")
                    row("Versão do CapturedRoom", "\(capture.snapshot.roomPlanVersion)")
                    if !capture.snapshot.sections.isEmpty {
                        row("Seções", capture.snapshot.sections.joined(separator: ", "))
                    }
                }
                Section("Contagem") {
                    ForEach([SurfaceSnapshot.Kind.wall, .door, .window, .opening, .floor], id: \.self) { kind in
                        row(kindLabel(kind), "\(capture.snapshot.surfaces.filter { $0.kind == kind }.count)")
                    }
                    row("Objetos", "\(capture.snapshot.objects.count)")
                }
                Section("Superfícies") {
                    ForEach(capture.snapshot.surfaces) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(kindLabel(s.kind)) · confiança \(s.confidence.rawValue)")
                                .font(.subheadline.weight(.semibold))
                            Text(detail(s)).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                if !capture.snapshot.objects.isEmpty {
                    Section("Objetos detectados") {
                        ForEach(capture.snapshot.objects) { o in
                            Text("\(o.category) · confiança \(o.confidence.rawValue)").font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle("Dados da captura")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() } } }
    }

    private func row(_ k: String, _ v: String) -> some View {
        LabeledContent(k) { Text(v).foregroundStyle(.secondary) }
    }

    private func kindLabel(_ k: SurfaceSnapshot.Kind) -> String {
        switch k {
        case .wall: return "Paredes"
        case .door: return "Portas"
        case .window: return "Janelas"
        case .opening: return "Aberturas"
        case .floor: return "Pisos"
        }
    }

    private func detail(_ s: SurfaceSnapshot) -> String {
        guard s.transform.count == 16, s.dimensions.count == 3 else { return "dados inválidos" }
        func f(_ v: Double) -> String { String(format: "%.2f", v) }
        var text = "dim \(f(s.dimensions[0]))×\(f(s.dimensions[1]))×\(f(s.dimensions[2])) m"
        text += " · pos (\(f(s.transform[12])), \(f(s.transform[13])), \(f(s.transform[14])))"
        if !s.polygonCorners.isEmpty { text += " · \(s.polygonCorners.count) vértices" }
        if s.isCurved { text += " · curva" }
        if s.completedEdges.count < 4 { text += " · bordas \(s.completedEdges.map(\.rawValue).joined(separator: "/"))" }
        if let open = s.isDoorOpen { text += open ? " · aberta" : " · fechada" }
        return text
    }
}
