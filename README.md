# gd-vn-studio

Visual Novel Studio: um editor externo (Tauri + React + TypeScript) para criar visual novels com narrativa dinâmica, um runtime em Godot 4.7.2 + GDScript e um sistema de minijogos por plugins.

Por enquanto o repositório contém as especificações. O layout completo do monorepo (Studio, runtime, SDK, CLI e plugins oficiais) está na [spec 09](docs/specs/09-repositories-and-code-layout.md).

| Pasta | Conteúdo |
|---|---|
| [`docs/specs/`](docs/specs/README.md) | Especificações normativas, JSON Schemas, exemplos, vetores de conformidade e ferramentas de referência |
| [`docs/reviews/`](docs/reviews/) | Relatórios de revisão das especificações |

Conferências de referência (Python 3):

```bash
cd docs/specs
python3 tools/validate.py examples/demo-project examples/fishing-plugin   # validador
python3 tools/test_validate.py                     # casos do validador
python3 tools/conformance.py                       # vetores de conformidade
python3 tools/compile_bundle.py examples/demo-project /tmp/bundle examples/fishing-plugin   # bundle que o runtime lê
```

O jogo de exemplo jogável fica em [`gd-vn-studio-demo`](https://github.com/luisfernandosouza/gd-vn-studio-demo). Para rodá-lo no editor do Godot quando o runtime existir, veja a [Runtime Spec §2.1](docs/specs/02-narrative-runtime-specification.md).
