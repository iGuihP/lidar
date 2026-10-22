# Fase 6 — Investigação: vários ambientes e corredores

**Estado: investigação documental. Nada foi implementado nem testado em dispositivo.**

## O que a documentação da Apple diz

Fonte: *Scanning the rooms of a single structure* e `CapturedStructure`/`StructureBuilder` (iOS 17+).

- Cada ambiente é escaneado em sequência com **a mesma sessão AR contínua**: ao concluir um ambiente chama-se
  `captureSession.stop(pauseARSession: false)`, guarda-se o `CapturedRoom` e roda-se `run(configuration:)` de novo.
- `StructureBuilder.capturedStructure(from: [CapturedRoom])` junta os ambientes em um `CapturedStructure`
  (`rooms`, `walls`, `doors`, `windows`, `openings`, `floors`, `sections`, também `Codable`).
- Para os ambientes ficarem no **mesmo espaço de coordenadas**, a sessão AR deve ser contínua ou **relocalizada**
  com um `ARWorldMap` (app vai ao segundo plano, perde tracking etc.). Ambientes devem estar próximos (mesmo prédio).
- `CapturedRoom.story` / `Surface.story` indicam o andar.

## Como isto se encaixa na arquitetura atual

O modelo já prevê: `FloorPlanProject.captures[]`, `CaptureRecord.placement` (`Transform2D`), `Room.captureID`,
e `FloorPlanGenerator.generate(captures:)` já processa várias capturas. Se os `CapturedRoom` compartilham o espaço
de coordenadas, **`placement` permanece identidade** e as plantas se compõem sem alinhamento extra.

## Plano de implementação proposto (não iniciado)

1. `CaptureManager`: modo "continuar com outro ambiente" usando `stop(pauseARSession: false)` + novo `run`, acumulando `CaptureResult`s.
2. Opção A (preferida, mais simples): **composição própria** — cada `CapturedRoom` vira um `CaptureRecord` com `placement` identidade; o gerador já produz um `Room` por captura. Resolver paredes duplicadas entre ambientes vizinhos (mesma parede escaneada dos dois lados) por interseção/limiar de distância.
3. Opção B: usar `StructureBuilder` para obter paredes fundidas e converter `CapturedStructure` em snapshot. Menos código nosso, mas depende de comportamento da Apple (ver riscos).
4. Relocalização com `ARWorldMap` se o app for interrompido entre ambientes (persistir o mapa por projeto).
5. Editor: seleção/renomeação por ambiente já funciona; faltaria mover um ambiente inteiro (`placement`) para ajuste manual.

## Riscos conhecidos (a confirmar em dispositivo)

- Relatos em fóruns (não confirmados por mim) de que `StructureBuilder` perde a correspondência entre ambientes de entrada e saída (identificadores mudam) e de travamentos com certas paredes.
- Deriva de tracking entre ambientes distantes ou após interrupções.
- Paredes compartilhadas entre ambientes aparecem duplicadas (uma de cada lado), com espessura real desconhecida.
- Corredores longos: risco maior de deriva e de paredes incompletas.

## Experimento sugerido (precisa do iPhone)

Escanear 2 cômodos adjacentes na mesma sessão contínua, exportar os dois JSONs brutos e `CapturedStructure`, e medir:
(a) se as coordenadas dos dois `CapturedRoom` já são consistentes; (b) deslocamento da parede comum; (c) se `StructureBuilder` preserva portas entre cômodos.
