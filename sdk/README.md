# SDKs de plugins

Os dois SDKs para quem escreve minijogos ([Plugin SDK](../docs/specs/03-plugin-sdk-specification.md), [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

| Pasta | Conteúdo | Tag | Publicado em |
|---|---|---|---|
| `runtime/addons/vn_runtime_sdk/` | Runtime SDK (GDScript), copiado para os projetos de plugin por `vnplugin doctor --fix` | `sdk-runtime-v<versão>` | Release (zip do addon) |
| `editor/` | Editor SDK (`@vnstudio/editor-sdk`) | `sdk-editor-v<versão>` | npm |
| `plugin-schema/` | Tipos TypeScript gerados de `docs/specs/schemas/` (`@vnstudio/plugin-schema`, Plugin SDK §10) | `sdk-editor-v<versão>` | npm, com o Editor SDK |

O addon chega com as tarefas M3-02 e M3-03 do backlog (a M3-03 completa os serviços; a ponte ganhou os métodos de idioma, tema, modo stream, personagens, assets, áudio, overlays e RNG). `editor/` e `plugin-schema/` são pacotes do workspace npm da raiz (M0-06): o Editor SDK ainda é um esqueleto, completado na tarefa M7-04.

## Runtime SDK (`runtime/addons/vn_runtime_sdk/`)

O addon não depende de nenhuma classe do runtime, porque é copiado sozinho para os projetos de plugin. As fachadas que o plugin vê falam só com uma `VNPluginBridge` (uma por plugin), que o Plugin Host do runtime implementa sobre os módulos do M0-07 (M3-01) e que o `VNTestHarness` imita (M3-07).

| Classe | Spec | Estado |
|---|---|---|
| `VNRuntimePlugin` (`Node`) | SDK §5.1 | ciclo de vida completo (métodos virtuais) |
| `VNPluginContext` | SDK §5.2 | todos os campos; `VNPluginContext.create(bridge, id, namespace, config)` |
| `VNNarrativeAPI`, `VNVariableAPI`, `VNTransaction` | SDK §5.3 | M3-02 |
| `VNEventAPI` | SDK §5.4 | M3-02 |
| `VNSceneAPI` | SDK §5.5 | M3-02 |
| `VNActivityHandle` | SDK §6 | `complete`/`fail` uma vez, `close()` do host; o resto em M3-04 |
| `VNResult`, `VNRuntimeSDK` (capacidades, códigos de erro, `~chave`) | RT §6.3, SDK §4.2 | M3-02 |
| `VNLogger` | SDK §5.2 | M3-02 |
| `VNRandom` | SDK §5.6; RT §12.2 | M3-03: o fluxo vem da ponte (`create_rng`); com `reproducible_rng` o host passa o PCG32 do runtime (M1-08), o SDK não duplica o gerador |
| `VNCharacterAPI`, `VNAssetAPI`, `VNAudioAPI`, `VNSound`, `VNUIAPI`, `VNI18nAPI`, `VNThemeInfo`, `ctx.content_filter` | SDK §5.6–§5.7; RT §5.5 | M3-03 |
| `VNProfileAPI` | SDK §9.1 | assinaturas; implementação em M3-06 |

Regras das fachadas: toda chamada confere a thread principal (`WRONG_THREAD`, RT §6.1) e a capacidade (Plugin SDK §4.2). Sem capacidade, o serviço não faz nada: `PERMISSION_DENIED` nos métodos com `VNResult`, `fallback`/`false`/`0`/vazio nos outros, e a ponte recebe `permission_denied(capability, call)`. Variáveis do próprio namespace não precisam de capacidade. A permissão de **escrita** é conferida pelo State Manager na verificação 6 do RT §6.2, para que `VARIABLE_NOT_FOUND` e `READ_ONLY` venham antes; a fachada só avisa a ponte quando o resultado é `PERMISSION_DENIED`.

Dois nomes diferem do texto original da spec, que foi corrigida junto: `ctx.plugin_namespace` (`namespace` é palavra reservada do GDScript) e `VNTransaction.set_value` (`Object.set` é nativo e não pode ser sobrescrito).

`VNResult` existe também em `runtime/vn_runtime/core/vn_result.gd` (M0-07), com os mesmos campos. Quando o addon entrar no projeto do runtime (integração), a cópia de `core/` sai.

### Testes

`sdk/runtime/` é um projeto Godot só de teste (a release empacota apenas o addon):

```bash
godot --headless --path sdk/runtime --import
godot --headless --path sdk/runtime --script res://tests/run_tests.gd
```

A workflow [`sdk-runtime.yml`](../.github/workflows/sdk-runtime.yml) roda esses testes e confere que os plugins de exemplo das specs (`fishing-plugin` e o `probe` das fixtures) carregam com o addon.
