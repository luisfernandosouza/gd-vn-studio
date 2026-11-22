# SDKs de plugins

Os dois SDKs para quem escreve minijogos ([Plugin SDK](../docs/specs/03-plugin-sdk-specification.md), [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

| Pasta | Conteúdo | Tag | Publicado em |
|---|---|---|---|
| `runtime/addons/vn_runtime_sdk/` | Runtime SDK (GDScript), copiado para os projetos de plugin por `vnplugin doctor --fix` | `sdk-runtime-v<versão>` | Release (zip do addon) |
| `editor/` | Editor SDK (`@vnstudio/editor-sdk`) | `sdk-editor-v<versão>` | npm |

Ainda vazio. O addon chega com as tarefas M3-02 e M3-03 do backlog, e o Editor SDK com o workspace TypeScript (M0-06).
