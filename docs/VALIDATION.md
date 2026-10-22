# Validação

Este arquivo separa o que foi **efetivamente validado** do que ainda **não foi**. Atualize-o a cada teste em aparelho.

## Estado atual

| Item | Como foi verificado | Estado |
|---|---|---|
| Normalização 3D→2D, geração de planta, editor, storage, exportação (JSON/SVG) | 37 testes unitários (`swift test`) em Linux, fixtures **sintéticas** | ✅ validado |
| JSON exportado conforme `floorplan.schema.json` | Validado com `jsonschema` (Python) sobre exportação gerada pelo código; schema rejeita valor inválido | ✅ validado |
| SVG bem formado e legível | Parse XML nos testes + renderização no Chromium inspecionada visualmente (fixture sintética) | ✅ validado |
| Compilação da camada do app (SwiftUI/RoomPlan/ARKit) | Escrita **sem compilador Apple disponível**; assinaturas conferidas na documentação da Apple | ⚠️ **não compilada** |
| Captura com RoomPlan (Fase 1) | — | ❌ **não validada em dispositivo** |
| Conversão `CapturedRoom` → snapshot com dados reais | — | ❌ não validada |
| Planta gerada de uma captura real (cantos, portas, janelas) | — | ❌ não validada |
| Edição por toque/arrasto no iPhone | — | ❌ não validada |
| Precisão das dimensões vs. trena | — | ❌ não medida |
| Vários ambientes (Fase 6) | — | ❌ não iniciada |

## Roteiro de teste no iPhone (iPhone 15 Pro Max, iOS 26)

1. `brew install xcodegen && xcodegen generate`, abra `FloorPlanScanner.xcodeproj`, selecione seu *Team* em *Signing*, rode no aparelho.
   Se houver erros de compilação, envie o texto dos erros.
2. **Compatibilidade:** abrir "Nova planta" → "Escanear" mostra "Pronto para escanear" (não "indisponível") e pede permissão da câmera.
3. **Captura:** escanear um cômodo simples (retangular, com 1 porta e 1 janela). Conferir que as orientações da Apple aparecem, que "Concluir" processa e abre a planta.
4. **Dados brutos:** menu ⋯ → *Dados da captura*: confira contagens (paredes/portas/janelas/pisos), confiança e vértices (`polygonCorners`).
5. **Planta:** paredes fechando nos cantos? Porta e janela na parede certa? Há pontos laranja (pendências) coerentes?
6. **Medidas:** meça com trena 3–4 paredes e 1 porta; anote na tabela abaixo.
7. **Edição:** mover parede, arrastar ponta, adicionar porta, renomear ambiente, desfazer/refazer, fechar e reabrir o app.
8. **Exportação:** exportar JSON e SVG, abrir no Arquivos/Mail e conferir.
9. **Fixture real:** menu ⋯ → *Exportar JSON bruto do RoomPlan* e envie o arquivo: ele vira fixture de teste real.

### Tabela de medidas (preencher)

| Elemento | Trena (m) | App (m) | Diferença (cm) |
|---|---|---|---|
| Parede 1 | | | |
| Parede 2 | | | |
| Parede 3 | | | |
| Parede 4 | | | |
| Porta (largura) | | | |

Não há promessa de precisão arquitetônica até esta tabela ter dados reais suficientes.
