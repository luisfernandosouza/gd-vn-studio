# Studio

Editor de visual novels: Tauri + React + TypeScript (ADD §2.1, [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

| Pasta | Conteúdo |
|---|---|
| `src/` | Interface (React) |
| `src-tauri/` | Processo nativo (Rust): arquivos, Godot embutido, Git |
| `preview/` | Painel do Preview: ponte com o runtime Web ([Preview Protocol §1.1](../docs/specs/07-preview-protocol.md)) |

Os schemas e os presets não são copiados à mão para cá: o build do Studio os lê de `docs/specs/schemas/` e `docs/specs/presets/` (spec 09 §1 e §1.2).

Ainda vazio. O esqueleto do app e a CI chegam na tarefa M0-05 do backlog.
