# Plugin SDK Specification — v1.0.0-draft

- **Status:** rascunho para revisão
- **Base:** Architecture Design Document v0.1, seções 5, 6, 8, 9, 10, 11 e 13.4–13.5; [Narrative Data Model](01-narrative-data-model.md); [Narrative Runtime Specification](02-narrative-runtime-specification.md)
- **Schemas:** [`plugin.schema.json`](schemas/plugin.schema.json) (manifesto), [`plugins.schema.json`](schemas/plugins.schema.json) (concessões do projeto), [`plugin-lock.schema.json`](schemas/plugin-lock.schema.json)
- **Exemplo:** [`examples/fishing-plugin/plugin.json`](examples/fishing-plugin/plugin.json)

Este documento define os contratos entre plugins, Studio e Runtime: formato do pacote, manifesto, modelo de permissões, APIs do Runtime SDK (GDScript) e do Editor SDK (TypeScript), eventos, configuração, saves, compatibilidade, dependências e publicação.

Regra que atravessa tudo: **plugins executam gameplay; o Narrative Engine controla a história** (ADD §6.8). Um plugin só toca a narrativa por três caminhos: atividades chamadas por nós `plugin`, a NarrativeAPI (variáveis, eventos, transações) e pedidos de cena autorizados.

---

## 1. Tipos de plugin

| Tipo (ADD §5.2) | `targets` | Entrypoints obrigatórios |
|---|---|---|
| Editor Extension | `["editor"]` | `editor` |
| Runtime Extension | `["runtime"]` | `runtime` |
| Full Extension | `["editor", "runtime"]` | `editor` e `runtime` |

Uma Runtime Extension sem parte de editor ainda ganha suporte no Studio: o formulário dos `params` de cada atividade e o da `config` são gerados automaticamente a partir dos JSON Schemas do manifesto.

## 2. Pacote `.vnplugin`

### 2.1. Conteúdo

ZIP com a estrutura do ADD §5.3. Regras:

- `plugin.json` DEVE estar na raiz do ZIP (não dentro de uma pasta).
- `editor/dist/` vai no pacote **já compilado**; `editor/src/` vai junto para revisão (distribuição baseada em código-fonte, ADD §5.1). `node_modules/` nunca vai.
- `runtime/` contém GDScript, cenas `.tscn` e assets; nada de binários nativos (GDExtension) no v1, porque eles não podem ser revisados como código-fonte.
- `tests/` e `docs/` são incluídos; o Build System não os copia para o jogo.
- Arquivos do ambiente de desenvolvimento nunca vão no pacote: `project.godot`, `override.cfg`, `.godot/`, `*.import`, `addons/`, `sandbox/`, `.vnplugin/`. O Build System reimporta os assets do plugin no Build Staging.
- Tamanho máximo: 100 MB.

### 2.2. Empacotamento reprodutível

`vnplugin package` gera o mesmo arquivo para a mesma árvore: entradas em ordem lexicográfica, data fixa (1980-01-01), permissões normalizadas, compressão deflate nível 9. Com isso o hash identifica o conteúdo.

### 2.3. Integridade

`integrity` = `sha256-<base64>` do arquivo `.vnplugin` inteiro (formato SRI). Gravado no `plugin-lock.json` e no catálogo. O Studio e o Build System recusam pacote cujo hash difere do lock.

### 2.4. Ambiente de desenvolvimento

O repositório do plugin **é um projeto Godot** que o dev abre direto no editor. O mesmo formato vale para um plugin embutido no repositório de um jogo (`plugins/<nome>/`) e para os plugins oficiais no repositório do produto; onde cada um mora está na spec 09 ([09-repositories-and-code-layout.md](09-repositories-and-code-layout.md)). `vnplugin create` gera:

```text
fishing-plugin/                 # repositório Git = projeto Godot de desenvolvimento
├── project.godot               # gerado; fora do pacote
├── addons/vn_runtime_sdk/      # Runtime SDK na versão de sdk.runtime; fora do pacote
├── sandbox/sandbox.tscn        # roda a atividade com F5; fora do pacote
├── .vnplugin/                  # estado da CLI (versão do Godot, projeto de VN vinculado)
└── vn_plugins/fishing/         # o plugin: só esta pasta vira o .vnplugin
    ├── plugin.json
    ├── README.md, LICENSE, CHANGELOG.md
    ├── runtime/src/, runtime/scenes/, runtime/assets/
    ├── editor/src/, editor/dist/
    ├── tests/runtime/, tests/editor/
    └── docs/
```

- **Caminho fixo.** No jogo exportado, no Preview no Runtime e no ambiente de desenvolvimento o plugin fica em `res://vn_plugins/<namespace>/`. Como o caminho é o mesmo nos três, cenas `.tscn` e `preload` funcionam sem ajuste, e o depurador do Godot acha os scripts (§12.3). Todo caminho `res://` do plugin DEVE começar com `res://vn_plugins/<namespace>/`, `res://vn_plugins/<namespace de uma dependência>/` ou `res://addons/vn_runtime_sdk/`; caminhos relativos são permitidos (P012).
- **Sandbox.** `sandbox.tscn` usa a classe `VNSandbox` do SDK: carrega o plugin sobre uma NarrativeAPI em memória (a mesma do `VNTestHarness`, §12.1) com renderização e input reais, e mostra um painel lateral com o formulário dos `params`, as variáveis, os eventos emitidos, os logs e os botões Pular e Reiniciar. É onde o dev itera com breakpoints, sem abrir o Studio.
- **Versão do Godot.** Cada versão do runtime fixa uma versão **exata** do Godot (a mesma embutida no Studio). `vnplugin doctor` mostra a versão do Studio instalado e a do Godot correspondente; `vnplugin godot install` baixa o editor oficial nessa versão (build padrão, sem .NET), confere o hash e guarda em `~/.vnstudio/godot/<versão>/`; `vnplugin godot open` abre o projeto com ele. `vnplugin test` usa o binário headless da mesma versão. O validador avisa se `compatibility.godot` não inclui a versão fixada pelo runtime de `compatibility.runtime`.
- **Nomes globais do Godot.** `class_name`, grupos e ações de input criadas pelo plugin são globais no jogo. Por isso todo `class_name` DEVE começar com o namespace em PascalCase (`FishingGame` para `fishing`) e grupos e ações com `<namespace>_` (P011). O prefixo `VN` é reservado ao SDK. Plugins não registram autoloads nem alteram configurações do projeto; para input, usam as ações padrão do runtime (§5.7).

## 3. Manifesto `plugin.json`

Schema completo em [`plugin.schema.json`](schemas/plugin.schema.json). Campos:

| Campo | Obrigatório | Descrição |
|---|---|---|
| `manifest_version` | sim | `1` |
| `id` | sim | `<publisher>.<nome>`, global. Publisher `vnstudio` é reservado aos oficiais |
| `namespace` | sim | Prefixo de variáveis, eventos e atividades. Único **no projeto**; `sys`, `story`, `vn`, `global`, `character`, `chapter`, `scene` e `plugin` são reservados (Data Model §3) |
| `name`, `version`, `description` | name, version | `version` em SemVer |
| `default_locale` | sim | Idioma-base dos textos do plugin (§5.7) |
| `author`, `license`, `homepage`, `repository` | license | `license` em SPDX |
| `sdk` | sim | Faixas do Runtime SDK e do Editor SDK usadas; `sdk.runtime` é obrigatório com `targets` `runtime`, e `sdk.editor` com `editor` |
| `compatibility` | sim | Faixas de Studio, Runtime, Godot e Data Model. `runtime` é obrigatório; `studio` e `data_model` ausentes = qualquer versão; `godot` ausente = a versão fixada pelo runtime. `platforms` opcional lista as plataformas testadas (ausente = todas; W008 se o projeto exporta para outra) |
| `targets`, `entrypoints` | sim | §1 |
| `capabilities` | não | Capacidades pedidas (§4.2) |
| `variable_permissions` | não | Variáveis do projeto que pede para ler/escrever; aceita `*` como segmento e `$config.<campo>` (§4.4). Variáveis de outro plugin: só leitura e só com dependência declarada (P017) |
| `variables` | não | Variáveis próprias (`plugin.<ns>.<key>`), formato do Data Model §4.2, sem `access` nem `characters`; `derived` só lê o próprio namespace (P017). DEVERIAM ter `name` e `description` (W007): o autor as vê no Studio como "do plugin *{name}*" |
| `events` | não | `emits` (com schema do payload) e `subscribes` |
| `activities` | não | Atividades para nós `plugin` (§6) |
| `config_schema` | não | JSON Schema da configuração por projeto (§8) |
| `config_migrations` | não | Migrações declarativas da `config` (§8) |
| `save.data_version` | não | Versão do formato dos dados salvos (§9) |
| `dependencies`, `optional_dependencies` | não | `id → faixa SemVer` (§11) |
| `editor` | não | Contribuições declarativas: painéis, comandos, inspetores |

**Namespace x ID.** O ID é global e estável; o namespace é curto e legível no conteúdo (`fishing.completed`, `plugin.fishing.total_caught`). Se dois plugins do mesmo projeto declararem o mesmo namespace, a instalação do segundo falha (P001); por isso o catálogo reserva o namespace no primeiro `published` e recusa outro plugin com o mesmo (§13.2). Renomear namespace é mudança MAJOR do plugin.

## 4. Modelo de permissões

### 4.1. Três camadas

| Camada | Arquivo | Quem decide |
|---|---|---|
| **Pedido** | `plugin.json` (`capabilities`, `variable_permissions`) | Autor do plugin |
| **Concessão** | `plugins.json → grants` | Dono do projeto, no Plugin Manager |
| **Aceite** | `variables.json → access` de cada variável | Dono do projeto, no Variable Manager |

Permissão efetiva = pedido ∩ concessão ∩ aceite. Conceder algo não pedido é erro de validação (P006/P007). O manifesto nunca é barreira de segurança por si só (ADD §6.4): o Runtime e o Studio verificam a permissão efetiva em toda chamada.

Na instalação, o Plugin Manager mostra o pedido em linguagem simples ("Este plugin quer ler e alterar *Dinheiro*") e grava a concessão que o usuário aprovar. É **um único diálogo**: ao aprovar acesso a uma variável cujo `access` não permite, o Studio ajusta também o aceite em `variables.json`, mostrando isso no mesmo diálogo ("*Dinheiro* passará a aceitar alterações de plugins"). O autor nunca precisa visitar o Variable Manager para destravar uma concessão. Atualização que pede permissão nova exige aprovação de novo; até lá a permissão nova não vale.

### 4.2. Capacidades

**Runtime**

| Capacidade | Libera |
|---|---|
| `variables.read` | `variables.get_value`, `has`, observar `state_changed` (só das variáveis legíveis) |
| `variables.write` | `set_value`, `add_value` etc. (só nas variáveis graváveis) |
| `transactions` | `begin_transaction()` |
| `events.emit` | Emitir eventos do próprio namespace |
| `events.subscribe` | Ouvir eventos `sys.*`, `story.*` e de outros plugins |
| `characters.read` | Dados públicos de personagens (nome, cor, expressões) |
| `scenes.request` | `scenes.request(id)` para as cenas listadas em `grants.scenes` |
| `save.data` | Guardar dados próprios no save |
| `profile.data` | Guardar dados próprios e recordes no perfil do jogador, que sobrevivem entre partidas (§9.1) |
| `assets.read` | Carregar assets do projeto por ID |
| `audio.play` | Tocar áudio nos canais `sfx`/`ambient` (música é do Narrative Engine); o runtime para os sons do plugin ao fim de cada atividade |
| `ui.overlay` | Desenhar camada própria sobre o jogo |
| `input.capture` | Receber a entrada do jogador durante atividades, com exclusividade |

**Input sem e com `input.capture`.** Sem a capacidade, a `CanvasLayer` dos overlays do plugin tem `mouse_filter = IGNORE` e o runtime não entrega a ela `_input`/`_unhandled_input`: a UI narrativa continua com o foco. Com a capacidade, durante a atividade o runtime desliga o processamento de input da UI narrativa e entrega tudo à camada do plugin; ao fim da atividade, devolve.

Variáveis do próprio namespace não precisam de capacidade.

**Editor**

| Capacidade | Libera |
|---|---|
| `panels` | Registrar painéis |
| `commands` | Registrar comandos e atalhos |
| `node_inspector` | Inspetor próprio para nós das suas atividades |
| `project.read` | Ler o conteúdo narrativo (cenas, variáveis, personagens) |
| `project.write` | Propor alterações ao conteúdo (sempre via comandos com undo, §10.4) |
| `assets.read` / `assets.write` | Ler / importar assets |
| `notifications` | Mostrar notificações |
| `preview` | Controlar o preview e desenhar no Preview no Studio |
| `network` | Acesso de rede (bloqueado por padrão; só oficiais no v1, P016) |

### 4.3. Confiança

| Nível | Origem | Comportamento |
|---|---|---|
| `official` | Catálogo oficial, publisher `vnstudio` | Instala e executa |
| `reviewed` | Catálogo oficial, plugin externo aprovado na revisão | Instala e executa |
| `local` | `path:` (pacote guardado ou plugin embutido) ou GitHub fora do catálogo | Instala, mas **não executa** até o usuário confirmar explicitamente por projeto (ADD §8.2). A confirmação fica em `.vnstudio/`, por máquina (spec 09 §3.2) |

Runtime plugins rodam no processo do Godot e **não são isolados** (ADD §8.2). A verificação de permissões do SDK protege contra erro, não contra código malicioso; contra isso valem revisão, hash e revogação (§13).

### 4.4. Permissão ligada à configuração

Quando o autor escolhe a variável na configuração ("Variável de dinheiro"), o plugin não sabe o ID de antemão. Nesse caso o pedido usa `$config.<campo>`, e o campo do `config_schema` é declarado com `"format": "vn-variable"` (o Studio mostra um seletor de variáveis, filtrado por `vn-variable-type` se presente):

```json
"config_schema": { "properties": { "currency_variable": { "type": "string", "format": "vn-variable", "vn-variable-type": "integer", "title": "Variável de dinheiro" } } },
"variable_permissions": { "write": ["$config.currency_variable"] }
```

Ao salvar a configuração, o Studio mostra o diálogo de permissão (§4.1) para a variável escolhida e grava a concessão com o ID real (`global.player_money`). Trocar a variável na configuração troca a concessão no mesmo diálogo. O validador resolve `$config.*` com a `config` do projeto antes de checar P007.

**Outros formatos de seletor.** O mesmo mecanismo vale para assets, cenas e personagens, na `config` e nos `params` das atividades:

| `format` | O Studio mostra | O validador confere | Build |
|---|---|---|---|
| `vn-variable` (+ `vn-variable-type`) | Seletor de variáveis | Existência (R005) e concessão (P007) | — |
| `vn-asset` (+ `vn-asset-type`) | Seletor de assets do tipo | Existência (P018) e tipo (W014) | Inclui o asset sem `always_include`. O plugin pode carregar e tocar esse asset sem `assets.read`, porque foi o autor que o escolheu |
| `vn-scene` | Seletor de cenas pelo título | Existência (P018) | — |
| `vn-character` | Seletor de personagens pelo nome | Existência (P018) | — |

Antes de pedir escrita, o autor do plugin DEVERIA preferir devolver o dado no resultado da atividade e oferecer um `suggested_effects` (§6). O plugin de referência faz assim e não pede nenhuma permissão de variável.

## 5. Runtime SDK (GDScript)

Pacote distribuído como addon Godot (`addons/vn_runtime_sdk/`) junto com o runtime. Versão própria em SemVer.

### 5.1. Classe base e ciclo de vida

```gdscript
# runtime/src/fishing_plugin.gd
extends VNRuntimePlugin

func _vn_init(ctx: VNPluginContext) -> void:
    # Chamado uma vez ao carregar o plugin. Registrar ouvintes aqui.
    pass

func _vn_ready() -> void:
    # Bundle narrativo e todos os plugins carregados.
    pass

func _vn_game_started(is_new_game: bool) -> void:
    pass

func _vn_start_activity(activity_id: StringName, params: Dictionary, handle: VNActivityHandle) -> void:
    pass

func _vn_cancel_activity(handle: VNActivityHandle) -> void:
    pass

func _vn_save() -> Variant:                                   # requer save.data
    return {}

func _vn_load(data: Variant) -> void:
    pass

func _vn_migrate_save_data(data: Variant, from_version: int) -> Variant:
    return data

func _vn_migrate_profile_data(data: Variant, from_version: int) -> Variant:   # requer profile.data
    return data

func _vn_game_ended() -> void:
    pass

func _vn_shutdown() -> void:
    pass
```

Ordem garantida: `_vn_init` (todos os plugins, em ordem topológica de dependências; plugins sem dependência entre si seguem a ordem lexicográfica do id, a mesma nos dois interpretadores) → `_vn_ready` (todos) → `_vn_game_started` → … → `_vn_game_ended` → `_vn_shutdown`. Ao carregar save (Runtime Spec §8.3): `_vn_game_ended()` se havia jogo em andamento → `_vn_game_started(false)` → `_vn_migrate_save_data` (se preciso) → `_vn_load(data)`. Se o save não tem dados do plugin, `_vn_load(null)` é chamado mesmo assim, e o plugin DEVE voltar ao estado inicial.

### 5.2. Contexto

```gdscript
class_name VNPluginContext
var plugin_id: StringName          # "vnstudio.fishing"
var namespace: StringName          # "fishing"
var config: Dictionary             # config do projeto, já validada e com defaults
var narrative: VNNarrativeAPI
var characters: VNCharacterAPI     # characters.read
var scenes: VNSceneAPI             # scenes.request
var assets: VNAssetAPI             # assets.read
var audio: VNAudioAPI              # audio.play
var ui: VNUIAPI                    # ui.overlay
var profile: VNProfileAPI          # profile.data (§9.1)
var rng: VNRandom                  # fluxo do plugin fora de atividades; reproduzível só com settings.reproducible_rng (Runtime Spec §12.2). Na atividade, use handle.rng
var i18n: VNI18nAPI                # idioma do jogo e textos runtime/ do plugin (§5.7)
var theme: VNThemeInfo             # aparência do projeto, somente leitura (§5.7)
var log: VNLogger
```

Serviços cuja capacidade não foi concedida existem, mas não fazem nada. Métodos que retornam `VNResult` devolvem `PERMISSION_DENIED`; os demais devolvem `null` (`load_asset`, `push_overlay`, `play`), `fallback` (`get_value`) ou `false` (`has`). Em todos os casos o runtime registra no log do plugin, envia `plugin.permission_denied` ao Studio (Runtime Spec §11) e conta para o estado *faulted*.

### 5.3. NarrativeAPI

```gdscript
class_name VNNarrativeAPI
var variables: VNVariableAPI
var events: VNEventAPI
func begin_transaction() -> VNTransaction

class_name VNVariableAPI
func has(id: String) -> bool
func get_value(id: String, fallback: Variant = null) -> Variant
func get_definition(id: String) -> Dictionary        # tipo, restrições, default (sem valores de outros escopos)
func set_value(id: String, value: Variant) -> VNResult
func add_value(id: String, amount: float) -> VNResult
func subtract_value(id: String, amount: float) -> VNResult
func toggle(id: String) -> VNResult
func reset(id: String) -> VNResult
signal changed(changes: Array[Dictionary])           # só variáveis legíveis pelo plugin

class_name VNTransaction
func set(id: String, value: Variant) -> VNTransaction
func add(id: String, amount: float) -> VNTransaction
func subtract(id: String, amount: float) -> VNTransaction
func toggle(id: String) -> VNTransaction
func reset(id: String) -> VNTransaction
func expect(id: String, value: Variant) -> VNTransaction   # pré-condição (compare-and-set)
func commit() -> VNResult                                  # tudo ou nada
func rollback() -> void
```

IDs são sempre totalmente qualificados (`global.player_money`). Para as variáveis próprias, o SDK aceita o atalho `"~total_caught"` → `plugin.<namespace>.total_caught`.

Exemplo (equivalente ao ADD §6.7):

```gdscript
var tx := ctx.narrative.begin_transaction()
tx.add("global.player_money", 100) \
  .add("~total_caught", fish_count)
var result := tx.commit()
if not result.ok:
    ctx.log.warn("recompensa não aplicada: %s" % result.error)
```

### 5.4. EventAPI

```gdscript
class_name VNEventAPI
func emit(name: String, payload: Dictionary = {}) -> VNResult       # só o próprio namespace
func on(pattern: String, callback: Callable) -> int                  # "story.*", "sys.scene_ended"
func off(subscription_id: int) -> void
# callback: func(name: String, payload: Dictionary, source: String) -> void
```

Semântica de entrega na Runtime Spec §7: enfileirado, FIFO, nunca reentrante.

### 5.5. SceneAPI

```gdscript
class_name VNSceneAPI
func request(scene_id: String) -> VNResult
```

Registra um **pedido** para o próximo ponto de seleção, tratado como `end.then.scene` (Runtime Spec §4.3): aceito só se a cena estiver em `grants.scenes` **e** for elegível ou `manual`. Não interrompe a cena atual. Último pedido antes do ponto de seleção vence; pedidos do conteúdo (`end.then.scene`) têm precedência sobre os de plugins.

### 5.6. Demais serviços

```gdscript
class_name VNCharacterAPI
func get_character(id: String) -> Dictionary     # { id, name (localizado), color, expressions }
func list_characters() -> PackedStringArray

class_name VNAssetAPI
func load_asset(asset_id: String) -> Resource     # assets do projeto; recursos do plugin via res:// normal

class_name VNAudioAPI
func play(asset: String, channel: StringName = &"sfx", volume: float = 1.0) -> VNSound   # ID de asset do projeto (assets.read) ou res://vn_plugins/<ns>/…
func stop_all(fade: float = 0.0) -> void

class_name VNSound
func stop(fade: float = 0.0) -> void
func is_playing() -> bool

class_name VNUIAPI
func push_overlay(scene: PackedScene) -> Node      # camada acima da UI narrativa
func pop_overlay(node: Node) -> void

class_name VNRandom
func randi_range(from: int, to: int) -> int
func randf() -> float
```

### 5.7. Idioma, aparência, input e tempo

```gdscript
class_name VNI18nAPI
var locale: String                                        # idioma atual do jogo, ex.: "pt-BR"
func text(key: String, fallback: String, args: Dictionary = {}) -> String
signal locale_changed(locale: String)

class_name VNThemeInfo
var resolution: Vector2i                                  # project.json → settings.resolution
func font(role: StringName) -> Font                       # &"dialogue", &"name", &"ui" (theme.json → fonts)
func font_size(role: StringName) -> int
func color(role: StringName) -> Color                     # &"text", &"accent", &"panel", &"disabled"
```

- **Textos ao jogador.** Os `args` usam a mesma sintaxe e a mesma formatação da interpolação do projeto (números pela tabela do idioma, `{{` e `}}` para chaves literais; Runtime Spec §12.1); a marcação de texto do Data Model §9.1 também vale. `i18n.text("runtime/hud/fish_count", "Fish: {count}", {"count": 3})` procura, nesta ordem: tradução do projeto (`plugin/<namespace>/runtime/...` nos arquivos de `locales/`), `plugin_locales[locale]` do manifesto, `plugin_locales[default_locale]` e por fim o `fallback` do código. O texto-fonte que vai para a planilha de tradução é o de `plugin_locales[default_locale]`, porque o Studio não lê o código GDScript; por isso toda chave `runtime/` usada no código DEVE estar lá (W016, conferido por `vnplugin validate`). A planilha de tradução do Studio (Req §9) inclui esses textos, então o autor traduz o minijogo para um idioma que o plugin não traz. O nome é `text`, e não `tr`, para não colidir com `Object.tr` do Godot.
- **Aparência.** Overlays são criados numa `CanvasLayer` cujo `Control` raiz cobre a resolução base do projeto, com o mesmo modo de escala do jogo. O minijogo DEVERIA ser desenhado para essa resolução com âncoras, e usar `ctx.theme` para fontes e cores, para não destoar da VN.
- **Input.** O runtime define as ações `vn_*` da tabela fechada do Runtime Spec §10.1 (`vn_confirm`, `vn_cancel`, direções, `vn_advance`, `vn_skip`, `vn_auto`, `vn_hide`, `vn_backlog`, `vn_menu`, `vn_quick_save`, `vn_quick_load`), com teclas, mouse e gamepad padrão. Um minijogo normalmente usa só `vn_confirm`, `vn_cancel` e as direções. Com `input.capture`, o plugin recebe o input durante a atividade. Ações próprias são criadas em `_vn_init` com `InputMap.add_action("<namespace>_...")`.
- **Tempo.** Gameplay DEVE medir tempo pelo `delta` de `_process`/`_physics_process` ou por nós `Timer`, nunca pelo relógio do sistema (`Time.get_ticks_msec`). Assim a pausa do jogo funciona e o `VNTestHarness` pode acelerar o tempo.
- **Plataformas.** Threads próprias (§10 da Runtime Spec) têm restrições no export Web; um plugin que as usa DEVERIA omitir `web` de `compatibility.platforms`.

## 6. Atividades

Contrato entre o nó `plugin` da cena e o código do plugin.

**Declaração** (manifesto): `id`, `name`, `params_schema`, `outcomes`, `outcome_labels`, `result_schema`, `suggested_effects`, `skippable`, `default_outcome` (obrigatório com `skippable: true`, e deve estar em `outcomes`). Opcional: `min_fps`, a menor taxa de quadros em que a atividade é jogável; o runtime a respeita quando o limite de FPS vem do padrão do projeto, e a escolha explícita do jogador vence (Runtime Spec §5.3, UI Spec §8).

**Textos para o autor.** O Studio gera o formulário da atividade a partir do `params_schema`, então cada propriedade DEVERIA ter `title` e `description`, e cada outcome um rótulo em `outcome_labels` (sem isso, aviso W007 e o Studio mostra o nome técnico). Os textos são escritos no idioma do autor do plugin e traduzidos em `plugin_locales` (`activity/<id>/param/<prop>/title`, `activity/<id>/outcome/<outcome>` etc.). O mesmo vale para `config_schema`.

**Mapeamentos sugeridos.** `suggested_effects` lista efeitos prontos (`label`, `op`, `value` com `{"result": …}`, `variable_type`). O Studio os oferece no inspetor do nó como frases ("Somar a pontuação ÷ 100 em…") e o autor só escolhe a variável do tipo indicado. O resultado é gravado como `on_result.effects` comum, então nada muda no runtime.

**Execução** (Runtime Spec §5.3):

```gdscript
class_name VNActivityHandle
var activity_id: StringName
var params: Dictionary            # validado e com defaults do schema
var rng: VNRandom                 # fluxo próprio desta atividade (Runtime Spec §12.2)
var mode: StringName              # &"story" (nó plugin de uma cena) ou &"free_play" (§6.1)
func complete(outcome: StringName, payload: Dictionary = {}) -> void
func fail(reason: String) -> void
func is_active() -> bool
```

Regras:

- O plugin DEVE chamar `complete` ou `fail` exatamente uma vez. Chamadas depois disso são ignoradas com aviso.
- `outcome` DEVE estar em `outcomes`; `payload` DEVERIA satisfazer `result_schema` (validado em debug).
- O plugin PODE alterar variáveis durante a atividade (com permissão), mas a forma recomendada é devolver dados no `payload` e deixar o autor mapeá-los em `on_result.effects`. Assim o projeto decide o que o minigame significa para a história, e o plugin não precisa de `variables.write`.
- Só uma atividade roda por vez.
- Ao pular (`skippable`) ou por timeout, o runtime encerra o handle (`is_active()` passa a ser falso) **antes** de chamar `_vn_cancel_activity`. Assim o plugin pode fechar o minijogo no mesmo fluxo do `await` sem completar duas vezes.
- No pulo, a cena segue pelo `default_outcome`, mas `on_result.effects` **não** é aplicado (Runtime Spec §5.3): um minijogo pulado não rende moedas nem pontos. Se o `payload` de um `complete` normal não tiver algum campo usado em `{result}`, vale o `default` do `{result}` ou o padrão do tipo da variável (Data Model §6.1).
- Sorteios do minijogo DEVERIAM usar `handle.rng`, o fluxo próprio da atividade, separado do RNG da narrativa e do `ctx.rng` do plugin. Com `settings.reproducible_rng` ele é reproduzível (Runtime Spec §12.2); sem ela, é o RNG comum do motor. `ctx.rng` não muda de fluxo durante a atividade, então guardar `ctx.rng` em `_vn_init` não troca um pelo outro.

### 6.1. Modo livre

Uma atividade com `free_play` no manifesto pode ser jogada **fora da história**: o autor põe um botão "Minijogos" no menu (ação `play_activity`, UI Spec §4) e o jogador joga quantas vezes quiser, como num modo arcade.

```json
"free_play": { "params": { "difficulty": "normal", "duration_seconds": 90 } }
```

- O runtime chama `_vn_start_activity` com `handle.mode == &"free_play"` e os `params` de `free_play.params`, sobrepostos pelos da ação. Não há cena, nó, `on_result` nem autosave.
- **A história não muda.** Leituras da NarrativeAPI devolvem os valores padrão das variáveis (e os de perfil); escritas, `emit` e `scenes.request` devolvem `INVALID_STATE` (`emit` só registra no log). As variáveis do próprio plugin com `persistence: profile` são a exceção: podem ser lidas e gravadas, e vão para o perfil.
- O que o modo livre guarda vai para o perfil: recordes e dados de perfil (§9.1). `complete` e `fail` encerram a atividade e voltam à tela que a abriu; o `payload` é ignorado, mas o `outcome` vai para `sys.ui.last_activity_outcome` e a posição do último `submit_record` para `sys.ui.last_record_rank`, para a tela mostrar "Novo recorde!" com `visible_if` (UI Spec §3.2).
- Só fora de uma partida: durante o jogo, o botão fica oculto e a ação é recusada (Runtime Spec §5.3). Rodar o modo livre suspendendo a história fica para depois do v1.
- `handle.rng` usa o RNG comum do motor (o modo livre nunca é reproduzível). O limite de FPS é o de minijogos (UI Spec §8).
- O validador confere `free_play.params` contra `params_schema` (P004). Uma ação `play_activity` para atividade sem `free_play` é erro P020.

## 7. Eventos

- Nome: `<namespace>.<nome>`; o plugin só emite no próprio namespace (P009).
- Todo evento emitido DEVE estar em `events.emits`; emitir evento não declarado retorna `PERMISSION_DENIED` em debug e é descartado.
- `payload` só com tipos JSON; o schema declarado é a documentação e o contrato. Adicionar campo opcional é MINOR; remover ou mudar tipo é MAJOR.
- `subscribes` documenta e limita o que o plugin escuta; padrões com `*` no fim são permitidos.
- Conteúdo reage a eventos de plugin com a condição `event_since_last_selection` (Data Model §5.2).

## 8. Configuração por projeto

- O plugin declara `config_schema`; o projeto guarda a configuração em `plugins.json → config`.
- O Studio gera o formulário a partir do schema (ou usa um painel do próprio plugin).
- O runtime entrega `ctx.config` já validada e com `default`s aplicados.
- Mudança incompatível no schema exige MAJOR do plugin e uma migração. A forma padrão é declarativa, em `config_migrations` (`from_major`, `ops` em JSON Patch, `destructive`), e funciona também para plugins sem parte de editor. Plugins com editor PODEM ainda exportar `migrateConfig` (§10.5), que roda depois das migrações declarativas.

## 9. Integração com saves

- Com `save.data`, o runtime chama `_vn_save()` a cada save e grava o retorno em `state.plugins.<namespace>` com `plugin_version` e `data_version`.
- O dado DEVE ser serializável em JSON e DEVERIA ter menos de 256 KB.
- Ao mudar o formato, o plugin incrementa `save.data_version` e implementa `_vn_migrate_save_data(data, from_version)`; o runtime chama a migração em cadeia antes de `_vn_load`.
- Estado que afeta a história DEVE ficar em variáveis (visíveis ao autor e ao Condition Evaluator), não nos dados opacos do plugin. Dados opacos são para estado interno de gameplay (nível da vara de pesca, recordes, inventário interno).

### 9.1. Dados de perfil e recordes

O save guarda o estado de **uma partida**. Para o que deve sobreviver entre partidas e novos jogos (recordes, fases liberadas no modo livre, estatísticas do minijogo), o plugin usa o **perfil** do jogador, com a capacidade `profile.data`:

```gdscript
class_name VNProfileAPI
func get_data() -> Variant                                  # null se o plugin nunca gravou
func set_data(data: Variant) -> VNResult                    # JSON, até 64 KB; vai para o disco no próximo debounce do perfil
func submit_record(board: StringName, score: float, meta: Dictionary = {}) -> int   # posição alcançada (1…keep) ou 0
func get_records(board: StringName) -> Array[Dictionary]    # [{ score, at, meta }], já ordenado
```

- **Onde fica.** Em `profile.json → plugins.<namespace>` (`save.schema.json → $defs/Profile`), com `plugin_version`, `data_version`, `data` e `records`. O perfil é assinado como os saves (BS §8.3), então recordes editados à mão são recusados como o resto do perfil.
- **Recordes.** Cada quadro é declarado no manifesto (`records`: `id`, `name`, `order` `desc`/`asc`, `keep`, `format` `integer`/`number`/`time_ms`). `submit_record` insere a marca com a data (`at`, UTC) e mantém só as `keep` melhores; empate fica com a mais antiga. `meta` (até 1 KB) guarda detalhes curtos, como a dificuldade. A tela de menu mostra um quadro com o elemento `records_list` (UI Spec §3.1).
- **Variáveis de perfil × dados de perfil.** Um número que o autor da VN deve poder usar em condições ("já pescou 100 peixes no total?") é uma variável do plugin com `persistence: profile`, visível no Studio. `data` é para o resto, que só o plugin entende.
- **Migração.** Ao mudar o formato, o plugin incrementa `profile.data_version` no manifesto e implementa `_vn_migrate_profile_data(data, from_version)`; o runtime chama a migração em cadeia antes do primeiro `get_data()`. Recordes não migram: um quadro removido do manifesto é descartado; um `order` novo reordena as marcas.
- **Exibição.** `records_list` e `ctx.i18n` mostram a marca pelo `format` do quadro: `integer` e `number` como na interpolação (Runtime Spec §12.1; `number` com até 2 casas), e `time_ms` como `m:ss.cc` (`h:mm:ss.cc` a partir de uma hora), com centésimos truncados e o separador decimal do idioma (`1:02.34` em inglês, `1:02,34` em português). Os vetores `records` (spec 08) fixam o formato.
- **Plugin removido.** Se o plugin sai do projeto, `profile.plugins.<namespace>` fica no perfil como dado órfão, porque o jogador pode reinstalar o jogo numa versão que o traga de volta. Se o mesmo namespace passa a ser de um plugin com outro `id`, o runtime descarta os dados antigos ao carregar o perfil e registra no log.
- **Limitação.** A data `at` vem do relógio do sistema e o perfil fica no computador do jogador, então recordes locais não são competitivos: servem para o jogador bater as próprias marcas. Placares online ficam fora do v1.
- Valem em qualquer modo (história e livre). A ação de tela `reset_profile` (UI Spec §4) apaga o perfil inteiro, inclusive recordes; saves e `settings.json` ficam.

## 10. Editor SDK (TypeScript)

Pacotes: `@vnstudio/editor-sdk` (API), `@vnstudio/plugin-schema` (tipos e schemas), `@vnstudio/plugin-cli`.

### 10.1. Isolamento

Cada Editor Extension roda num **iframe com `sandbox="allow-scripts"`** (sem `allow-same-origin`), com CSP própria e sem acesso ao IPC do Tauri. Toda comunicação passa por uma **API Bridge** via `postMessage`, que verifica a permissão efetiva em cada mensagem e só expõe os métodos abaixo. O plugin nunca vê caminhos absolutos do disco. Isso cumpre o ADD §8.1 desde o v1, mesmo que no início só existam plugins oficiais, para não mudar o contrato quando vierem os externos.

### 10.2. Ativação

```ts
// editor/src/index.ts
import type { PluginContext } from "@vnstudio/editor-sdk";

export async function activate(ctx: PluginContext): Promise<void> {
  ctx.panels.register("fishing_spots", { render: (el) => mountSpotsPanel(el, ctx) });
  ctx.commands.register("add_fishing_scene", () => createFishingScene(ctx));
  ctx.narrative.registerNodeInspector("fishing_game", FishingInspector);
}

export async function deactivate(): Promise<void> {}
```

### 10.3. API

Todas as chamadas são assíncronas (atravessam a bridge) e rejeitam com `VNError { code, message }`.

```ts
interface PluginContext {
  readonly pluginId: string;
  readonly namespace: string;
  readonly sdkVersion: string;
  ids: { newEntityId(): string };                          // UUIDv7 para nós, opções e entidades novas (síncrono, sem bridge)
  config: { get(): Promise<unknown>; set(value: unknown): Promise<void> };
  panels: {
    register(id: string, view: { render(el: HTMLElement): void | (() => void) }): Disposable;
    reveal(id: string): Promise<void>;
  };
  commands: {
    register(id: string, run: (...args: unknown[]) => unknown): Disposable;
    execute(id: string, ...args: unknown[]): Promise<unknown>;
  };
  events: {
    on(name: StudioEventName, cb: (payload: unknown) => void): Disposable;
  };
  schemas: {
    validate(schemaRef: string, data: unknown): Promise<ValidationIssue[]>;
  };
  assets: {
    list(filter?: { type?: AssetType; tag?: string }): Promise<AssetInfo[]>;
    getUrl(assetId: string): Promise<string>;              // URL temporária, só leitura
    import(file: File, opts: { id: string; type: AssetType }): Promise<AssetInfo>; // assets.write
  };
  narrative: {
    getScene(id: string): Promise<Scene>;
    listScenes(filter?: { chapter?: string }): Promise<SceneSummary[]>;
    listVariables(): Promise<VariableInfo[]>;
    getDocument(pointer?: string): Promise<unknown>;       // project.read; trecho do documento lógico (§10.4)
    applyEdit(edit: ProjectEdit): Promise<void>;           // project.write; entra no undo/redo
    registerNodeInspector(activityId: string, inspector: NodeInspector): Disposable;
  };
  notifications: {
    show(msg: string, level?: "info" | "warning" | "error"): void;
  };
  preview: {
    start(opts: { scene?: string; node?: string; variables?: Record<string, unknown> }): Promise<void>;
    onStateChanged(cb: (changes: VariableChange[]) => void): Disposable;
    renderActivityMock(activityId: string, render: (el: HTMLElement, params: unknown, done: (outcome: string, payload?: unknown) => void) => void | (() => void)): Disposable;
  };
}
```

`StudioEventName` inclui `project.opened`, `project.saved`, `scene.selected`, `node.selected`, `selection.changed`, `preview.started`, `preview.stopped`.

### 10.4. Edições e undo/redo

Plugins nunca escrevem arquivos. `narrative.applyEdit` recebe uma **lista de operações JSON Patch (RFC 6902) sobre o documento lógico do projeto**, que o Studio valida contra os schemas e as regras semânticas, aplica como um único passo de undo e salva. Isso também resolve a pendência de undo/redo do editor: o próprio Studio usa o mesmo mecanismo (todo comando gera um patch e seu inverso).

#### 10.4.1. Documento lógico

O documento lógico é a união dos arquivos do projeto num único objeto JSON, com as entidades indexadas pelo id:

```json
{
  "project": { … },            // project.json
  "variables": { … },          // variables.json
  "assets": { … },             // assets.json → assets
  "theme": { … },              // theme.json
  "ui":   { "<id>": { … } },     // ui/<id>.json (UI Spec)
  "sets": { "<id>": { … } },     // sets/<id>.json
  "plugins": { … },            // plugins.json → plugins
  "characters": { "<uuid>": { … } },
  "chapters":   { "<uuid>": { … } },
  "scenes":     { "<uuid>": { … } },
  "locales":    { "<lang>": { "<caminho de texto>": { … } } }
}
```

- **Arrays de entidades com id** (`nodes`, `options`, `cases`, `exclusive_groups`, `endings`) podem ser endereçados pelo índice ou pelo id, com o segmento estendido `@<id>`: `/scenes/<cena>/nodes/@<nó>/text`. Em arrays de definições de variável (`variables/global`, `variables/character`, `variables` de capítulo e cena), o segmento é `@<key>`. O Studio converte para índice no momento de aplicar. Isso evita que dois editores que inserem passos ao mesmo tempo apontem para o nó errado.
- **Inserir** num array: `add` em `/…/nodes/-` (fim) ou `/…/nodes/@<nó>` (antes do nó indicado).
- **Entidades novas** recebem id de `ctx.ids.newEntityId()` (UUIDv7). Criar uma cena é `add` em `/scenes/<uuid novo>`; o Studio escolhe o arquivo.
- **Conflito.** Todo `replace`, `remove` e `move` DEVE ser precedido de um `test` com o valor esperado. Se o documento mudou no meio, o patch inteiro é recusado com `VNError { code: "CONFLICT" }` e o plugin relê com `getDocument`.
- Campos derivados (nomes de arquivo, `editor`) não fazem parte do contrato: o plugin não deve depender deles.
- **Ponteiros proibidos.** Um patch de plugin que toque qualquer um destes caminhos é recusado inteiro com `VNError { code: "FORBIDDEN_PATH" }`: `/plugins` e tudo abaixo (concessões e configuração só mudam pelo Plugin Manager, com o diálogo do §4.1; a `config` do próprio plugin muda por `ctx.config.set`), `/variables/**/access`, `/project/build`, `/project/runtime`, `/project/format_version` e `/project/id`. Assim nenhum plugin concede permissões a si mesmo nem altera a exportação. O mesmo vale para `getDocument`, que não devolve `/project/build/signing`.

### 10.5. Migração de configuração

```ts
export function migrateConfig(config: unknown, fromVersion: string): unknown;
```

Chamado pelo Studio ao atualizar o plugin quando a `config` salva foi criada com versão MAJOR anterior, depois das migrações declarativas de `config_migrations` (§8). Migrações destrutivas exigem confirmação (ADD §10).

### 10.6. Preview

- No **Preview no Studio**, o interpretador TypeScript não executa GDScript. A atividade é representada por `renderActivityMock`: o plugin desenha um substituto simples (ex.: botões "Ganhou"/"Perdeu" com campos do payload) e chama `done(outcome, payload)` para concluir; a função devolvida, se houver, limpa o elemento. Sem mock, o Studio mostra um formulário gerado do `result_schema` e da lista de `outcomes`.
- No **Preview no Runtime**, a atividade real roda no Godot (Runtime Spec §11).

## 11. Compatibilidade, versões e dependências

### 11.1. Versões controladas

Studio, Editor SDK, Runtime SDK, Runtime, Godot, Data Model (`format_version`) e cada plugin — todos em SemVer (ADD §10). O plugin declara faixas em `sdk` e `compatibility`; o Plugin Manager recusa instalar fora das faixas.

### 11.2. Política de mudanças do SDK

- PATCH: correções. MINOR: APIs novas, campos opcionais novos. MAJOR: remoção ou mudança incompatível.
- Toda API removida passa antes por pelo menos um MINOR marcada como obsoleta, com aviso em debug e no `vnplugin validate`.
- O runtime de MAJOR `N` carrega plugins escritos para Runtime SDK `N` e, sempre que possível, `N-1` via camada de compatibilidade.

### 11.3. Resolução de dependências

O Dependency Resolver:

1. Parte de `plugins.json` e expande `dependencies` recursivamente.
2. Para cada ID escolhe **uma única versão**: a maior que satisfaz todas as faixas pedidas. Não há versões duplicadas do mesmo plugin num projeto (o Godot não as isolaria).
3. Falha com conflito (nenhuma versão satisfaz todas as faixas), ciclo de dependência, plugin desabilitado do qual outro habilitado depende, ou namespace duplicado.
4. `optional_dependencies` só entram se o projeto já usa o plugin; se usa, a faixa é respeitada.
5. Grava `plugin-lock.json` com versão exata, URL resolvida, `integrity`, `trust` e quem pediu.
6. Builds e o Studio usam apenas o lock; o lock só muda com ação explícita (`instalar`, `atualizar`, `remover`).

## 12. Testes e depuração

### 12.1. Testes de runtime

O addon do Runtime SDK inclui o `VNTestHarness`, uma NarrativeAPI falsa em memória com bundle mínimo, e o `VNScriptedInput`. O harness roda a atividade num `SceneTree` headless com **relógio virtual**: avança quadros de 1/60 s sem esperar o tempo real, então uma pescaria de 60 s roda em menos de um segundo.

```gdscript
class_name VNTestHarness
func _init(manifest_path: String, opts: Dictionary = {})
    # opts: variables, config, grants (padrão: tudo que o manifesto pede), seed, locale, profile
func run_activity(id: StringName, params: Dictionary, input: VNScriptedInput = null,
                  max_seconds: float = 600.0, mode: StringName = &"story") -> VNActivityResult   # { outcome, payload, failed, reason, seconds }
func skip_activity_after(id: StringName, params: Dictionary, seconds: float) -> VNActivityResult
func get_value(id: String) -> Variant
func set_value(id: String, value: Variant) -> void
func emitted(name: String) -> bool
func events() -> Array[Dictionary]                     # { name, payload, at }
func save_plugin() -> Variant                          # chama _vn_save
func load_plugin(data: Variant, from_version: int = -1) -> void   # migra se preciso e chama _vn_load
func logs() -> Array[Dictionary]
func profile_data() -> Variant                         # dados de perfil gravados pelo plugin
func records(board: StringName) -> Array[Dictionary]  # quadro de recordes, como em VNProfileAPI.get_records
func plugin_context() -> VNPluginContext              # o ctx entregue ao plugin, para testar i18n, theme etc.

class_name VNScriptedInput
func press(action: StringName, at: float) -> VNScriptedInput
func release(action: StringName, at: float) -> VNScriptedInput
func tap(action: StringName, at: float, duration: float = 0.05) -> VNScriptedInput
func repeat(action: StringName, every: float, from: float = 0.0, until: float = INF) -> VNScriptedInput
func event(ev: InputEvent, at: float) -> VNScriptedInput
```

Os tempos de `VNScriptedInput` são segundos desde o início da atividade, no relógio virtual. Os testes ficam em `tests/runtime/`, em classes que estendem `VNPluginTest` (métodos `test_*`, com `assert_eq`, `assert_true` e `assert_false`). `vnplugin test` roda todos com Godot headless e o mesmo `seed`, de modo que o resultado é reproduzível. Exemplo completo em [`examples/fishing-plugin/tests/runtime/test_fishing.gd`](examples/fishing-plugin/tests/runtime/test_fishing.gd).

### 12.2. Testes de editor e validação

- **Editor:** `@vnstudio/editor-sdk/testing` fornece um `PluginContext` falso para Vitest/Jest; `tests/editor/`.
- `vnplugin validate` roda o schema do manifesto e confere entrypoints, namespaces de eventos e variáveis, rótulos (W007), nomes globais (P011), caminhos `res://` (P012), plataformas (W008), uso de APIs do Godot vetadas em plugins (W009: `OS.execute`, `OS.create_process`, `OS.shell_open`, `HTTPRequest`, `HTTPClient`, `StreamPeerTCP`, `PacketPeerUDP`, `WebSocketPeer`, `FileAccess`/`DirAccess` fora de `user://` e `res://`, `Engine.get_singleton`, `ProjectSettings.set_setting`), e lista as capacidades pedidas. Com `--project <pasta>`, valida também o plugin dentro daquele projeto de VN.

### 12.3. Depuração dentro de uma VN

1. `vnplugin link <pasta-do-projeto-de-VN>` (ou "Vincular pasta de desenvolvimento" no Plugin Manager) instala o plugin como **vínculo**, gravado só em `.vnstudio/plugin-lock.local.json` (mesmo schema do lock, fora do Git): a entrada tem `resolved: "path:<pasta>/vn_plugins/<namespace>"`, `link: true`, `trust: local` e nenhum `integrity`, e sobrepõe a entrada de `plugin-lock.json` só naquela máquina. `plugins.json` e `plugin-lock.json`, que vão para o Git, não mudam, então colaboradores continuam com o pacote publicado. O Studio lê os arquivos direto da pasta do dev.
2. Com o **modo desenvolvedor** ligado nas preferências do Studio, o Preview no Runtime inicia o Godot embutido com `--remote-debug tcp://127.0.0.1:<porta>` (padrão 6007). No editor do Godot do dev, com "Depurar → Manter servidor de depuração aberto" ativo, funcionam breakpoints, árvore de cena remota, inspetor e profiler, porque o plugin está no mesmo caminho `res://vn_plugins/<namespace>/` nos dois lados.
3. Ao salvar um arquivo de um plugin vinculado, o Studio envia `preview.reload_plugins([id])` (Runtime Spec §11). O runtime chama `_vn_shutdown`, recarrega os scripts e cenas, chama `_vn_init`/`_vn_ready` e, se uma atividade daquele plugin estava rodando, cancela e a reinicia com os mesmos `params`. Mudança no `plugin.json` que peça permissão nova abre o diálogo de permissão antes de recarregar.
4. O painel **Plugins** do modo desenvolvedor mostra, por plugin, os logs de `ctx.log`, eventos emitidos, chamadas recusadas por permissão (com a capacidade que falta), o estado *faulted* com botão "Reativar" e o tempo gasto em cada atividade.
5. Vínculos não vão para jogadores: o assistente de exportação recusa o build enquanto houver `link: true` em `.vnstudio/plugin-lock.local.json` (P013). Para distribuir, `vnplugin package` e instalar o `.vnplugin` gerado. "Desvincular" apaga a entrada local.

## 13. Publicação, catálogo e segurança

### 13.1. CLI `vnplugin`

| Comando | Faz |
|---|---|
| `create` | Gera o projeto de desenvolvimento (§2.4): tipo, id, namespace, addon do SDK, sandbox, `.gitignore` e um teste de exemplo. Com `--embedded <projeto>`, cria em `plugins/<nome>/` do projeto de VN e registra em `plugins.json` (spec 09 §3.2) |
| `doctor` | Mostra versões do Studio, runtime, Godot fixado, SDK e Node, e o que falta instalar |
| `godot install` / `godot open` | Baixa o editor do Godot na versão exata do runtime / abre o projeto com ele |
| `link <projeto>` | Vincula a pasta do plugin a um projeto de VN para depuração (§12.3) |
| `validate` | Schema + regras do §12 |
| `test` | Testes de runtime e editor |
| `package` | `.vnplugin` reprodutível + `integrity` |
| `install <fonte>` | Instala num projeto local (atualiza `plugins.json` e lock) |
| `publish` | Cria GitHub Release com o pacote e abre pedido de inclusão no catálogo (§13.5) |
| `revoke <versão> --reason <texto>` | Pede a revogação de uma versão publicada |

### 13.2. Catálogo

JSON estático versionado num repositório do projeto e servido por HTTPS (GitHub). Cada entrada: `id`, `namespace`, versões com `url`, `integrity`, `signature` (reservado para a assinatura do v2, §13.3; ausente no v1), `state` (`draft`/`review`/`published`), `trust`, `revoked` (com motivo). O Studio só lista `published`.

- **Namespaces reservados.** O catálogo recusa os mesmos namespaces que o schema (Data Model §3).

- **Publishers.** Cada publisher é um arquivo `publishers/<publisher>.json` no repositório do catálogo, ligado a um usuário ou organização do GitHub. O primeiro plugin de um publisher inclui esse arquivo no pedido; a CI do catálogo só aceita versões cuja Release foi criada por um membro dessa conta. `vnstudio` pertence à organização oficial.
- **Namespaces.** O namespace fica reservado ao plugin no primeiro `published`. Outro plugin com o mesmo namespace é recusado na revisão, o que garante que quaisquer plugins do catálogo podem ser usados juntos.

### 13.3. Revogação e assinatura

- **v1:** integridade por hash no catálogo e no lock. Uma versão marcada `revoked` no catálogo não é instalada; projetos que já a usam recebem aviso no Studio e o build falha até atualizar ou confirmar explicitamente.
- **v2 (proposta):** assinatura ed25519 (minisign) do pacote pela chave do catálogo, verificada pelo Studio e pelo Build System, para não depender só do canal HTTPS.

### 13.4. Revisão de plugins externos

Antes de `published`: `vnplugin validate` e testes verdes, leitura do código-fonte (runtime e editor), checagem de que o pedido de permissões é proporcional ao propósito, e conferência de que `editor/dist/` corresponde a `editor/src/` (build reprodutível na CI do catálogo).

### 13.5. Fluxo de publicação

1. **Pré-condições locais.** `vnplugin publish` exige árvore Git limpa, `version` do manifesto igual à tag `v<versão>`, entrada no `CHANGELOG.md` para a versão, `repository` preenchido, `validate` sem erros e `test` verde.
2. **Autenticação.** Login no GitHub pelo fluxo de dispositivo (ou token do `gh` já configurado). A CLI nunca guarda a senha.
3. **Release.** Gera o pacote reprodutível, cria a GitHub Release no repositório do plugin com o `.vnplugin` e o `integrity` nas notas.
4. **Pedido ao catálogo.** Abre um pull request no repositório do catálogo com a versão em `state: review` (e `publishers/<publisher>.json`, se for o primeiro plugin).
5. **CI do catálogo.** Recria o pacote a partir da tag e compara o `integrity`, roda validate e testes, recompila `editor/dist/`, e publica no pull request um **diff de permissões** contra a versão anterior.
6. **Revisão humana** (checklist do §13.4, mais W009 tratado como bloqueante). Motivos de recusa: permissão sem justificativa no README, código ofuscado ou minificado em `runtime/` ou `editor/src/`, API vetada (W009), namespace já reservado, testes que não exercitam a atividade. Meta de resposta: 5 dias úteis para plugin novo, 2 para atualização.
7. **Atualização expressa.** Runtime plugins não são isolados (§4.3), então código novo de runtime sempre passa por revisão humana. Sem revisão, só entram: versões PATCH ou MINOR de plugins `official`; ou versões de qualquer plugin cujo diff **não toca `runtime/`** (só `editor/`, `docs/`, `plugin_locales`, README, CHANGELOG), sem permissão nova, sem W009 e com a CI verde. Nos dois casos, a versão fica 72 h em `review` público, com o diff no pull request, antes de virar `published` e aparecer no Studio. O Studio nunca atualiza o lock sozinho (§11.3).
8. **Revogação.** `vnplugin revoke` abre o pull request que marca a versão como `revoked`, com motivo (§13.3). A equipe do catálogo também pode revogar.

## 14. Plugin de referência: Fishing Minigame

O manifesto em [`examples/fishing-plugin/plugin.json`](examples/fishing-plugin/plugin.json) e a cena [`scene_beach.json`](examples/demo-project/scenes/ch01/scene_beach.json) cobrem os requisitos do ADD §11:

| Requisito | Onde |
|---|---|
| Manifesto | `plugin.json` |
| Configuração visual no editor | `config_schema` e `params_schema` (formulários gerados) + mock no Preview ([`editor/src/index.ts`](examples/fishing-plugin/editor/src/index.ts)) |
| Schema de parâmetros | `activities[0].params_schema` |
| Runtime Godot | [`runtime/src/fishing_plugin.gd`](examples/fishing-plugin/runtime/src/fishing_plugin.gd) e [`runtime/scenes/fishing_game.gd`](examples/fishing-plugin/runtime/scenes/fishing_game.gd) |
| Comunicação com a Narrative API | Resultado da atividade + variáveis próprias (`~total_caught`, `~best_score`) |
| Atualização de variáveis | `plugin.fishing.total_caught` + `on_result.effects` na cena (inclusive as moedas) |
| Textos ao jogador | `ctx.i18n.text` com chaves `runtime/` em `plugin_locales` |
| Emissão de eventos | `fishing.completed`, consumido por `event_since_last_selection` |
| Integração com saves | `save.data_version: 1`, `_vn_save`/`_vn_load` |
| Testes isolados | [`tests/runtime/test_fishing.gd`](examples/fishing-plugin/tests/runtime/test_fishing.gd) com `VNTestHarness` e `VNScriptedInput` |
| Inclusão no build | `plugin-lock.json` |

O exemplo mostra a separação recomendada: o plugin devolve `won`, `fish_count` e `score`; a **cena** decide que vencer seta `global.fishing_won`, que cada 100 pontos valem 1 de `global.fishing_skill` e que cada peixe vale 10 moedas em `global.player_money`. Por isso o plugin não pede `variables.read`, `variables.write` nem `transactions`, e não tem `variable_permissions`: ele só escreve nas próprias variáveis. A pasta `examples/fishing-plugin/` corresponde a `vn_plugins/fishing/` do projeto de desenvolvimento (§2.4).
