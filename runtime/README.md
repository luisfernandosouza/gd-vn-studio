# Runtime

Runtime das visual novels: projeto Godot 4.7.2 + GDScript ([Runtime Spec](../docs/specs/02-narrative-runtime-specification.md), [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

| Caminho | Conteúdo |
|---|---|
| `project.godot` | Projeto Godot: resolução base 1920×1080, `stretch_mode = canvas_items`, `stretch_aspect = expand` (RT §1.1), ações de input `vn_*` (RT §10.1), cena principal `res://vn_runtime/boot.tscn`. No build, o Build System gera um `project.godot` novo a partir deste (BS §4.3) |
| `vn_runtime/boot.tscn`, `boot.gd` | Cena de boot: despacha `--vn-test`, lê `--vn-bundle` e `--vn-fakes` e roda o boot do RT §3.0 (ver [Boot](#boot)) |
| `vn_runtime/boot/` | Boot (M2-01): leitor do bundle em JSON e `.vnb`, JSON canônico (JCS), constantes do build, sequência do RT §3.0 e tela dos erros fatais G001/G002 |
| `vn_runtime/sets/` | Sets compostos e hotspots cosméticos (M2-08): `VNSetView` (camadas, estados, animação, parallax, ações cosméticas) e `VNSetHotspot`; usados pelo UI Manager (fundo das telas) e pelo Stage (fundo das cenas). Testes: `godot --headless --path runtime --script res://tests/sets/test_sets.gd` |
| `vn_runtime/` | Narrative Engine (`narrative_engine/`, ver [Narrative Engine](#narrative-engine)), Scheduler, State Manager, UI Manager… |
| `vn_runtime/presets/` | Cópia gerada de `docs/specs/presets/` + fontes embutidas em `fonts/` (os ids `preset/font_*`); fora do Git e nunca editada à mão |
| `vn_runtime/licenses/` | Gerada: licenças do runtime (MIT), do Godot e das bibliotecas dele, e a OFL de cada fonte do preset, com o índice `index.json` ([Build System §4.5](../docs/specs/05-build-system-specification.md)); fora do Git |
| `tests/` | Testes e runner headless dos vetores (`--vn-test`) |
| `tests/vn_test_runner.gd` | Executor dos vetores de conformidade (RT §12, spec 08 §4) |
| `tests/conformance/` | Peças do executor: leitor de JSON que preserva inteiros, comparação, montagem do estado mínimo (`VNCaseModules`), um adaptador por `kind` em `adapters/` e o autoteste `test_runner.gd` |
| `tests/fixtures/` | Bundles de teste com imagens e sons sintéticos, gerados por `python3 runtime/tests/fixtures/generate.py` ([README](tests/fixtures/README.md)), e placeholders feitos à mão: a única pasta do runtime onde pode haver mídia (spec 09 §1.1) |

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
godot --headless --path runtime -- --vn-test docs/specs/conformance   # vetores de conformidade (RT §12)
```

O executor aceita a pasta `docs/specs/conformance/` (os `*.json` do primeiro nível), um arquivo dela ou `<arquivo>#<id>` para um caso só; caminho relativo é relativo à pasta de onde o Godot foi chamado. Imprime `FALHOU <arquivo>#<id>` com o esperado e o obtido para cada falha, o resumo `N/M` (passaram/executados) e os pulados por motivo, e sai com 0 sem falhas, 1 com falha e 2 com erro de uso. Só existe no runtime de debug: `tests/` não entra nos templates de exportação (spec 09 §1.2).

### Como o executor monta cada caso (M1-01)

- **Números.** O `JSON` do Godot lê todo número como `float` (e erra o último bit de alguns); o executor usa `VNCaseJson`, que lê os `float` com arredondamento correto (`VNCanonicalJson.parse_number`) e devolve `int` para literais sem fração nem expoente, porque `2` e `2.0` têm tipos diferentes nos vetores (spec 08 §2.1). A comparação segue a de `tools/conformance.py`: float confere com número por valor, inteiro com inteiro, booleano nunca é número.
- **Módulos reais.** Toda classe com `class_name`, não abstrata, em `vn_runtime/`, que estende um contrato do M0-07 é a implementação real dele (`VNCaseModules.discover()`). O executor monta um `VNModules` com os dublês e põe os reais por cima, e o cabeçalho da saída diz quais achou. Quem implementa um módulo não mexe no executor: os casos que dependem dele deixam de ser pulados sozinhos.
- **Estado mínimo.** Um bundle mínimo com os padrões do compilador (variáveis do caso como `VariableDefinition`, capítulo e cenas com `scheduler`, `completion`, `scheduling` e `start` resolvidos) vai para `load_bundle()` de todos os módulos; depois `reset_game()` e os valores do caso. O Narrative Engine fica dublê nos casos sem cena inteira, só para dar capítulo e fase.
- **Pulados.** Um caso é pulado, nunca passado, quando falta a implementação real de um módulo de que ele depende:

  | `kind` | Chama | Pulado até |
  |---|---|---|
  | `expression`, `condition` | `VNConditionEvaluator` | (implementado: `VNConditionEvaluatorImpl`, M1-03; as condições completas são do M1-04) |
  | `effects` | `VNStateManager.apply_effects()` (com o Condition Evaluator); com erro, confere também que nada mudou | M1-06 |
  | `selection` | `VNSceneScheduler.select()` (com o Condition Evaluator) | M1-10; o caso `weighted` também espera o contrato do estado do RNG (M1-08) |
  | `flow` | Narrative Engine e o traço da spec 07 §4.2 | M1-12 (integração do núcleo) |
  | `canonical`, `hmac` | `VNCanonicalJson` (`vn_runtime/save_manager/`), sem depender de módulo | nunca pulado (M2-10) |
  | `text`, `rng`, `record` | sem contrato no M0-07 | M1-07, M1-08, M3-06: a tarefa cria o adaptador dela em `tests/conformance/adapters/` e tira o `kind` de `pending_adapter.gd` |

  Um `kind` sem adaptador é falha, não pulado: caso novo só entra com o executor pronto para ele (spec 08 §4).

O autoteste do executor confere a leitura dos números, a comparação, a descoberta dos módulos, o formato da saída e os códigos de saída, e liga os dublês como se fossem reais para exercitar cada adaptador:

```bash
godot --headless --path runtime --script res://tests/conformance/test_runner.gd
```

A workflow [`runtime.yml`](../.github/workflows/runtime.yml) roda esses três comandos e o autoteste do executor, com o Godot em cache, e a referência `tools/conformance.py` em todo pull request que toca `runtime/` ou `docs/specs/conformance/` (spec 08 §4). O job `web` da mesma workflow roda o runner Web (abaixo).

### Export Web e runner Web dos vetores (M4-03)

`export_presets.cfg` tem dois presets Web, os dois sem threads (`variant/thread_support=false`, BS §7.3, para rodar sem COOP/COEP):

| Preset | Para quê |
|---|---|
| `Web` | O runtime do painel do Preview (spec 09 §1): `exclude_filter` do produto (`tests/*, */tests/*, docs/*, *.md`, spec 09 §1.2), sem o executor de testes |
| `Web (vetores)` | O mesmo runtime **com** `tests/`, só para o runner Web dos vetores (spec 08 §4); nunca é distribuído |

```bash
python3 runtime/tests/web/fetch_web_templates.py 4.7.2-stable   # só os templates Web (~20 MB, em vez dos 1,3 GB do .tpz)
godot --headless --path runtime --export-debug "Web (vetores)" ../build/runtime-web-vectors/index.html
node runtime/tests/web/run_web_vectors.cjs build/runtime-web-vectors docs/specs/conformance   # precisa do pacote npm `playwright`
```

O runner sobe um servidor local, abre o export num Chromium headless do Playwright, passa os arquivos de casos para o sistema de arquivos em memória do motor e chama o mesmo `--vn-test` do nativo (áudio `Dummy`, porque o headless não tem `AudioWorklet`). Imprime o mesmo `FALHOU …`/`N/M` e sai com 0, 1 ou 2 como o nativo (3 se o runtime Web não chegou ao fim; `VN_WEB_TIMEOUT_MS` muda o limite de 300 s). A CI compara o resumo e os pulados dos dois runners e falha se diferirem.

As ações `vn_*` em `project.godot` seguem a tabela do RT §10.1. Para mudar uma ação, edite pelo editor do Godot (Projeto → Configurações do Projeto → Mapa de Entrada) e mantenha `device = -1` (todos os dispositivos).

## Boot

`vn_runtime/boot/` implementa o RT §3.0 sobre o registro `VNModules`:

| Arquivo | Classe | O que faz |
|---|---|---|
| `vn_canonical_json.gd` | `VNCanonicalJSON` | JCS (RFC 8785), `content_hash`, SHA-256 em SRI e o HMAC de saves e perfil (BS §5.1, §8.3). Conferido por `conformance/canonical.json` e por `tests/boot/numbers.json` |
| `vn_build_config.gd` | `VNBuildConfig` | Constantes de `res://vn_runtime/build_config.gd` (BS §4.4); sem ele, os padrões de desenvolvimento e a chave de debug |
| `vn_bundle_loader.gd` | `VNBundleLoader` | Lê `res://vn_content/` ou a pasta de `--vn-bundle`: a forma canônica em JSON (só debug e editor) ou os `.vnb` (zstd, AES-256-CBC), confere `format_version`, hashes e caminhos de asset; erros G001/G002 |
| `vn_boot.gd` | `VNBoot` | Os passos 1 a 6: settings, bundle, idioma, perfil (G006 no título), plugins, `sys.locale`/`sys.ui.*`, pergunta da primeira abertura e título. Repassa o modo stream, os volumes e o modo de tela quando a configuração muda |
| `vn_boot_messages.gd`, `vn_fatal_screen.gd` | `VNBootMessages`, `VNFatalScreen` | Mensagens `runtime/message/g00N` e a tela do erro fatal, sem tema nem UI Manager |

Enquanto os módulos reais não existem (integrações M1-12 e M2-16), o boot sem opções só lê e confere o bundle. Com `--vn-fakes` (debug, com `tests/`), ele usa os dublês e chega ao título:

```bash
python3 runtime/tests/fixtures/generate.py
godot --headless --path runtime --import
godot --headless --path runtime --script res://tests/boot/test_boot.gd
godot --headless --path runtime --quit -- --vn-fakes --vn-bundle res://tests/fixtures/bundles/dialogue/
```

A workflow [`runtime-boot.yml`](../.github/workflows/runtime-boot.yml) roda esses comandos. O leitor de JSON do Godot pode errar o último bit de números com mais de 17 dígitos; por isso o `content_hash` é conferido sobre o texto do bundle (que o compilador grava já canônico) e só cai no JCS dos valores quando o texto não está na forma canônica.

## Narrative Engine

`vn_runtime/narrative_engine/vn_runtime_narrative_engine.gd` (`VNRuntimeNarrativeEngine`, M1-11) implementa o contrato `VNNarrativeEngine`: ciclo de vida (RT §3.1–§3.4), laço de nós (§5.2), atividades de plugin (§5.3) e fim de cena (§5.4). Escreve só pelo State Manager, escolhe cenas só pelo Scheduler e é dirigido pelos sinais do Stage (`advanced`, `option_selected`) e do Plugin Host (`activity_ended`); o `bind()` liga esses sinais. Nós: `line`, `choice`, `interact`, `effects`, `branch`, `jump`, `emit`, `plugin`, `wait`, `end` e os de palco (`background`, `show`, `hide`, `audio`), que só repassam ao Stage e ao Audio Manager.

```bash
godot --headless --path runtime --script res://tests/narrative_engine/test_narrative_engine.gd
```

Os testes usam o Engine real com os dublês dos outros módulos; os casos `flow.json` reais fecham no M1-12. O texto das cenas vem do próprio nó (idioma-fonte); `set_locale(locale, strings)` entrega as traduções por caminho de texto. A workflow [`runtime-narrative-engine.yml`](../.github/workflows/runtime-narrative-engine.yml) roda os testes.

## Contratos dos módulos

Cada módulo da tabela do RT §1 tem uma classe base abstrata (`@abstract`) em `vn_runtime/<módulo>/`, só com assinaturas, sinais e documentação, e um dublê em `tests/fakes/<módulo>/` (tarefa M0-07). Uma tarefa implementa o seu módulo estendendo a classe base, na pasta dele, e testa contra os dublês dos outros; as tarefas de integração (M1-12, M2-16) trocam os dublês pelos módulos reais.

| Módulo (RT §1) | Contrato | Dublê | Campo em `VNModules` | Tarefas |
|---|---|---|---|---|
| Narrative Engine | `narrative_engine/vn_narrative_engine.gd` (`VNNarrativeEngine`) | `FakeNarrativeEngine` | `engine` | M1-11, M3-04 |
| Scene Scheduler | `scheduler/vn_scene_scheduler.gd` (`VNSceneScheduler`) | `FakeSceneScheduler` | `scheduler` | M1-10 |
| Condition Evaluator | `condition_evaluator/vn_condition_evaluator.gd` (`VNConditionEvaluator`, `VNEvalResult`) | `FakeConditionEvaluator` | `conditions` | M1-02, M1-03, M1-04 |
| State Manager | `state_manager/vn_state_manager.gd` (`VNStateManager`, `VNStateTransaction`) | `FakeStateManager` | `state` | M1-06 |
| Variable Manager | `variable_manager/vn_variable_manager.gd` (`VNVariableManager`) | `FakeVariableManager` | `variables` | M1-05 |
| Event Bus | `event_bus/vn_event_bus.gd` (`VNEventBus`) | `FakeEventBus` | `events` | M1-09 |
| Plugin Host | `plugin_host/vn_plugin_host.gd` (`VNPluginHost`) | `FakePluginHost` | `plugins` | M3-01, M3-04, M3-05 |
| Save Manager | `save_manager/vn_save_manager.gd` (`VNSaveManager`) | `FakeSaveManager` | `saves` | M2-10, M2-11, M2-13, M3-06 |
| `VNStorage` (RT §8.5) | `storage/vn_storage.gd` (`VNStorage`) | `FakeStorage` | `storage` | M2-10, M4-08 |
| Stage | `stage/vn_stage.gd` (`VNStage`) | `FakeStage` | `stage` | M2-02, M2-03, M2-04, M2-08, M2-12 |
| Stage: áudio | `audio/vn_audio_manager.gd` (`VNAudioManager`) | `FakeAudioManager` | `audio` | M2-05, M2-12 |
| UI Manager | `ui_manager/vn_ui_manager.gd` (`VNUIManager`) | `FakeUIManager` | `ui` | M2-06, M2-07, M2-09, M2-11, M2-15 |
| `VNAssets` (PP §1.3) | `assets/vn_assets.gd` (`VNAssets`) | `FakeAssets` | `assets` | M4-07 |

O Audio Manager faz parte do Stage no RT §1 ("Stage (UI/Audio/Asset Manager)"), mas tem contrato e pasta próprios porque M2-02 e M2-05 andam na mesma onda.

Tipos compartilhados, em `vn_runtime/core/`:

- `VNModule`: base de todos os contratos (`module_id()`, `load_bundle()`, `attach()`/`detach()` para os módulos que desenham). Todos são `RefCounted`, inclusive os que desenham, que recebem o nó por `attach()`; assim os módulos lógicos testam sem árvore de cena.
- `VNModules`: o registro. Um módulo chama outro por `modules().state`, `modules().events`… e guarda só uma referência fraca ao registro.
- `VNResult` (RT §6.3), `VNErrors` (códigos e ordem das verificações do RT §6.2), `VNLayers` (camadas do RT §1.1) e `VNPhase` (estados do RT §3, iguais ao `phase` do protocolo do Preview).

Nos testes, `VNFakeModules.create()` devolve um registro só com dublês; troque o módulo em teste e chame `bind_all()`:

```gdscript
var m := VNFakeModules.create()
m.state = MyStateManager.new()
m.bind_all()
```

Os dublês ficam em `tests/` e nunca são usados pelo código de `vn_runtime/`, então não entram em nenhum artefato (spec 09 §1.2). O teste de fumaça confere que cada dublê cumpre o contrato e que os dublês funcionam juntos:

```bash
godot --headless --path runtime --script res://tests/contracts/test_contracts.gd
```

A workflow [`runtime-contracts.yml`](../.github/workflows/runtime-contracts.yml) roda esse teste em todo pull request que toca `runtime/vn_runtime/` ou `runtime/tests/`.

**Mudar um contrato** (a assinatura, um sinal ou uma constante de um arquivo de contrato ou de `core/`) é um pull request próprio, que atualiza o dublê e o teste de fumaça juntos e avisa as tarefas em andamento que usam o módulo. Uma tarefa que implementa um módulo não muda o contrato dele no mesmo pull request.

## Tipos e valores (M1-02)

`vn_runtime/condition_evaluator/vn_value.gd` (`VNValue`) implementa a semântica de referência do RT §12.1 e do DM §5.1 e §6.1.1 sobre valores com tipo (`VNEvalResult` com `ok = true`): intervalo de inteiros ±(2^53 − 1) e `OUT_OF_RANGE`, aritmética com divisão e `mod` por zero, `round`/`floor`/`ceil`/`abs`/`min`/`max`/`clamp`, comparação de tipos (`1 = 1.0`, `enum` = `string`), conversão para texto do `concat` e o arredondamento sobre a representação decimal mais curta, base da formatação da interpolação. `vn_decimal.gd` (`VNDecimal`) calcula essa representação mais curta com aritmética exata, porque o `String.num_scientific` do Godot 4.7.2 erra o último dígito em alguns valores.

Testes: `godot --headless --path runtime --script res://tests/condition_evaluator/test_vn_value.gd` (workflow [`runtime-condition-evaluator.yml`](../.github/workflows/runtime-condition-evaluator.yml)).

`VNValue.from_literal` tipa um literal pelo tipo do Godot (`int` → `integer`, `float` → `number`), como o lê o `VNCaseJson` dos vetores. O `JSON` do Godot lê todo número como `float`; para conteúdo lido por ele, `integral_floats = true` faz um `float` com parte fracionária zero dentro do intervalo virar `integer`. Quem conhece o tipo esperado passa `hint`. `VNValue.typed` normaliza o valor de uma variável pelo tipo declarado.
