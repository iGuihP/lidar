# Formato de exportação JSON

Arquivo gerado por **Exportar JSON**. Contrato estável para integração com outros sistemas.
Schema formal: [`floorplan.schema.json`](floorplan.schema.json) (JSON Schema 2020-12; o `$id` é um placeholder).

- `format`: sempre `"ios-floorplan-scanner.plan"`.
- `schemaVersion`: inteiro. **Mudanças incompatíveis incrementam este número**; acrescentar campos
  opcionais não incrementa. Leitores devem ignorar campos desconhecidos e recusar `schemaVersion` maior que o conhecido.
- Codificação: UTF-8, datas ISO-8601 (UTC), UUIDs em maiúsculas. Números arredondados a 0,1 mm.

## Unidades e coordenadas

- Unidade: **metros** (`units: "meters"`).
- Sistema `floorplan-topdown-v1`: vista **de cima**, sem espelhamento. `x` = eixo X do mundo ARKit,
  `y` = eixo Z do mundo ARKit (cresce "para baixo" na vista de cima, igual ao SVG).
- **A origem é arbitrária**: é onde a sessão AR começou, não um ponto do prédio. Use `bounds` para
  normalizar (subtraia `bounds.min`) se precisar de coordenadas positivas.
- Não há referência de norte nem georreferenciamento.

## Estrutura

| Campo | Descrição |
|---|---|
| `project` | `id`, `name`, `capturedAt`, `updatedAt` |
| `captures[]` | Uma por ambiente escaneado: `id`, `capturedAt`, `roomPlanVersion`, `device` (modelo, sistema, versão do app, LiDAR) |
| `hasUserEdits` | `true` se `edited` difere de `original` |
| `edited` | Planta com as correções do usuário (é a que deve ser usada) |
| `original` | Planta gerada automaticamente da captura, sem correções (opcional; omitida se exportada sem original) |
| `disclaimer` | Aviso de que a planta é estimada |

Cada plano (`edited`/`original`) contém:

- `bounds` — `min`/`max` que envolvem paredes (com espessura) e contornos.
- `walls[]` — `id`, `start`, `end`, `lengthMeters`, `thicknessMeters`, `thicknessIsEstimated`, `heightMeters?`,
  `origin` (`captured` | `userAdded`). A linha de centro vai de `start` a `end`.
  **A espessura é um valor padrão estimado (10 cm)**: o RoomPlan não mede espessura de parede.
- `openings[]` — `id`, `kind` (`door` | `window` | `opening`), `wallId`, `offsetMeters` (do `start` da
  parede até o **centro** da abertura), `widthMeters`, `heightMeters`, `sillHeightMeters` (peitoril; 0 em portas),
  `isOpen?` (só portas), `center` (no plano).
- `rooms[]` — `id`, `name`, `areaSquareMeters`, `outline` (polígono fechado, sem repetir o primeiro vértice,
  anti-horário no sistema matemático), `wallIds` (paredes do contorno, sem ordem garantida).
- `issues[]` — pontos que precisam de conferência: `kind`, `severity` (`info` | `warning`), `targetIds`, `location?`, `value?`.
  Itens corrigidos pelo usuário são removidos desta lista.

## Limites conhecidos

- Precisão **não validada** por medição; a Apple não publica garantia de precisão do RoomPlan.
- Paredes curvas são aproximadas por um segmento reto (aparecem em `issues` como `curvedWall`).
- O sentido de abertura das portas não é capturado; o SVG desenha o giro para dentro do ambiente mais próximo.
- Objetos (móveis) são guardados na captura, mas ainda não aparecem na planta nem na exportação.
- Versão 1: um ambiente por projeto (`captures[]` já é uma lista, para vários ambientes no futuro).

## SVG

- `viewBox` em **centímetros**; `width`/`height` em **mm** conforme a escala impressa (padrão 1:50, 1 m = 20 mm).
- Grupos: `rooms`, `walls` (com máscara que abre os vãos), `openings`, `dimensions`, `labels`, `issues` (opcional), `scale`.
- Elementos trazem `data-wall-id`, `data-opening-id`, `data-room-id` com os mesmos UUIDs do JSON.

## Arquivos do projeto no aparelho

```
Documents/FloorPlans/<project-id>/project.json              modelo interno (schemaVersion próprio, inclui snapshot e planta original/editada)
Documents/FloorPlans/<project-id>/capture-<id>.roomplan.json  JSON bruto Codable do CapturedRoom (Apple)
```
O `project.json` é formato interno; para integrar, use o JSON exportado acima.
