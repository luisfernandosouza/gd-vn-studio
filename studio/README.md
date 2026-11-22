# Studio

Editor de visual novels: Tauri 2 + React + TypeScript (ADD §2.1, [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

| Pasta | Conteúdo |
|---|---|
| `src/` | Interface (React) |
| `src-tauri/` | Processo nativo (Rust): arquivos, Godot embutido, Git |
| `preview/` | Painel do Preview: ponte com o runtime Web ([Preview Protocol §1.1](../docs/specs/07-preview-protocol.md)) |
| `scripts/` | Scripts do build (ícones gerados) |

Os schemas e os presets não são copiados à mão para cá: o build do Studio os lê de `docs/specs/schemas/` e `docs/specs/presets/` (spec 09 §1 e §1.2).

## Bibliotecas

Só as aceitas no [README das specs](../docs/specs/README.md) (2026-11-14): React Flow, Zustand + Immer, Ajv, CodeMirror/Monaco. O esqueleto já usa Zustand + Immer para o estado (`src/state/`); as outras entram com as tarefas que precisam delas.

## Desenvolvimento

Precisa de Node 22 e Rust estável, mais as [dependências do Tauri](https://v2.tauri.app/start/prerequisites/) do sistema (no Linux, WebKitGTK 4.1).

```bash
cd studio
npm ci
npm run tauri dev        # app com recarga da interface
npm run lint             # ESLint
npm run typecheck        # TypeScript
npm test                 # testes unitários (Vitest)
npm run tauri build      # build de release
```

Os ícones do app ficam fora do Git, porque o repositório não guarda imagens fora das pastas da spec 09 §1.1. `npm run icons` gera um ícone provisório de cor sólida em `src-tauri/icons/`; o `tauri dev` e o `tauri build` já chamam o script.

## CI

A workflow [`studio.yml`](../.github/workflows/studio.yml) roda lint, typecheck e testes, e faz o build no Windows, no macOS e no Linux. Em cada sistema ela abre o app com `VNSTUDIO_SMOKE_TEST=1`: a janela abre, a interface monta e avisa o processo nativo (comando `app_ready`), e o app sai com 0. Se a interface não montar em 90 segundos, o app sai com erro (`src-tauri/src/smoke.rs`).
