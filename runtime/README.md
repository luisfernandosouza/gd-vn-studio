# Runtime

Runtime das visual novels: projeto Godot 4.7.2 + GDScript ([Runtime Spec](../docs/specs/02-narrative-runtime-specification.md), [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

| Caminho | Conteúdo |
|---|---|
| `project.godot` | Projeto Godot: resolução base 1920×1080, `stretch_mode = canvas_items`, `stretch_aspect = expand` (RT §1.1), ações de input `vn_*` (RT §10.1), cena principal `res://vn_runtime/boot.tscn`. No build, o Build System gera um `project.godot` novo a partir deste (BS §4.3) |
| `vn_runtime/boot.tscn` | Cena de boot (por enquanto vazia; o boot do RT §3.0 entra com o Narrative Engine) |
| `vn_runtime/` | Narrative Engine, Scheduler, State Manager, UI Manager… |
| `vn_runtime/presets/` | Cópia gerada de `docs/specs/presets/` + fontes embutidas em `fonts/` (os ids `preset/font_*`); fora do Git e nunca editada à mão |
| `vn_runtime/licenses/` | Gerada: licenças do runtime (MIT), do Godot e das bibliotecas dele, e a OFL de cada fonte do preset, com o índice `index.json` ([Build System §4.5](../docs/specs/05-build-system-specification.md)); fora do Git |
| `tests/` | Testes e runner headless dos vetores (`--vn-test`) |
| `tests/fixtures/` | Placeholders de teste feitos à mão: a única pasta do runtime onde pode haver mídia (spec 09 §1.1) |

## Presets, fontes e licenças

`vn_runtime/presets/` e `vn_runtime/licenses/` são gerados a partir de `docs/specs/` (spec 09 §1 e §1.2):

```bash
python -m pip install fonttools==4.60.1
python3 docs/specs/tools/sync_generated_copies.py runtime           # gera (baixa as fontes uma vez, para o cache)
python3 docs/specs/tools/sync_generated_copies.py --check runtime   # confere por hash, sem rede
```

As fontes Noto (Sans, JP, SC, TC, KR) vêm do `google/fonts` num commit fixo e viram fontes estáticas Regular; os commits, URLs e hashes ficam em `docs/specs/tools/generated_sources.json`. Para mudar um preset, edite `docs/specs/presets/` e rode o script de novo.

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
```

A workflow [`runtime.yml`](../.github/workflows/runtime.yml) roda esses dois comandos em todo pull request que toca `runtime/`.

As ações `vn_*` em `project.godot` seguem a tabela do RT §10.1. Para mudar uma ação, edite pelo editor do Godot (Projeto → Configurações do Projeto → Mapa de Entrada) e mantenha `device = -1` (todos os dispositivos).
