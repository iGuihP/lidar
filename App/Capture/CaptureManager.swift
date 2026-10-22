import AVFoundation
import Foundation
import Observation
import RoomPlan
import FloorPlanCore

/// Resultado de um escaneamento já convertido para o núcleo.
struct CaptureResult: Identifiable {
    let id = UUID()
    let capturedAt: Date
    let device: DeviceMetadata
    let snapshot: CapturedRoomSnapshot
    /// JSON `Codable` bruto do `CapturedRoom` da Apple.
    let rawRoomPlanJSON: Data
}

/// Fluxo do escaneamento: compatibilidade, permissão de câmera, iniciar/concluir/cancelar.
@Observable
@MainActor
final class CaptureManager {
    enum State: Equatable {
        case checking
        case unsupported
        case cameraDenied
        case ready
        case scanning
        case processing
        case finished
        case failed(String)
    }

    private(set) var state: State = .checking
    private(set) var result: CaptureResult?
    private(set) var service: RoomCaptureService?
    private var retiredService: RoomCaptureService?

    func prepare() async {
        guard RoomCaptureService.isSupported else {
            state = .unsupported
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            state = .ready
        case .notDetermined:
            state = await AVCaptureDevice.requestAccess(for: .video) ? .ready : .cameraDenied
        default:
            state = .cameraDenied
        }
    }

    func start() {
        switch state {
        case .ready, .failed: break
        default: return
        }
        let service = RoomCaptureService()
        service.onFinished = { [weak self, weak service] outcome in
            guard let self, let service, self.service === service else { return } // ignora escaneamentos cancelados
            self.handle(outcome)
        }
        retiredService = nil
        self.service = service
        state = .scanning
        service.start()
    }

    func finish() {
        guard state == .scanning else { return }
        state = .processing
        service?.finish()
    }

    func cancel() {
        if state == .scanning || state == .processing {
            service?.cancel()
            retiredService = service // mantém a view viva até a sessão parar
        }
        service = nil
        state = .ready
    }

    private func handle(_ outcome: Result<CapturedRoom, Error>) {
        switch outcome {
        case .failure(let error):
            service = nil
            state = .failed(error.localizedDescription)
        case .success(let room):
            let snapshot = RoomSnapshotConverter.snapshot(from: room)
            guard snapshot.surfaces.contains(where: { $0.kind == .wall }) else {
                service = nil
                state = .failed(CaptureError.noGeometry.localizedDescription)
                return
            }
            do {
                let raw = try JSONEncoder().encode(room)
                result = CaptureResult(capturedAt: Date(), device: DeviceInfo.metadata(),
                                       snapshot: snapshot, rawRoomPlanJSON: raw)
                service = nil
                state = .finished
            } catch {
                service = nil
                state = .failed("Falha ao serializar a captura: \(error.localizedDescription)")
            }
        }
    }
}
