# SDKs de plugins

Os dois SDKs para quem escreve minijogos ([Plugin SDK](../docs/specs/03-plugin-sdk-specification.md), [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

| Pasta | Conteúdo | Tag | Publicado em |
|---|---|---|---|
| `runtime/addons/vn_runtime_sdk/` | Runtime SDK (GDScript), copiado para os projetos de plugin por `vnplugin doctor --fix` | `sdk-runtime-v<versão>` | Release (zip do addon) |
| `editor/` | Editor SDK (`@vnstudio/editor-sdk`) | `sdk-editor-v<versão>` | npm |
| `plugin-schema/` | Tipos TypeScript gerados de `docs/specs/schemas/` (`@vnstudio/plugin-schema`, Plugin SDK §10) | `sdk-editor-v<versão>` | npm, com o Editor SDK |

O addon chega com as tarefas M3-02 e M3-03 do backlog. `editor/` e `plugin-schema/` são pacotes do workspace npm da raiz (M0-06): o Editor SDK ainda é um esqueleto, completado na tarefa M7-04.
