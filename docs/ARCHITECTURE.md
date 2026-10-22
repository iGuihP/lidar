# Arquitetura

```
App (SwiftUI, iOS 17+)                      FloorPlanCore (Swift Package, só Foundation)
─────────────────────────                   ─────────────────────────────────────────────
Capture/RoomCaptureService  ─ snapshot ───▶ GeometryNormalizer  (3D ARKit → segmentos 2D)
Capture/RoomSnapshotConverter               FloorPlanGenerator  (cantos, aberturas, contorno, alertas)
Capture/CaptureManager (permissão, estado)  FloorPlanEditor     (edição + undo/redo; original intocado)
UI/* (canvas, editor, lista, inspetor)      FloorPlanStorage    (uma pasta por projeto, gravação atômica)
AppModel / ProjectEditorModel               FloorPlanExporter   (JSON versionado, SVG)
```

Regras:

1. **Só `RoomCaptureService` e `RoomSnapshotConverter` importam RoomPlan.** Eles copiam o `CapturedRoom` para
   `CapturedRoomSnapshot`. Daí em diante o núcleo não depende de Apple e roda (e é testado) em Linux.
2. **Geometria original ≠ editada.** O projeto guarda o snapshot, a planta gerada (`original`) e a planta
   editada (`edited`); o editor só altera `edited`. O JSON bruto da Apple é guardado ao lado para reprocessar no futuro.
3. **Captura independente da planta.** Melhorar o gerador não exige novo escaneamento: `FloorPlanGenerator.generate`
   pode ser reexecutado sobre os snapshots salvos.
4. **Preparado para vários ambientes:** `captures[]`, `CaptureRecord.placement` (transformação 2D), `Room.captureID`.
   A versão 1 usa uma captura com `placement` identidade.
5. **Privacidade:** nenhuma chamada de rede; nenhum dado sai do aparelho sem o usuário acionar "Exportar".

## Decisões

- JSON em disco (não SwiftData/Core Data): é a fonte da verdade, simples de migrar e inspecionar.
- Canvas desenhado com `Canvas` do SwiftUI; hit-testing e snapping na própria view.
- Espessura de parede fixa e estimada (10 cm): o RoomPlan não a fornece.
- `SWIFT_VERSION = 5` no app por ora (sem Xcode no ambiente de desenvolvimento para ajustar concorrência estrita).
