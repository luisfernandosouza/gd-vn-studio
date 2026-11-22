# Runtime

Runtime das visual novels: projeto Godot 4.7.2 + GDScript ([Runtime Spec](../docs/specs/02-narrative-runtime-specification.md), [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

| Caminho | Conteúdo |
|---|---|
| `project.godot` | Projeto Godot: resolução base 1920×1080, `stretch_mode = canvas_items`, `stretch_aspect = expand` (RT §1.1), ações de input `vn_*` (RT §10.1), cena principal `res://vn_runtime/boot.tscn`. No build, o Build System gera um `project.godot` novo a partir deste (BS §4.3) |
| `vn_runtime/boot.tscn`, `boot.gd` | Cena de boot. Por enquanto só despacha `--vn-test` para o executor de testes; o boot do RT §3.0 entra com o Narrative Engine |
| `vn_runtime/` | Narrative Engine, Scheduler, State Manager, UI Manager… |
| `vn_runtime/presets/` | Cópia gerada de `docs/specs/presets/` + fontes embutidas; nunca editada à mão (tarefa M0-03) |
| `vn_runtime/licenses/` | Licenças do runtime, do Godot e das fontes do preset ([Build System §4.5](../docs/specs/05-build-system-specification.md)) |
| `tests/` | Testes e runner headless dos vetores (`--vn-test`) |
| `tests/vn_test_runner.gd` | Executor dos vetores de conformidade (RT §12, spec 08 §4); por enquanto conta os casos e os dá como pulados (a tarefa M1-01 os executa) |
| `tests/fixtures/` | Placeholders de teste feitos à mão: a única pasta do runtime onde pode haver mídia (spec 09 §1.1) |

## Rodar sem o Studio

`runtime/vn_content/` e `runtime/vn_plugins/` ficam fora do Git. Para preenchê-las com a demo ([Runtime Spec §2.1](../docs/specs/02-narrative-runtime-specification.md)):

```bash
python3 docs/specs/tools/compile_bundle.py ../gd-vn-studio-demo --godot runtime docs/specs/examples/fishing-plugin
```

O script exige `runtime/project.godot`. Depois é só abrir `runtime/` no editor do Godot 4.7.2 e rodar (F5). Quando o plugin oficial existir, a pasta do plugin passa a ser `plugins/fishing/vn_plugins/fishing`.

Nada de `tests/`, `docs/` ou `.md` entra nos templates de exportação nem no `runtime-preview.pck` (spec 09 §1.2).

## Godot e CI

O runtime 1.0 fixa o **Godot 4.7.2** ([Build System §2.1](../docs/specs/05-build-system-specification.md)). O renderizador é o `gl_compatibility`, o único que o export Web aceita (o Preview em painel roda o runtime exportado para Web, RT §11).

```bash
godot --headless --path runtime --import   # importa o projeto (cria runtime/.godot/, fora do Git)
godot --headless --path runtime --quit     # abre e fecha; precisa sair com 0 e sem ERROR no log
godot --headless --path runtime -- --vn-test docs/specs/conformance   # vetores de conformidade (RT §12)
```

O executor aceita a pasta `docs/specs/conformance/` (os `*.json` do primeiro nível) ou um arquivo dela; caminho relativo é relativo à pasta de onde o Godot foi chamado. Imprime `FALHOU <arquivo>#<id>` para cada falha e o resumo `N/M` (passaram/executados) com os pulados, e sai com 0 sem falhas, 1 com falha e 2 com erro de uso. Só existe no runtime de debug: `tests/` não entra nos templates de exportação (spec 09 §1.2).

A workflow [`runtime.yml`](../.github/workflows/runtime.yml) roda esses três comandos, com o Godot em cache, e a referência `tools/conformance.py` em todo pull request que toca `runtime/` ou `docs/specs/conformance/` (spec 08 §4). O runner Web entra com a tarefa M4-03.

As ações `vn_*` em `project.godot` seguem a tabela do RT §10.1. Para mudar uma ação, edite pelo editor do Godot (Projeto → Configurações do Projeto → Mapa de Entrada) e mantenha `device = -1` (todos os dispositivos).
