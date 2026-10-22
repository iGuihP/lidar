# Compilar pelo GitHub Actions

Workflow: [`.github/workflows/ios-build.yml`](../.github/workflows/ios-build.yml). Roda em todo push/PR e manualmente
(*Actions → iOS Build → Run workflow*).

## O que cada job faz

| Job | O que faz | Precisa de conta Apple? |
|---|---|---|
| `core-tests-linux` | `swift test` do `FloorPlanCore` em Linux | não |
| `build` | testes no macOS, gera o `.xcodeproj` (XcodeGen), **compila o app para o simulador** e gera um **`.ipa` sem assinatura** | não |
| `signed-ipa` | (manual, opcional) gera `.ipa` **assinado** instalável no seu iPhone | **sim** (Apple Developer ou Apple ID com perfil de desenvolvimento) |

Resultados ficam em *Actions → (execução) → Artifacts*:
`build-logs` (sempre; abra aqui para ver erros de compilação), `FloorPlanScanner-unsigned-ipa`, `FloorPlanScanner-signed-ipa`.

> Compilar com sucesso no CI **não** valida a captura: RoomPlan precisa de LiDAR e só funciona no aparelho.

## Como instalar no iPhone

- **`.ipa` sem assinatura:** o iOS não instala direto. É preciso reassinar com seu Apple ID, por exemplo com
  AltStore ou Sideloadly (ferramentas de terceiros; o perfil gratuito expira em 7 dias).
- **`.ipa` assinado (job `signed-ipa`):** instale pelo Apple Configurator, Xcode (*Devices*) ou ferramenta MDM.
  O UDID do seu iPhone precisa estar no perfil de provisionamento.

## Configurar a assinatura (só para o job `signed-ipa`)

1. No Apple Developer: crie um **bundle id** (ex.: `com.seunome.floorplanscanner`), um certificado **Apple Development**
   (exporte como `.p12` com senha) e um **perfil de provisionamento de desenvolvimento** com o UDID do iPhone.
2. Troque `com.example.floorplanscanner` pelo seu bundle id em `project.yml` **e** na chave `provisioningProfiles`
   do `ExportOptions.plist` dentro do workflow (job `signed-ipa`).
3. Em *Settings → Secrets and variables → Actions*, crie:

| Secret | Conteúdo |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | `base64 -i certificado.p12` |
| `P12_PASSWORD` | senha do `.p12` |
| `BUILD_PROVISION_PROFILE_BASE64` | `base64 -i perfil.mobileprovision` |
| `KEYCHAIN_PASSWORD` | qualquer senha temporária |
| `APPLE_TEAM_ID` | Team ID de 10 caracteres |

4. *Run workflow* com **signed = true**.

Os secrets nunca aparecem nos logs. O job `signed-ipa` **não foi executado** (não há credenciais aqui); trate-o como um ponto de partida.
