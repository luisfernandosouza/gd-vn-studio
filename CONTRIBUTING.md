# Como contribuir

Este é o monorepo do Visual Novel Studio: Studio, runtime, SDKs, CLI e plugins oficiais. Onde cada coisa mora está na [spec 09](docs/specs/09-repositories-and-code-layout.md); este guia resume as regras que valem para todo pull request.

## Onde fica cada coisa

| Pasta | Componente | Tag de release |
|---|---|---|
| [`docs/specs/`](docs/specs/README.md) | Especificações normativas, schemas, presets, exemplos, vetores e ferramentas de referência (Python) | `specs-v<versão>` |
| [`docs/reviews/`](docs/reviews/) | Relatórios de revisão das specs | — |
| [`studio/`](studio/README.md) | Studio (Tauri + React + TypeScript) | `studio-v<versão>` |
| [`runtime/`](runtime/README.md) | Runtime (Godot 4.7.2 + GDScript) | `runtime-v<versão>` |
| [`sdk/runtime/addons/vn_runtime_sdk/`](sdk/runtime/addons/vn_runtime_sdk/) | Runtime SDK (GDScript) | `sdk-runtime-v<versão>` |
| [`sdk/editor/`](sdk/editor/) | Editor SDK (`@vnstudio/editor-sdk`) | `sdk-editor-v<versão>` |
| [`cli/`](cli/README.md) | CLIs `vnstudio` e `vnplugin` (TypeScript, Node) | `cli-v<versão>` |
| [`plugins/`](plugins/README.md) | Plugins oficiais, um projeto de desenvolvimento cada | `plugin-<namespace>-v<versão>` |
| `.github/workflows/` | CI | — |

Cada componente tem SemVer próprio (ADD §10).

## As specs mandam

- As specs em `docs/specs/` são normativas. **DEVE**, **DEVERIA** e **PODE** seguem a RFC 2119. Se o código precisa se afastar de uma spec, o pull request muda a spec junto, ou a mudança na spec entra antes.
- Os critérios de aceite das tarefas do backlog citam as seções das specs. Confira o resultado contra elas antes de pedir revisão.

## Fonte única

- **Schemas:** `docs/specs/schemas/` é a única cópia. Studio, CLI e runtime os leem dali no build; nenhum componente mantém uma cópia editada à mão.
- **Presets:** `docs/specs/presets/` é a fonte. O build do runtime copia para `runtime/vn_runtime/presets/`; a cópia não é editada à mão.
- **Cópias geradas:** `python docs/specs/tools/sync_generated_copies.py` gera `runtime/vn_runtime/presets/` (com as fontes Noto em `fonts/`), `runtime/vn_runtime/licenses/` (MIT do runtime, licença do Godot e OFL das fontes), `studio/src-tauri/resources/specs/` e `cli/schemas/`. Todas ficam fora do Git; `--check` confere por hash, e a workflow `generated-copies.yml` falha se uma cópia divergir da fonte ou entrar no Git. Precisa do `fonttools` na versão de `docs/specs/tools/generated_sources.json`.
- **Exemplo da demo:** `docs/specs/examples/demo-project/` é gerado por `docs/specs/tools/sync_demo_example.py` a partir do [`gd-vn-studio-demo`](https://github.com/luisfernandosouza/gd-vn-studio-demo), no commit de `SOURCE.json`. Uma mudança no exemplo entra primeiro na demo; depois, o pull request deste repositório roda o script com `--update-source` (spec 09 §1.1).

## Sem arte de jogo

O repositório do produto guarda código, specs e dados de teste. Não entra arte, música, voz ou vídeo de jogo, inclusive arte gerada por IA (spec 09 §1.1). Imagem, áudio, vídeo e fontes de arte (`.psd`…) só podem estar em:

- `runtime/tests/fixtures/`: placeholders de teste feitos à mão, sem arte gerada por IA. Prefira gerar os assets de teste por script na CI (cores sólidas, formas, tons sintéticos);
- `plugins/*/vn_plugins/*/runtime/`: assets originais de cada plugin oficial, com a licença declarada no plugin;
- `plugins/*/sandbox/`: a cena de teste do projeto de desenvolvimento de um plugin oficial.

A workflow `repo-hygiene.yml` confere isso em todo pull request. Um teste que precisa de arte de verdade é um teste de ponta a ponta que clona a demo numa versão fixa.

## O que nunca vai para um artefato

Nada que serve só para desenvolver o produto chega a quem instala o Studio, o runtime, o SDK ou um plugin oficial (spec 09 §1.2): `tests/` e `*/tests/*`, `docs/` como pasta (só os schemas e presets, copiados pelo build), `spikes/`, os `.md` (salvo o `README.md` e o `CHANGELOG.md` que o `.vnplugin` exige) e qualquer arquivo da demo.

## Fora do Git

O [`.gitignore`](.gitignore) da raiz deixa de fora, entre outros, `runtime/vn_content/` e `runtime/vn_plugins/` (gerados por `compile_bundle.py --godot`, Runtime Spec §2.1), as pastas `.godot/`, o `addons/vn_runtime_sdk/` restaurado nos projetos de plugin, `.vnplugin/local.json`, os pacotes `*.vnplugin` e `node_modules/`.

## Antes de abrir o pull request

- Um pull request por tarefa do backlog, que fecha a issue (`Closes #<n>`). Fique na pasta da tarefa: duas tarefas da mesma onda não deveriam mexer no mesmo arquivo. Mudar uma interface compartilhada é um pull request próprio.
- Se tocou em `docs/specs/`, rode as ferramentas de referência (Python 3 e `jsonschema>=4.18`), as mesmas da workflow `specs.yml`:

  ```bash
  cd docs/specs
  python3 tools/validate.py examples/demo-project examples/fishing-plugin
  python3 tools/test_validate.py
  python3 tools/test_schemas.py
  python3 tools/conformance.py
  python3 tools/test_compile.py
  ```

- A CI precisa estar verde. A licença do repositório é a [MIT](LICENSE); ao contribuir, você licencia o seu código nos mesmos termos.
