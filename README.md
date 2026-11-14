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
```
