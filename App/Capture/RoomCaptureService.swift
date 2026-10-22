import UIKit
import RoomPlan

enum CaptureError: LocalizedError {
    case cancelled
    case noGeometry

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Escaneamento cancelado."
        case .noGeometry: return "Nenhuma parede foi reconhecida. Tente novamente com mais luz e percorrendo todo o ambiente."
        }
    }
}

/// Encapsula o RoomPlan (`RoomCaptureView` + `RoomBuilder`). Não conhece planta, edição nem disco.
///
/// O `RoomCaptureView` fornece a câmera, o feedback em tempo real e as orientações de movimento da
/// Apple. Ao parar a sessão devolvemos `false` em `shouldPresent` para pós-processar nós mesmos
/// com `RoomBuilder` e evitar a tela de resultado do framework.
@MainActor
final class RoomCaptureService: NSObject, RoomCaptureViewDelegate {
    static var isSupported: Bool { RoomCaptureSession.isSupported }

    let captureView: RoomCaptureView
    /// Chamado uma vez por escaneamento com o ambiente processado, o erro ou o cancelamento.
    var onFinished: ((Result<CapturedRoom, Error>) -> Void)?

    private var cancelled = false

    override init() {
        captureView = RoomCaptureView(frame: .zero)
        super.init()
        captureView.delegate = self
    }

    // `RoomCaptureViewDelegate` herda de `NSCoding`.
    nonisolated required init?(coder: NSCoder) { fatalError("Não suportado") }
    nonisolated func encode(with coder: NSCoder) {}

    func start() {
        cancelled = false
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    /// Conclui: o RoomPlan entrega os dados brutos em `captureView(shouldPresent:error:)`.
    func finish() {
        captureView.captureSession.stop()
    }

    func cancel() {
        cancelled = true
        captureView.captureSession.stop()
    }

    // MARK: RoomCaptureViewDelegate

    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
        Task { @MainActor in
            await self.process(roomDataForProcessing, error: error)
        }
        return false
    }

    nonisolated func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {}

    private func process(_ data: CapturedRoomData, error: Error?) async {
        if cancelled {
            onFinished?(.failure(CaptureError.cancelled))
            return
        }
        if let error {
            onFinished?(.failure(error))
            return
        }
        do {
            let room = try await RoomBuilder(options: [.beautifyObjects]).capturedRoom(from: data)
            onFinished?(.success(room))
        } catch {
            onFinished?(.failure(error))
        }
    }
}
