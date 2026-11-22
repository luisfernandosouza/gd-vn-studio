# Runtime

Runtime das visual novels: projeto Godot 4.7.2 + GDScript ([Runtime Spec](../docs/specs/02-narrative-runtime-specification.md), [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

| Caminho | Conteúdo |
|---|---|
| `project.godot` | Projeto Godot (tarefa M0-02) |
| `vn_runtime/` | Narrative Engine, Scheduler, State Manager, UI Manager… |
| `vn_runtime/presets/` | Cópia gerada de `docs/specs/presets/` + fontes embutidas; nunca editada à mão (tarefa M0-03) |
| `vn_runtime/licenses/` | Licenças do runtime, do Godot e das fontes do preset ([Build System §4.5](../docs/specs/05-build-system-specification.md)) |
| `tests/` | Testes e runner headless dos vetores (`--vn-test`) |
| `tests/fixtures/` | Placeholders de teste feitos à mão: a única pasta do runtime onde pode haver mídia (spec 09 §1.1) |

## Rodar sem o Studio

`runtime/vn_content/` e `runtime/vn_plugins/` ficam fora do Git. Para preenchê-las com a demo ([Runtime Spec §2.1](../docs/specs/02-narrative-runtime-specification.md)):

```bash
python3 docs/specs/tools/compile_bundle.py ../gd-vn-studio-demo --godot runtime docs/specs/examples/fishing-plugin
```

O script exige `runtime/project.godot` (tarefa M0-02). Depois é só abrir `runtime/` no editor do Godot 4.7.2 e rodar (F5). Quando o plugin oficial existir, a pasta do plugin passa a ser `plugins/fishing/vn_plugins/fishing`.

Nada de `tests/`, `docs/` ou `.md` entra nos templates de exportação nem no `runtime-preview.pck` (spec 09 §1.2).
