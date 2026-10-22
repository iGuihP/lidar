# Floor Plan Scanner (iOS)

App nativo para iPhone/iPad com LiDAR que escaneia um ambiente com o **Apple RoomPlan** e gera uma
**planta baixa 2D vista de cima** (paredes, portas, janelas, aberturas, ambientes), editável, salva
localmente e exportável em **JSON versionado** e **SVG**. Projeto independente; sem backend nem conta.

> Planta **estimada** a partir de LiDAR. Não é levantamento arquitetônico; precisão não validada por medição.

## Requisitos

- Escanear: iPhone Pro (12 Pro ou posterior) ou iPad Pro com LiDAR, **iOS 17+** (RoomPlan: iOS 16; vários ambientes: iOS 17).
  O app consulta `RoomCaptureSession.isSupported` e explica quando não houver LiDAR. Projetos salvos abrem em qualquer aparelho com iOS 17.
- Desenvolver: Mac com Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Rodar

```bash
brew install xcodegen
xcodegen generate            # cria FloorPlanScanner.xcodeproj a partir de project.yml
open FloorPlanScanner.xcodeproj   # escolha seu Team em Signing & Capabilities e rode no iPhone
```
O bundle id padrão (`com.example.floorplanscanner`) é um placeholder; altere em `project.yml`.

Testes da lógica (não precisam de Xcode nem de iPhone):

```bash
swift test --package-path Packages/FloorPlanCore
```

## Estrutura

```
App/                         SwiftUI + RoomPlan (captura, canvas 2D, editor, lista, inspetor)
Packages/FloorPlanCore/      Normalizer, Generator, Editor, Storage, Exporter (só Foundation; testado em Linux)
docs/                        SCHEMA.md, floorplan.schema.json, ARCHITECTURE.md, VALIDATION.md, GITHUB_BUILD.md, MULTI_ROOM.md
project.yml                  definição do projeto Xcode (XcodeGen)
```

## Status por fase

| Fase | Código | Validado |
|---|---|---|
| 1. Prova de conceito (captura + dados brutos) | escrito (`App/Capture`, *Dados da captura*) | ❌ aguarda teste no iPhone |
| 2. Planta 2D | escrito; núcleo testado | núcleo ✅ / UI ❌ |
| 3. Persistência | escrito; storage testado | storage ✅ / UI ❌ |
| 4. Editor | escrito; lógica testada | lógica ✅ / UI ❌ |
| 5. Exportação JSON/SVG | escrito; testado | ✅ (fixture sintética) |
| 6. Vários ambientes | investigação documental em `docs/MULTI_ROOM.md`; não implementada | — |

Detalhes e roteiro de teste em [`docs/VALIDATION.md`](docs/VALIDATION.md). Compilar pelo GitHub: [`docs/GITHUB_BUILD.md`](docs/GITHUB_BUILD.md).
