# Narrative Runtime Specification — v1.0.0-draft

- **Status:** rascunho para revisão
- **Base:** Architecture Design Document v0.1, seções 4, 6, 13.1 e 13.3; [Narrative Data Model](01-narrative-data-model.md)
- **Schema relacionado:** [`schemas/save.schema.json`](schemas/save.schema.json) · exemplo [`examples/demo-save.json`](examples/demo-save.json)

Este documento define **como o jogo executa** o conteúdo do Narrative Data Model: ciclo de vida do jogo, seleção de cenas, execução de nós, alteração de estado, eventos, saves e tratamento de erros. Ele vale para o Visual Novel Runtime (Godot/GDScript) e também para o Preview no Studio (TypeScript): **os dois interpretadores DEVEM produzir o mesmo resultado** para a mesma entrada (seção 12).

---

## 1. Módulos e autoridade

| Módulo | Responsabilidade | É a autoridade sobre |
|---|---|---|
| **Narrative Engine** | Máquina de estados do jogo; executa nós; coordena os demais | Fluxo da história |
| **Scene Scheduler** | Escolhe a próxima cena e o próximo capítulo | Seleção de cenas (ADD §15) |
| **Condition Evaluator** | Avalia condições e expressões de valor (puro, sem efeitos) | — |
| **State Manager** | Única porta de escrita do estado; transações; validação | Estado narrativo |
| **Variable Manager** | Armazena valores, defaults, escopos, derivadas | Valores das variáveis |
| **Event Bus** (Event Executor) | Fila e entrega de eventos | Ordem dos eventos |
| **Plugin Host** (Plugin Manager) | Carrega plugins, aplica permissões, roda atividades | Ciclo de vida dos plugins |
| **Save Manager** | Snapshot, restauração, perfil, migração de saves | Formato do save |
| **Stage** (UI/Audio/Asset Manager) | Desenho, áudio e entrada do jogador; sets e seus hotspots cosméticos | Apresentação (sem estado narrativo) |
| **UI Manager** | Pilha de telas (`ui/*.json`), ações de botões e configurações do jogador (UI Spec §12) | Telas abertas e `settings.json` |

Regra de dependência: só o State Manager escreve no Variable Manager. Narrative Engine, efeitos de cena, plugins e as ações `effects` de telas passam todos pelo State Manager. O Stage nunca altera variáveis, e ações de tela nunca escolhem nem pulam cenas (UI Spec §4).

```text
Plugin ──► Runtime SDK (NarrativeAPI) ──► State Manager ──► Variable Manager
                                              │
Narrative Engine (efeitos de nós) ────────────┘
                                              ▼
                      Condition Evaluator ◄── Scene Scheduler
```

## 2. Conteúdo carregado pelo runtime

O runtime não lê a pasta do projeto do Studio (ADD §15, princípio 2). O Build System compila o projeto em um **bundle narrativo**:

```text
narrative/
├── bundle.json          # project + variables + characters + chapters + scenes + theme + ui + sets + assets (IDs→caminhos res://)
├── locales/<lang>.json  # todas as traduções do idioma, por caminho de texto
└── plugins.json         # plugins habilitados, concessões efetivas e config (a partir do lock)
```

O bundle já vem validado (zero erros), com defaults resolvidos (`priority`, `max_plays`, `start` etc.), variáveis de personagem instanciadas, aliases de `renamed_from` reunidos e `content_hash` calculado (SHA-256 do `bundle.json` canônico). O conteúdo continua referenciando assets **por ID**; `bundle.json → assets` é o mapa `{id → res://…}` que o runtime usa para resolver IDs vindos de cenas, do tema, de plugins (`load_asset`, `audio.play`) e do palco salvo. O runtime DEVE recusar bundle com `format_version` MAJOR que não suporta.

Essa é a forma canônica, usada pelo Preview e pelos builds de debug. Nos builds de release cada arquivo vai como `.vnb` (comprimido, cifrado e com `content_hash` no cabeçalho) em `res://vn_content/`; o runtime decodifica para o mesmo JSON antes de usar. Ver [Build System](05-build-system-specification.md) §5 e §8.

| Forma canônica (Preview, debug) | Release (`res://vn_content/`) |
|---|---|
| `narrative/bundle.json` | `narrative.vnb` |
| `narrative/locales/<lang>.json` | `locales/<lang>.vnb` |
| `narrative/plugins.json` | `plugins.vnb` |

## 3. Ciclo de vida do jogo

```text
BOOT ─► TITLE ─┬─► NEW_GAME ─► CHAPTER_ENTER ─► (entry_scene?) ─► SELECTION_POINT
               │                                                       │
               └─► LOAD_GAME ──────────────► (restaura) ───────────────┤
                                                                        ▼
       ┌──────────── SCENE_RUNNING ◄──────────── selecionou cena ◄──────┤
       │               │   ▲                                            │
       │      nó plugin▼   │ resultado                                  │
       │          ACTIVITY ┘                                            │
       ▼                                                                │
   SCENE_END ──► SELECTION_POINT ──► nenhuma / completion ──► CHAPTER_EXIT
                                                                  │
                                 próximo capítulo ◄───────────────┤
                                 (CHAPTER_ENTER)                  ▼
                                                              GAME_END ─► TITLE
```

### 3.1. Novo jogo

1. Variable Manager zera tudo e aplica defaults (incluindo `initial_values` dos personagens).
2. Aplica variáveis `profile` lidas de `profile.json`.
3. Zera o histórico. Com `settings.reproducible_rng`, gera `rng.seed` (ou usa um fixo em modo teste/preview, §12.2); sem ela, o RNG comum do motor é semeado normalmente.
4. Plugin Host chama `_vn_game_started(true)` em cada plugin.
5. Emite `sys.game_started { new_game: true }`.
6. Entra em `start_chapter`.

### 3.2. Entrada em capítulo

1. Reinicia as variáveis `chapter.*` do capítulo para os defaults.
2. Zera o histórico dos grupos de exclusividade do capítulo.
3. `history.chapters[id].entries += 1`; `sys.chapter.id = id`.
4. Emite `sys.chapter_started`.
5. Se houver `entry_scene`, inicia-a diretamente, sem checar `max_plays` nem `conditions` (contando como seleção, ver §4.4). Senão, vai para o ponto de seleção. A reentrada num capítulo já visitado segue os mesmos passos; o `plays` das cenas é mantido (Data Model §7).

### 3.3. Saída de capítulo

1. `history.chapters[id].completed = true`; emite `sys.chapter_ended { chapter }`.
2. Escolhe o próximo capítulo entre `next[]`: filtra por `conditions` (que ainda enxergam `chapter.*`), ordena por `priority` (desc) e depois pela ordem de `project.chapters` (ausente: ordem do id). Nenhum elegível → `GAME_END`.
3. Descarta as variáveis `chapter.*` e entra no capítulo escolhido.

### 3.4. Fim de jogo

`end` com `then: "end_game"` (ou capítulo sem próximo): registra `ending`, se houver, no perfil (o ID existe em `project.json → endings`, garantido pelo validador), grava `profile.json` **na hora** (sem esperar o debounce do §8.5, porque o jogador pode fechar o jogo nos créditos), emite `sys.game_ended { ending }` (`ending` é `null` quando o jogo acaba sem final declarado), chama `_vn_game_ended()` nos plugins e volta ao título.

## 4. Scene Scheduler

### 4.1. Pontos de seleção

O Scheduler só roda em **pontos de seleção**: depois que uma cena termina, ao entrar num capítulo sem `entry_scene`, e ao carregar um save feito num ponto de seleção. **Nunca no meio de uma cena.** Alterações de variáveis durante uma cena (inclusive por plugins) só influenciam a escolha da próxima cena, nunca interrompem a atual. Isso mantém a história previsível para o autor e responde à pendência sobre alterações simultâneas no nível narrativo.

### 4.2. Elegibilidade

Uma cena `s` é **elegível** no ponto de seleção `n` (`n = sys.selection_count`) se TODAS forem verdadeiras:

1. `s.scheduling.mode == "scheduled"`;
2. `s.chapter == capítulo ativo`, ou `s.chapter == null` e o capítulo tem `include_global_scenes` (padrão `true`);
3. `max_plays == null` ou `history.scenes[s].plays < max_plays`;
4. `cooldown == 0`, ou a cena nunca foi selecionada, ou `n - last_selection > cooldown`;
5. para cada grupo `g` em `exclusive_groups`: `s` já está em `history.groups[g]`, ou `len(history.groups[g]) < g.max_plays` (padrão 1);
6. `conditions` avaliam como verdadeiras.

A ordem acima é também a ordem de avaliação: filtros baratos primeiro, condições por último.

### 4.3. Algoritmo

```text
function on_selection_point(content_request = null):
    n = history.selection_count
    plugin_request = history.pending_request             # SceneAPI.request; vai no save
    history.pending_request = null

    # 1. Pedido do conteúdo (end.then.scene): sequência explícita do autor,
    #    vem antes do fim de capítulo
    if content_request != null and accept(content_request, n):
        return start_scene(scenes[content_request])

    # 2. Fim de capítulo explícito
    if chapter.completion.conditions existe e é verdadeira:
        return exit_chapter()

    # 3. Pedido de plugin autorizado (grants.scenes)
    if plugin_request != null and accept(plugin_request, n):
        return start_scene(scenes[plugin_request])

    # 4. Candidatas elegíveis
    E = [s for s in candidates(chapter) if eligible(s, n)]

    # 5. Nenhuma elegível
    if E is empty:
        switch chapter.completion.on_exhausted:
            "advance":  return exit_chapter()
            "scene":
                if fallback_streak >= 100:                # rede de segurança contra laço (W010)
                    log_error("fallback_scene repetida 100 vezes sem o capítulo terminar")
                    return exit_chapter()
                return start_scene(scenes[chapter.completion.fallback_scene])
            "end_game": return end_game()

    # 6. Melhor prioridade
    top = max(s.priority for s in E)
    T = [s for s in E if s.priority == top]

    # 7. Desempate
    if len(T) > 1:
        if chapter.tie_breaker == "weighted_random":
            s = weighted_pick(T, weight, rng)              # §12.2; reproduzível só com reproducible_rng
        else:  # deterministic (padrão)
            s = min(T, key = (plays(s),                     # menos vista primeiro
                              last_selection(s) ?? -1,      # vista há mais tempo
                              s.order ?? +inf,              # ordem de autoria
                              s.id))                        # estabilidade final
    else:
        s = T[0]

    return start_scene(s)

function accept(id, n):
    s = scenes[id]
    if s.chapter in (chapter.id, null) and (s.mode == "manual" or eligible(s, n)):
        return true
    log_warning("pedido de cena recusado", id)           # cai para a seleção normal
    return false

function start_scene(s):
    history.scenes[s].last_selection = history.selection_count
    history.scenes[s].starts += 1
    history.selection_count += 1
    history.events_since_selection = []
    ... (seção 5)
```

`fallback_scene` é executada mesmo que seja `manual` e mesmo que tenha atingido `max_plays` (é a rede de segurança do capítulo); o validador avisa se ela não altera nada que faça o capítulo progredir (W010). `fallback_streak` conta as seleções seguidas da `fallback_scene` e zera quando outra cena é escolhida; ao chegar a 100, o runtime registra erro de conteúdo e trata como `advance`. O contador vai no save (`history.fallback_streak`).

**Pedidos.** O pedido do conteúdo (`end.then.scene`) tem precedência sobre `completion`: uma sequência roteirizada termina mesmo que a cena anterior tenha satisfeito o fim do capítulo, e `completion` é checada de novo no ponto de seleção seguinte. Pedidos de plugin vêm depois de `completion` e ficam guardados em `history.pending_request` até o próximo ponto de seleção (vão no save). Cena `manual` pedida é aceita sem checar `conditions`, `max_plays` nem `cooldown`; é o mesmo tratamento da `entry_scene`.

`weighted_pick` ordena `T` pelo `id`, calcula `r = (next_u32() / 2^32) × soma dos pesos` em ponto flutuante de 64 bits e escolhe a primeira cena cuja soma cumulativa de pesos (na mesma ordem) passa de `r`.

### 4.4. Conclusão e contagem

- `plays` só aumenta quando a cena chega a um nó `end` (ou ao fim do grafo). Uma cena abandonada (jogador saiu sem salvar) não conta.
- Ao concluir, a cena entra em `history.groups[g]` para cada grupo dela.
- `entry_scene`, `fallback_scene` e cenas pedidas diretamente também contam seleção e conclusão normalmente.

### 4.5. Respostas às pendências do ADD §13.1

| Pendência | Decisão proposta |
|---|---|
| Algoritmo de seleção | §4.3: filtro de elegibilidade → maior prioridade → desempate |
| Desempate | Determinístico por padrão (menos vista → mais antiga → `order` → `id`); sorteio ponderado opcional por capítulo, reproduzível só com `settings.reproducible_rng` (§12.2) |
| Nenhuma cena elegível | `on_exhausted` do capítulo: `advance` (padrão), `scene` (fallback) ou `end_game` |
| Repetição | Não por padrão (`max_plays: 1`); configurável com `max_plays` e `cooldown` |
| Exclusividade | `exclusive_groups` com tempo de vida de capítulo ou de jogo e `max_plays` por grupo |

## 5. Execução de cenas

### 5.1. Início

1. Instancia as variáveis `scene.*` com defaults; `sys.scene.id = s.id`.
2. Emite `sys.scene_started { scene, chapter }`.
3. Vai para `start` (ou o primeiro nó).

### 5.2. Laço de nós

O Narrative Engine executa um nó de cada vez. Cada nó é **instantâneo** (avança na mesma frame) ou **bloqueante** (espera algo):

| Nó | Tipo | Comportamento |
|---|---|---|
| `line` | bloqueante | Mostra o texto interpolado; espera o jogador avançar (ou auto/skip, §8.5). Adiciona ao backlog e ao `seen_text` do perfil |
| `interact` | bloqueante | Como `choice`, com hotspots no lugar de opções (UI Spec §6): avalia `visible_if`/`enabled_if` uma vez ao entrar e esconde os hotspots `once` já usados (`scene.used_hotspots`). Sem hotspot visível e sem `exit`, segue `next`. Ao clicar: marca o `once`, aplica `effects` + `record` numa transação, emite `sys.choice_made { scene, node, option: <hotspot>, value }` e vai para `goto` (ausente: `next`). `exit` vai para seu `goto` (ausente: `next`) sem efeitos |
| `choice` | bloqueante | Avalia `visible_if`/`enabled_if` **uma vez** ao entrar. Sem opção visível, segue `next` (ou o nó seguinte). Ao escolher: aplica `effects` e `record` (`value` da opção ou o id) numa **única** transação; se ela falhar por restrição, tudo é desfeito e a cena segue mesmo assim. Emite `sys.choice_made { scene, node, option, value }` e vai para `goto` (ausente: `next`) |
| `effects` | instantâneo | Aplica a lista como transação. Falha por restrição (`CONSTRAINT_VIOLATION`) não é erro: vai para `on_fail`, se houver, ou segue. Outras falhas são erro de conteúdo (§9) e seguem o fluxo normal |
| `branch` | instantâneo | Primeiro `case` verdadeiro → `goto`; senão `else` ou próximo |
| `jump` | instantâneo | Vai para `goto` |
| `background` (`asset` ou `set`), `show`, `hide`, `audio` | instantâneo* | Atualiza o Stage. *A transição visual roda em paralelo; o próximo nó não espera, exceto se for outro comando de Stage no mesmo alvo |
| `wait` | bloqueante | Espera `seconds` (pulável se `skippable`) |
| `emit` | instantâneo | Avalia o payload e enfileira o evento |
| `plugin` | bloqueante | Entra em `ACTIVITY` (§5.3) |
| `end` | — | Conclui a cena (§5.4) |

Guarda contra laço infinito: mais de 10 000 nós instantâneos seguidos sem um bloqueante é erro de conteúdo (provável `jump` circular).

### 5.3. Atividades de plugin

1. Verifica se o plugin está carregado e habilitado; senão segue `on_error`.
2. Valida `params` contra `params_schema` (no build já foi validado; em runtime só em debug).
3. Faz **autosave de segurança**, sempre, inclusive com `settings.autosave: off` (§8.1). O save guarda o nó `plugin` como `scene.node`; ao carregá-lo, a atividade recomeça do início.
4. Emite `sys.activity_started { activity, scene, node }` e chama `_vn_start_activity(activity_id, params, handle)` no plugin. Durante a atividade, com `input.capture`, só o plugin recebe a entrada do jogador (Plugin SDK §4.2).
5. O plugin termina chamando `handle.complete(outcome, payload)` ou `handle.fail(reason)`.
6. No `complete`: valida `outcome` (desconhecido → erro → `on_error`); aplica `on_result.effects` com `{result: …}` resolvido a partir do payload (campo ausente → `default` do `{result}` ou padrão do tipo da variável de destino, Data Model §6.1). Campo com tipo diferente do esperado conta como **ausente**, com aviso no log, em vez de abortar a transação: um plugin com bug não tira do jogador as recompensas dos outros campos. `integer` aceita número com parte fracionária zero (`3.0`); emite `sys.activity_completed { activity, outcome, skipped: false }`; vai para `outcomes[outcome]` ou `next`.
7. Se o jogador pular (`skippable`), o runtime encerra o handle, chama `_vn_cancel_activity` e completa com `default_outcome`. **No pulo, `on_result.effects` não é aplicado**: só o desvio por outcome acontece, e o evento sai com `skipped: true`.
8. Timeout opcional (`settings.activity_timeout_seconds`, ausente = sem limite) → o handle é encerrado, `_vn_cancel_activity` é chamado e a atividade falha (`on_error`).

Durante uma atividade a cena está suspensa: nenhum nó avança e o Scheduler não roda.

**Taxa de quadros.** Fora de atividades vale `PlayerSettings.fps_limit_vn` (padrão do projeto: `settings.display.fps_limit_vn`, 60). No passo 4, antes de chamar o plugin, o runtime troca para `fps_limit_activity` (padrão 0, sem limite), elevado ao `min_fps` da atividade quando o limite vem do padrão do projeto; ao terminar, cancelar ou falhar, volta ao limite da VN. `0` = sem limite; com `vsync`, o monitor limita. No Web, o navegador decide (UI Spec §8).

### 5.4. Fim de cena

1. `plays += 1`, registra os grupos.
2. Emite `sys.scene_ended { scene, chapter }`.
3. Descarta as variáveis `scene.*`.
4. Conforme `then`: `schedule` → ponto de seleção; `{scene}` → ponto de seleção com pedido; `end_chapter` → saída de capítulo; `end_game` → fim de jogo.

## 6. State Manager e Variable Manager

### 6.1. Modelo de concorrência

- **Escritor único.** Todo estado narrativo é alterado na thread principal do Godot, através do State Manager. Uma chamada de escrita feita de outra thread não é aplicada: retorna `VNResult` com erro `WRONG_THREAD` (em debug e em release), e o plugin reenvia com `call_deferred`. Leituras de outra thread também retornam `fallback` com erro no log. Assim o resultado nunca é otimista.
- **Sem interrupção.** Escritas valem imediatamente para leituras e condições subsequentes, mas o Scheduler só as considera no próximo ponto de seleção (§4.1).
- **Transações.** Uma transação acumula operações e só valida/aplica no `commit`. Como o código pode `await` entre `begin` e `commit`, o estado pode mudar nesse intervalo: operações relativas (`add`, `subtract`, `multiply`, `toggle`) são calculadas sobre o valor no momento do commit; `set` sobrescreve. Para proteger contra condição de corrida, a transação aceita `expect(variable, value)`: se o valor no commit for diferente, o commit falha com `CONFLICT` e nada é aplicado.

### 6.2. Validação de escrita

Para cada operação, nesta ordem (primeira falha interrompe):

| # | Verificação | Código de erro |
|---|---|---|
| 1 | Chamada feita na thread principal | `WRONG_THREAD` |
| 2 | Estado do jogo permite escrita (não em `LOAD_GAME`, `GAME_END`, nem durante avaliação de condição) | `INVALID_STATE` |
| 3 | Variável existe | `VARIABLE_NOT_FOUND` |
| 4 | Não é `sys.` nem derivada | `READ_ONLY` |
| 5 | Escopo ativo (`chapter.*`/`scene.*` só com capítulo/cena ativos) | `SCOPE_INACTIVE` |
| 6 | Chamador tem permissão de escrita (plugins: §4.6 do Data Model) | `PERMISSION_DENIED` |
| 7 | Tipo compatível com a operação e com o valor | `TYPE_MISMATCH` |
| 8 | Resultado dentro do intervalo de inteiros (§12.1) e finito | `OUT_OF_RANGE` (erro de conteúdo) |
| 9 | Restrições (`min`/`max` com `on_overflow`, `max_length`, `values`) | `CONSTRAINT_VIOLATION` (lógica de jogo, não erro de conteúdo: Data Model §6.2) |
| 10 | `expect` confere (só transações) | `CONFLICT` |

Leituras verificam 1, 3, 5 e permissão de leitura. Variável derivada é recalculada na leitura.

### 6.3. Resultado

Toda operação de escrita retorna um `VNResult`:

```gdscript
class_name VNResult
var ok: bool
var error: StringName          # &"" quando ok
var message: String
var changes: Array[Dictionary] # [{ "variable": "global.player_money", "old": 30, "new": 130 }]
```

### 6.4. Notificação de mudanças

Após cada operação ou transação aplicada, o State Manager emite **um** sinal `state_changed(changes)` com todas as mudanças (não um por variável). UI de debug, Preview e plugins com `variables.read` podem observar as variáveis que têm permissão de ler. Mudanças não geram eventos no Event Bus (para não inundá-lo); quem precisa reagir usa o sinal.

### 6.5. Ciclo de vida por escopo (resumo)

| Escopo | Criada | Reiniciada | Destruída | Salva |
|---|---|---|---|---|
| `global.*`, `character.*`, `plugin.*` | Novo jogo / load | Novo jogo | Fim de jogo / volta ao título | Conforme `persistence` |
| `chapter.*` | Entrada no capítulo | Cada entrada | Saída do capítulo | Se o save ocorre com o capítulo ativo |
| `scene.*` | Início da cena | Cada início | Fim da cena | Se o save ocorre no meio da cena |
| `profile` (qualquer escopo permitido) | Primeiro boot | Nunca (só "apagar dados") | Nunca | Em `profile.json`, com debounce (§8.5) |
| `session` | Como o escopo | Também ao carregar save | Como o escopo | Nunca |

## 7. Eventos

### 7.1. Namespaces

| Namespace | Quem emite |
|---|---|
| `sys.*` | Runtime (tabela abaixo) |
| `story.*` | Conteúdo (nó `emit`), declarados em `project.json → events` (W015) |
| `<namespace>.*` | O plugin dono do namespace (declarados em `events.emits`) |

| Evento `sys.*` | Quando | Payload |
|---|---|---|
| `sys.game_started` | Novo jogo (§3.1 passo 5) e ao carregar (§8.3 passo 6), antes de qualquer cena | `{ new_game: bool }` |
| `sys.chapter_started` | §3.2 passo 4 | `{ chapter, entries }` |
| `sys.chapter_ended` | §3.3 passo 1 | `{ chapter }` |
| `sys.scene_started` | §5.1 passo 2 | `{ scene, chapter }` |
| `sys.scene_ended` | §5.4 passo 2 | `{ scene, chapter }` |
| `sys.choice_made` | Opção escolhida (§5.2) | `{ scene, node, option, value }` |
| `sys.activity_started` | §5.3 passo 4 | `{ activity, scene, node }` |
| `sys.activity_completed` | §5.3 passos 6–7 (não em falha) | `{ activity, outcome, skipped }` |
| `sys.game_saved` | Depois de gravar um save | `{ slot, autosave: bool }` |
| `sys.game_loaded` | §8.3 passo 6, logo depois de `sys.game_started` | `{ slot }` |
| `sys.game_ended` | §3.4 | `{ ending }` (`null` sem final) |

### 7.2. Entrega

- `emit` **enfileira**; nunca chama ouvintes na mesma pilha. A fila é esvaziada ao final da operação atual (fim do nó, fim do commit, fim do callback do plugin), em ordem FIFO.
- Ouvintes podem emitir novos eventos, que vão para o fim da fila. Mais de 64 eventos encadeados numa mesma drenagem é erro (provável ciclo) e a drenagem é interrompida.
- Todo evento `story.*` ou de plugin entregue tem seu nome adicionado a `history.events_since_selection` (usado pela condição `event_since_last_selection`), que é zerada a cada seleção e vai no save. Eventos `sys.*` não entram: o que eles informam já está em `sys.*` e no histórico, e a lista do save fica pequena.
- Payload é um `Dictionary` só com tipos JSON. Em debug/preview, o payload é validado contra o schema declarado; em release, não.
- Ouvintes recebem `(name, payload, source)`, onde `source` é `"sys"`, `"story"` ou o ID do plugin.

## 8. Saves

### 8.1. Quando é possível salvar

- Em pontos de seleção;
- Em nós `line`, `choice` e `interact` aguardando o jogador;
- No nó `plugin`, **antes** de iniciar a atividade (só o autosave de segurança, §5.3; ao carregar, a atividade recomeça);
- No início da cena, depois de instanciar `scene.*` e antes do primeiro nó (só o autosave `scene_start`; ao carregar, a cena começa do primeiro nó);
- **Não** durante `ACTIVITY` nem durante transições de capítulo. O autosave antes de cada atividade cobre esse intervalo.

### 8.2. O que é salvo

Ver [`save.schema.json`](schemas/save.schema.json): **todas** as variáveis `persistence: save` (inclusive as que estão no padrão e as `chapter.*`/`scene.*` ativas), capítulo e cena atuais (com o nó e o estado do Stage), histórico do Scheduler (inclusive `pending_request` e `fallback_streak`), estado do RNG (só com `settings.reproducible_rng`, §12.2, inclusive os fluxos dos plugins), dados opacos de cada plugin (`SaveAPI`) com `data_version`, e o backlog. Derivadas e `session` nunca vão para o save.

Gravar também os valores iguais ao padrão é o que permite mudar um `default` numa atualização do jogo sem alterar o progresso de quem já jogava. O backlog guarda o caminho do texto e os valores interpolados, não o texto pronto, então trocar de idioma ou atualizar o jogo se reflete no histórico.

### 8.3. Carregamento

1. Valida contra o schema; recusa `save_format` MAJOR desconhecido.
2. Se havia um jogo em andamento (carregar sem voltar ao título), chama `_vn_game_ended()` nos plugins.
3. Reinicia o estado e aplica defaults → perfil → variáveis do save, traduzindo chaves antigas pelos aliases de `renamed_from` (§8.4 trata divergências).
4. Restaura histórico, RNG (se houver), capítulo.
5. Para cada plugin, nesta ordem: `_vn_game_started(false)`; se `data_version` < atual, `_vn_migrate_save_data(data, from_version)`; depois `_vn_load(data)`. Se o save não tem dados do plugin, chama `_vn_load(null)`, e o plugin volta ao estado inicial. Dados de plugin ausente do jogo são **preservados** opacos e regravados no próximo save, com aviso.
6. Emite `sys.game_started { new_game: false }` e depois `sys.game_loaded { slot }`, e drena a fila de eventos.
7. Restaura o Stage e retoma: se havia cena, reexecuta o nó salvo (a fala aparece de novo, sem duplicar o backlog; a escolha e o `interact` reavaliam opções e hotspots; o nó `plugin` recomeça a atividade); senão, vai ao ponto de seleção.

Os aliases de `renamed_from` valem também ao ler `profile.json`, com as mesmas regras do §8.4: renomear uma variável `profile` depois do lançamento não perde galeria nem NG+.

### 8.4. Save de versão antiga do jogo

Quando `content_hash` difere (o jogo foi atualizado) ou falta no save (tratado como diferente):

| Situação | Comportamento |
|---|---|
| Variável do save foi renomeada | Lida pelo alias de `renamed_from` (Data Model §12) |
| Variável do save não existe mais | Descartada, com aviso no log |
| Variável nova | Recebe o default |
| Default mudou | O valor do save vale, porque todas as variáveis são gravadas (§8.2) |
| Tipo mudou | Tenta converter (int↔number, bool↔int); senão default e aviso |
| Valor fora das restrições novas | Ajustado (`clamp`) |
| Cena atual não existe | Volta ao ponto de seleção |
| Nó atual não existe | Reinicia a cena do início, com `scene.*` zeradas |
| Capítulo atual não existe | Entra no `start_chapter`; histórico é mantido |

O autor PODE fornecer migradores de save por versão do jogo (`migrations/save/<from>-<to>.json`, lista de efeitos) no futuro; fora do v1.

### 8.5. Slots, arquivos e preferências

Todos os arquivos ficam em `user://` (no Web, IndexedDB).

| Arquivo | Conteúdo |
|---|---|
| `saves/slot_<n>.json` (n = 1 a 99) | Saves manuais, com miniatura em `saves/slot_<n>.png` (320 × 180) |
| `saves/quick.json` | Salvamento rápido (uma tecla, sem menu) |
| `saves/auto_<n>.json` (n = 1 a 3) | Autosaves em rodízio (`settings.autosave` e antes de atividades) |
| `profile.json` | Perfil (`save.schema.json → $defs/Profile`) |
| `settings.json` | Preferências do jogador (`$defs/PlayerSettings`): idioma, velocidade do texto, espera do modo automático, pular só texto lido, modo de tela, resolução, VSync, limites de FPS da VN e dos minijogos, volumes por canal e acessibilidade. Sem assinatura. Só os campos que o jogador mudou são gravados; os demais vêm de `project.json → settings.display` e dos padrões do runtime (UI Spec §8) |

- **Continuar** abre o save mais recente entre todos os slots, rápido e autosaves.
- O jogador só salva pelo menu em nós `line`, `choice` e `interact` (§8.1); um ponto de seleção é instantâneo, então só autosaves o capturam.
- O perfil é gravado com *debounce*: em cada ponto de seleção, ao fim do jogo e ao sair. Não a cada fala. `seen_text` guarda o hash curto de cada caminho de texto (16 hex), para não crescer com o tamanho do texto.
- **Automático e pular.** O modo automático avança as falas depois de `auto_delay`; pular avança sem esperar e para em escolhas, atividades e, com `skip_unread: false`, no primeiro texto não lido.

## 9. Tratamento de erros

| Origem | Debug / Preview | Release |
|---|---|---|
| Conteúdo (variável inexistente, divisão por zero, inteiro fora do intervalo, laço infinito, `fallback_scene` em laço) | Pausa e mostra overlay com cena, nó e erro | Registra; condição vale `false`, efeito/transação é abortado, nó é pulado |
| Restrição (`CONSTRAINT_VIOLATION`) | Só log, sem overlay | Só log; o nó segue `on_fail` (Data Model §6.2) |
| Transação de plugin falhou | `VNResult` com erro; log | Igual |
| Atividade falhou ou expirou | Overlay + segue `on_error` | Segue `on_error` |
| Plugin com erros repetidos (≥ 5 por sessão: erros de script reportados pelo motor, `fail` de atividade, timeout e chamadas com `PERMISSION_DENIED` ou `WRONG_THREAD`) | Marcado como *faulted* | Marcado como *faulted*: ouvintes removidos, atividades vão direto para `on_error` |
| Plugin falhou ao carregar (hash, versão, script) | Erro bloqueante | Jogo continua sem o plugin; atividades vão para `on_error` |

GDScript não tem exceções: o SDK expõe resultados explícitos (`VNResult`) e o Plugin Host detecta falhas por retorno, por timeout e pelos erros de script reportados pelo motor.

## 10. Política de execução assíncrona

- O Narrative Engine é dirigido por sinais na thread principal; nenhum laço bloqueia a frame.
- Plugins PODEM usar `await` e threads próprias para gameplay, mas toda chamada ao SDK é reenviada para a thread principal.
- Fora de atividades, plugins só rodam em: ouvintes de eventos, sinal `state_changed`, e overlays de UI (`ui.overlay`). Nada disso pode avançar nós.
- Ordem garantida: efeitos de um nó → drenagem de eventos → próximo nó.

## 11. Comunicação com o Studio (Preview no Runtime)

Proposta para a pendência do ADD §3.3. O protocolo completo, com parâmetros, resultados, erros e schema, está em [07-preview-protocol.md](07-preview-protocol.md); esta seção é o resumo.

- **Transporte:** WebSocket em `127.0.0.1`, porta escolhida pelo Studio, com token de uso único passado por argumento de linha de comando (`--vn-preview-port`, `--vn-preview-token`). O runtime recusa conexões sem o token.
- **Protocolo:** JSON-RPC 2.0.
- **Studio → Runtime:** `preview.load(bundle_path)`, `preview.start({chapter, scene?, node?, variables?, seed?})` (com `reproducible_rng`, `seed` é a semente do PCG32; sem ela, semeia o RNG comum do motor, o que ajuda a reproduzir um bug no Preview mas não garante traço idêntico), `preview.set_variables({...})`, `preview.get_state()`, `preview.step()`, `preview.pause()`, `preview.reload(changed_files)`.
- **Studio → Runtime (diagnóstico):** `preview.explain_selection({scene?})` devolve, sem alterar o estado, a avaliação atual do Scheduler (formato abaixo).
- **Runtime → Studio (notificações):** `state.changed`, `scene.started`, `node.entered`, `event.emitted`, `scheduler.evaluated`, `log`, `error`.
- **Explicação da seleção:** em cada ponto de seleção, o runtime em modo preview emite `scheduler.evaluated` com cada cena candidata e o motivo da decisão (formato completo em Preview Protocol §4.3). É o que o Studio usa para responder "por que esta cena não apareceu?":

  ```json
  { "selection_count": 4, "chapter": "ch01", "chosen": "scene_quiet_day", "reason": "fallback",
    "candidates": [
      { "scene": "scene_beach", "eligible": false, "blocked_by": "max_plays", "detail": { "plays": 1, "max_plays": 1 } },
      { "scene": "scene_fishing_master", "eligible": false, "blocked_by": "conditions",
        "failed": [{ "path": "conditions[1]", "variable": "global.fishing_skill", "operator": "greater_than_or_equal",
                     "expected": 10, "actual": 3 }] }
    ] }
  ```

  `blocked_by` ∈ `conditions`, `max_plays`, `cooldown`, `exclusive_group`, `mode_manual`, `lower_priority`, `tie_break`. `reason` ∈ `request`, `plugin_request`, `priority`, `tie_break`, `fallback`, `completion`, `exhausted`. Um pedido recusado aparece em `request_refused: { scene, by }`. O interpretador do Preview no Studio produz o mesmo formato, e os vetores de conformidade (§12) incluem esse traço.
- **Hot reload:** em `preview.reload`, o runtime recarrega o bundle e tenta permanecer na mesma cena e nó; se o nó sumiu, reinicia a cena.
- **Plugins em desenvolvimento** (Plugin SDK §12.3): `preview.reload_plugins(ids)` recarrega os scripts e cenas dos plugins vinculados (`_vn_shutdown` → recarga → `_vn_init`/`_vn_ready`) e reinicia a atividade em curso com os mesmos `params`. No modo desenvolvedor, o Studio passa `--remote-debug tcp://127.0.0.1:<porta>` para o depurador do Godot do dev, e o runtime envia as notificações `plugin.log`, `plugin.permission_denied { plugin, capability, call }` e `plugin.faulted`.
- **Caminho dos plugins:** no bundle e no jogo exportado, cada plugin fica em `res://vn_plugins/<namespace>/` (Plugin SDK §2.4).

Motivo: funciona igual em Windows, macOS e Linux, permite inspeção ao vivo e é trivial de consumir pelo React/Tauri.

## 12. Conformidade e testes

- **Vetores de conformidade:** um conjunto compartilhado de casos `entradas → resultado esperado`, definido em [08-conformance-vectors.md](08-conformance-vectors.md), com os casos em `conformance/` e a implementação de referência em `tools/conformance.py`. O Runtime Godot e o interpretador do Preview no Studio DEVEM passar no mesmo conjunto.
- **Runner headless:** `godot --headless -- --vn-test <casos>` executa os vetores sem renderizar.
- **Determinismo:** com as mesmas entradas, o traço é idêntico nos dois interpretadores. Sorteios só entram nessa garantia com `settings.reproducible_rng` (§12.2); sem ela, os vetores de conformidade não podem depender de sorteios.

### 12.1. Semântica de referência

Para que os dois interpretadores produzam o mesmo traço, estas regras são normativas e cada linha tem casos nos vetores de conformidade:

- **Números.** `number` é IEEE 754 de 64 bits. `integer` vale no intervalo **±(2^53 − 1)** nos dois interpretadores (o Godot guarda em int64, mas o limite é o mesmo do JavaScript). Resultado inteiro fora do intervalo, `number` não finito (infinito ou NaN), divisão ou `mod` por zero e conversão de `number` fora do intervalo para `integer` são erro de conteúdo nos dois (`OUT_OF_RANGE`, §6.2): a transação é abortada. Comparações e funções seguem a tabela do Data Model §6.1.1 (tipos de resultado, `div` sempre real, `mod` com o sinal do divisor, `round` meio-para-longe-do-zero). Comparar `integer` com `number` converte o inteiro para `number` (exato dentro do intervalo).
- **Conversão para texto** (`concat`). Inteiros sem casa decimal; `number` com parte fracionária zero também sem casa (`2.0` → `2`); os demais na menor representação que volta ao mesmo valor, como o `Number.prototype.toString` do JavaScript (`1/3` → `0.3333333333333333`), mas nunca em notação científica dentro do intervalo de inteiros.
- **Formatação na interpolação.** O runtime traz uma tabela própria por idioma (separador decimal, separador de milhar, até 2 casas decimais sem zeros à direita, arredondando meio-para-longe-do-zero sobre a representação decimal mais curta, a mesma do `concat`: `1.005` → `1.01`; um negativo que arredonda para zero aparece sem sinal), sem depender de ICU ou `Intl`. Idioma fora da tabela usa a do inglês. A mesma formatação vale para os `args` de `ctx.i18n.text` (Plugin SDK §5.7).

  | Idioma | Decimal | Milhar | Exemplo (1234567,5) |
  |---|---|---|---|
  | `en`, `ja`, `zh-Hans`, `zh-Hant` | `.` | `,` | 1,234,567.5 |
  | `pt-BR`, `it`, `de` | `,` | `.` | 1.234.567,5 |
  | `es` | `,` | `.` (só a partir de 5 dígitos: 1234 fica sem separador) | 1.234.567,5 |
  | `fr` | `,` | espaço fino inseparável (U+202F) | 1 234 567,5 |

  A tabela casa pela tag completa e depois pelo idioma (`pt-PT` → `pt`, que fica fora da tabela e usa o inglês até ser acrescentado).
- **JSON canônico.** Os dois implementam o JCS (Build System §5.1) para `content_hash` e assinaturas.
- **Ordem.** Toda iteração sobre mapas (variáveis, cenas candidatas, plugins) segue a ordem lexicográfica das chaves.

### 12.2. RNG reproduzível (opcional)

É **opcional e vem desligado** (`project.json → settings.reproducible_rng`). Um projeto que não usa sorteios, ou que não precisa de sorteios reproduzíveis, ignora esta seção inteira.

- **Desligado (padrão).** `random_int`, `weighted_random`, `ctx.rng` e `handle.rng` usam o RNG comum do motor, semeado ao abrir o jogo. Nada de RNG vai para o save, e recarregar um save pode sortear diferente. Os vetores de conformidade não cobrem sorteios.
- **Ligado.**
  - Algoritmo **PCG32** (XSH-RR, multiplicador 6364136223846793005, incremento 1442695040888963407). `seed` e `state` são gravados no save em hexadecimal de 16 dígitos, porque inteiros de 64 bits perdem precisão em JSON no JavaScript.
  - **Semeadura:** `state = 0`, avança um passo, `state += seed`, avança um passo. Cada saída de 32 bits usa o estado anterior ao passo (XSH-RR padrão).
  - `random_int(min, max)` usa rejeição para evitar viés: com `n = max − min + 1` até 2^32, sorteia `r = next_u32()` até que `r ≥ (2^32 − n) mod n` e devolve `min + r mod n`; com `n` maior, faz o mesmo com `next_u64() = (next_u32() << 32) | next_u32()` e 2^64. `weighted_pick` segue §4.3. Os vetores de conformidade (`conformance/rng.json`) fixam as saídas.
  - **Fluxo separado por atividade.** O RNG de uma atividade é entregue em `handle.rng` (Plugin SDK §6): um PCG32 próprio, semeado com os 8 primeiros bytes (big-endian) de SHA-256(`seed` ‖ `selection_count` ‖ id do nó ‖ `activity_index`), onde `seed` são os 8 bytes big-endian da semente do jogo, `selection_count` é um uint64 big-endian, o id do nó são os 16 bytes do UUID e `activity_index` é um uint32 big-endian que conta as atividades já iniciadas na execução atual da cena (começa em 0; separa duas passagens pelo mesmo nó). Assim os sorteios do minijogo, que dependem do tempo de reação do jogador, não alteram o RNG da narrativa, e o traço continua reproduzível depois de qualquer atividade, inclusive entre o mock do Preview no Studio e o plugin real.
  - **Fluxo do plugin fora de atividades.** `ctx.rng` é um PCG32 por plugin, semeado com os 8 primeiros bytes de SHA-256(`seed` ‖ namespace em UTF-8). O estado dele vai no save em `rng.streams.<namespace>`, para que carregar um save não reinicie a sequência. `ctx.rng` nunca muda de fluxo durante a atividade; quem precisa do fluxo da atividade usa `handle.rng`.
  - O estado dentro de uma atividade não é salvo: não há save durante `ACTIVITY` (§8.1).

## 13. Versionamento

O runtime declara as faixas suportadas de `format_version` (Data Model), `save_format` e Runtime SDK. Mudança incompatível em qualquer contrato deste documento exige MAJOR do runtime.
