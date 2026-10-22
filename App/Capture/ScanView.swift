import SwiftUI
import RoomPlan

struct RoomCaptureRepresentable: UIViewRepresentable {
    let view: RoomCaptureView
    func makeUIView(context: Context) -> RoomCaptureView { view }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

/// Tela de escaneamento. Entrega o resultado por `onCaptured` e fecha.
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = CaptureManager()
    let onCaptured: (CaptureResult) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .task { await manager.prepare() }
        .onChange(of: manager.state) { _, newState in
            if newState == .finished, let result = manager.result {
                onCaptured(result)
                dismiss()
            }
        }
        .interactiveDismissDisabled(manager.state == .scanning || manager.state == .processing)
    }

    @ViewBuilder
    private var content: some View {
        switch manager.state {
        case .checking:
            ProgressView().tint(.white)
        case .unsupported:
            message(title: "Escaneamento indisponível",
                    text: "Este aparelho não tem sensor LiDAR, necessário para o RoomPlan. O escaneamento exige iPhone Pro (12 Pro ou posterior) ou iPad Pro com LiDAR. Você ainda pode abrir, editar e exportar projetos salvos.")
        case .cameraDenied:
            VStack(spacing: 16) {
                message(title: "Câmera bloqueada",
                        text: "O app precisa da câmera para escanear. Libere o acesso em Ajustes > Floor Plan Scanner > Câmera.")
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        case .ready:
            VStack(spacing: 20) {
                message(title: "Pronto para escanear",
                        text: "Fique em um canto do ambiente e caminhe devagar, apontando o iPhone para paredes, portas e janelas. Mantenha boa iluminação e siga as orientações exibidas na tela.")
                Button("Iniciar escaneamento") { manager.start() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case .failed(let text):
            VStack(spacing: 20) {
                message(title: "Não foi possível concluir", text: text)
                Button("Tentar novamente") { manager.start() }
                    .buttonStyle(.borderedProminent)
            }
        case .scanning, .processing, .finished:
            scanning
        }
        if manager.state != .scanning && manager.state != .processing {
            VStack {
                HStack {
                    Button("Fechar") { dismiss() }
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }
    }

    private var scanning: some View {
        ZStack {
            if let service = manager.service {
                RoomCaptureRepresentable(view: service.captureView).ignoresSafeArea()
            }
            VStack {
                Spacer()
                if manager.state == .processing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Processando captura…")
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 40)
                } else {
                    HStack(spacing: 16) {
                        Button("Cancelar", role: .destructive) {
                            manager.cancel()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        Button("Concluir") { manager.finish() }
                            .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func message(title: String, text: String) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.title2.bold())
            Text(text).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}
