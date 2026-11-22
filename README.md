# gd-vn-studio

Visual Novel Studio: um editor externo (Tauri + React + TypeScript) para criar visual novels com narrativa dinâmica, um runtime em Godot 4.7.2 + GDScript e um sistema de minijogos por plugins.

O repositório é um monorepo, com o layout da [spec 09](docs/specs/09-repositories-and-code-layout.md). Por enquanto só as especificações têm conteúdo; as pastas dos componentes já existem e vão sendo preenchidas pelas tarefas do backlog da v1.

| Pasta | Conteúdo |
|---|---|
| [`docs/specs/`](docs/specs/README.md) | Especificações normativas, JSON Schemas, presets, exemplos, vetores de conformidade e ferramentas de referência |
| [`docs/reviews/`](docs/reviews/) | Relatórios de revisão das especificações |
| [`studio/`](studio/README.md) | Studio: Tauri + React + TypeScript (`src/`, `src-tauri/`, `preview/`) |
| [`runtime/`](runtime/README.md) | Runtime: projeto Godot 4.7.2 + GDScript (`vn_runtime/`, `tests/`) |
| [`sdk/runtime/addons/vn_runtime_sdk/`](sdk/runtime/addons/vn_runtime_sdk/) | Runtime SDK (GDScript), copiado para os projetos de plugin |
| [`sdk/editor/`](sdk/editor/) | Editor SDK (`@vnstudio/editor-sdk`, npm) |
| [`cli/`](cli/README.md) | CLIs `vnstudio` e `vnplugin` (TypeScript, Node) |
| [`plugins/`](plugins/README.md) | Plugins oficiais (`vnstudio.*`); [`plugins/fishing/`](plugins/fishing/) é o minijogo de pesca |
| [`.github/workflows/`](.github/workflows/) | CI: `specs.yml`, `repo-hygiene.yml` e as dos componentes |

Como contribuir, inclusive onde pode haver mídia e o que fica fora do Git: [CONTRIBUTING.md](CONTRIBUTING.md).

Conferências de referência (Python 3):

```bash
cd docs/specs
python3 tools/validate.py examples/demo-project examples/fishing-plugin   # validador
python3 tools/test_validate.py                     # casos do validador
python3 tools/test_schemas.py                      # padrões dos schemas
python3 tools/conformance.py                       # vetores de conformidade
python3 tools/compile_bundle.py examples/demo-project /tmp/bundle examples/fishing-plugin   # bundle que o runtime lê
```

O jogo de exemplo jogável fica em [`gd-vn-studio-demo`](https://github.com/luisfernandosouza/gd-vn-studio-demo). Para rodá-lo no editor do Godot quando o runtime existir, veja a [Runtime Spec §2.1](docs/specs/02-narrative-runtime-specification.md).
