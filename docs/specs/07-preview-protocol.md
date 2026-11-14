# Protocolo do Preview — v1.0.0-draft

- **Status:** rascunho para revisão
- **Base:** Runtime Spec §11; Plugin SDK §12.3; Requisitos de autoria §4; UI Spec §9
- **Schema:** [`schemas/preview-protocol.schema.json`](schemas/preview-protocol.schema.json)

O Studio mostra o jogo rodando de verdade, no Runtime Godot embutido, enquanto o autor edita. Este documento define a conversa entre os dois: como o Studio abre o runtime, os métodos que pode chamar, as notificações que recebe e os erros. Ele detalha o RT §11, que fica como resumo.

As palavras **DEVE**, **DEVERIA** e **PODE** seguem a RFC 2119.

## 1. Transporte e sessão

1. O Studio escolhe uma porta livre em `127.0.0.1` e gera um token aleatório de 32 bytes (hex).
2. O Studio abre o runtime com `--vn-preview-port <porta> --vn-preview-token <token>` (e `--remote-debug tcp://127.0.0.1:<porta>` no modo desenvolvedor, Plugin SDK §12.3).
3. O runtime abre um servidor WebSocket só em `127.0.0.1:<porta>`, aceita **uma** conexão por vez e espera `session.hello` com o token. Qualquer outra mensagem antes disso, token errado ou 5 segundos sem `hello` fecham a conexão com o código 4401. Uma segunda conexão é recusada com 4409.
4. Cada quadro de texto do WebSocket leva **uma** mensagem JSON-RPC 2.0 em UTF-8. Lotes (arrays) não são aceitos.
5. Ao fechar a janela do jogo, o runtime envia `session.closing` e fecha com 1000. Se a conexão cair, o runtime encerra sozinho em 10 segundos, para não deixar processos órfãos.

Mensagens do Studio para o runtime são **requisições** (com `id`) e recebem uma resposta. Mensagens do runtime para o Studio são **notificações** (sem `id`). O runtime nunca faz requisições ao Studio no v1.

O protocolo tem versão própria (`protocol`, hoje `1.0`), independente do runtime. Mudança incompatível sobe o MAJOR; o `hello` falha com `UNSUPPORTED_VERSION` se os MAJOR forem diferentes.

## 2. Estados do Preview

```text
CONNECTED ─ hello ─► READY ─ load ─► LOADED ─ start ─► RUNNING ⇄ PAUSED
                                        ▲                 │
                                        └──── stop ───────┘
```

| Estado | O que o runtime está fazendo |
|---|---|
| `READY` | Autenticado, sem bundle |
| `LOADED` | Bundle carregado, nenhum jogo em andamento (mostra a tela de título se o Studio pedir `preview.show_screen`) |
| `RUNNING` | Jogo em andamento; a cada nó, notificações |
| `PAUSED` | Jogo congelado num nó; aceita `step`, `set_variables` e `resume` |

O estado do motor (RT §3: `TITLE`, `SCENE_RUNNING`, `ACTIVITY`…) vem em `preview.get_state` e no campo `phase` das notificações.

## 3. Métodos (Studio → Runtime)

| Método | Estados | Parâmetros | Resultado |
|---|---|---|---|
| `session.hello` | `CONNECTED` | `token`, `protocol`, `studio_version` | `runtime_version`, `godot_version`, `protocol`, `platform`, `features` |
| `preview.load` | `READY`, `LOADED` | `bundle_path` (pasta com a forma canônica, RT §2), `locale`? | `content_hash`, `format_version`, `chapters`, `scenes`, `plugins` |
| `preview.start` | `LOADED` | `chapter`?, `scene`?, `node`?, `variables`?, `profile`?, `seed`?, `paused`? | `GameState` |
| `preview.stop` | `RUNNING`, `PAUSED` | — | `{}` (volta a `LOADED`) |
| `preview.pause` / `preview.resume` | `RUNNING` / `PAUSED` | — | `{ node }` |
| `preview.step` | `PAUSED` | `until`: `node` (padrão), `blocking`, `scene_end`, `selection` | `{ node, phase }` (continua `PAUSED`) |
| `preview.input` | `RUNNING`, `PAUSED` | `action`: `advance`, `choose` (`option`), `click` (`hotspot`), `skip_activity`, `cancel_activity` | `{ accepted }` |
| `preview.set_variables` | `PAUSED`, ou `RUNNING` fora de `ACTIVITY` | `variables`: `{ id qualificado → valor }` | `{ changes }` |
| `preview.get_state` | qualquer depois de `load` | `include`: lista de `variables`, `history`, `stage`, `backlog`, `plugins` (padrão: todos) | `GameState` |
| `preview.explain_selection` | `RUNNING`, `PAUSED` | `scene`? | `SchedulerEvaluation` (§4.3), sem alterar o estado |
| `preview.reload` | depois de `load` | `bundle_path`, `changed` (caminhos do projeto que mudaram) | `{ content_hash, resumed }` |
| `preview.reload_plugins` | depois de `load` | `ids` | `{ reloaded, activity_restarted }` |
| `preview.show_screen` | `LOADED`, `RUNNING`, `PAUSED` | `screen` (id de `ui/`), `simulate`? (`has_save`, `in_game`, `platform`, `endings`) | `{}` |
| `preview.set_locale` | depois de `load` | `locale` | `{}` |

Detalhes:

- **`preview.start`.** Sem `scene`, começa um jogo novo (RT §3.1) no `chapter` dado ou no `start_chapter`. Com `scene`, entra no capítulo da cena sem rodar a `entry_scene` e começa a cena; com `node`, começa nesse nó, depois de instanciar `scene.*`. `variables` sobrescreve valores depois dos defaults e do perfil (é o "começar daqui com estas variáveis" do Studio). `profile` substitui o `profile.json` só nesta sessão (para testar NG+ e finais vistos). Com `settings.reproducible_rng`, `seed` (16 hex) semeia o PCG32; sem ela, semeia o RNG comum do motor, o que ajuda a reproduzir um bug mas não garante o mesmo traço (RT §12.2). `paused: true` para no primeiro nó.
- **`preview.set_variables`** passa pelo State Manager como uma transação com origem `preview`: as mesmas validações do RT §6.2, menos a de permissão. Variáveis `sys.*` e derivadas dão `READ_ONLY`. A resposta e a notificação `state.changed` trazem as mudanças.
- **`preview.input`** é o que a automação de testes e o "repetir a partir daqui" do Studio usam. `choose` e `click` recebem o UUID da opção ou do hotspot; uma opção invisível ou desabilitada dá `accepted: false`.
- **`preview.reload`.** O runtime troca o bundle e tenta continuar na mesma cena e no mesmo nó (`resumed: "node"`). Se o nó sumiu, reinicia a cena (`"scene_restarted"`); se a cena sumiu, volta ao ponto de seleção (`"selection_point"`). Valores de variáveis são mantidos e passam pelas regras do RT §8.4. Mudanças só em `ui/`, `sets/` ou `theme.json` redesenham a tela sem mexer no jogo (`"ui_only"`).
- **`preview.show_screen`** abre uma tela de `ui/` por cima de tudo, para o Menu Editor (UI Spec §9). `simulate` finge os valores de `sys.ui.*` e `sys.endings.*`, para o autor ver o título "depois do final" sem jogar.

## 4. Notificações (Runtime → Studio)

Toda notificação tem `seq` (inteiro crescente na sessão, a partir de 1) e `phase` (estado do motor). O Studio usa `seq` para ordenar e detectar perdas.

| Notificação | Quando | Parâmetros |
|---|---|---|
| `session.closing` | O runtime vai fechar | `reason`: `window_closed`, `stop`, `error` |
| `chapter.started` / `chapter.ended` | RT §3.2, §3.3 | `chapter` |
| `scene.started` | Uma cena começa | `scene`, `chapter`, `selection_count`, `reason`: o `reason` da seleção (§4.3); `entry` quando é a `entry_scene` do capítulo (RT §3.2, sem passar pelo Scheduler); `start` quando o Preview forçou a cena com `preview.start({scene})` |
| `scene.ended` | Fim de cena (RT §5.4) | `scene`, `then` |
| `node.entered` | Antes de executar cada nó | `scene`, `node`, `type` |
| `state.changed` | Cada transação aplicada | `changes` (`{variable, old, new}`), `source`: `scene`, `choice`, `plugin:<id>`, `ui`, `preview`, `system` |
| `event.emitted` | Evento entregue pelo Event Bus | `name`, `payload`, `source` |
| `scheduler.evaluated` | Cada ponto de seleção | `SchedulerEvaluation` (§4.3) |
| `activity.started` / `activity.ended` | RT §5.3 | `activity`, `scene`, `node`; no fim, `outcome`, `skipped`, `failed` |
| `game.ended` | RT §3.4 | `ending` |
| `log` | Mensagem do runtime | `level` (`debug`, `info`, `warning`, `error`), `message`, `scene`?, `node`? |
| `error` | Erro de conteúdo (RT §9) | `code`, `message`, `scene`?, `node`?, `variable`? |
| `plugin.log` / `plugin.permission_denied` / `plugin.faulted` | Modo desenvolvedor (Plugin SDK §12.3) | `plugin` e, conforme o caso, `level`/`message`, `capability`/`call`, `error` |

### 4.1. Volume

`node.entered` e `state.changed` saem a cada nó. Em `skip` ou num laço longo, o runtime PODE agrupar notificações do mesmo tipo em um quadro a cada 50 ms (`params.batch`, uma lista); a ordem e os `seq` continuam valendo.

### 4.2. Ordem

Para um mesmo nó: `node.entered` → `state.changed` (efeitos do nó) → `event.emitted` (eventos que o nó enfileirou, depois de entregues). No ponto de seleção: `scene.ended` → `scheduler.evaluated` → `scene.started`. Os vetores de conformidade `flow` (spec 08 §4) usam essa mesma ordem como traço.

### 4.3. `SchedulerEvaluation`

O formato do RT §11 continua valendo, agora com schema:

```json
{ "selection_count": 4, "chapter": "<uuid>", "action": "start_scene", "chosen": "<uuid>", "reason": "fallback",
  "candidates": [
    { "scene": "<uuid>", "eligible": false, "blocked_by": "max_plays", "detail": { "plays": 1, "max_plays": 1 } },
    { "scene": "<uuid>", "eligible": false, "blocked_by": "conditions",
      "failed": [{ "path": "conditions[1]", "variable": "global.fishing_skill", "operator": "greater_than_or_equal",
                   "expected": 10, "actual": 3 }] } ],
  "request_refused": { "scene": "<uuid>", "by": "content" } }
```

- `action`: `start_scene`, `exit_chapter`, `end_game`; `chosen` é `null` quando nenhuma cena começa.
- `reason`: `request`, `plugin_request`, `priority`, `tie_break`, `fallback`, `completion`, `exhausted`.
- `blocked_by`: `mode_manual`, `max_plays`, `cooldown`, `exclusive_group`, `conditions`, `lower_priority`, `tie_break`.
- `failed` lista as comparações falsas que decidiram o resultado, com o caminho dentro de `conditions` (`conditions[1].any[0]`). Num `any`, lista todas as alternativas falsas.
- `candidates` fica vazia quando a decisão sai antes da etapa 4 (RT §4.3).

## 5. `GameState`

O resultado de `preview.start` e `preview.get_state`:

| Campo | Conteúdo |
|---|---|
| `phase` | Estado do motor (RT §3) |
| `preview` | `RUNNING` ou `PAUSED` |
| `chapter`, `scene`, `node` | Posição atual (ou `null`) |
| `variables` | `{ id qualificado → valor }` de todas as variáveis legíveis no ponto atual, inclusive `sys.*` e derivadas |
| `history` | Igual a `save.schema.json → state.history` |
| `stage` | Igual a `save.schema.json → state.scene.stage` |
| `backlog` | As últimas 50 entradas, já com texto no idioma atual |
| `plugins` | Por plugin: `enabled`, `faulted`, `activity` em curso |
| `rng` | `seed` e `state` (só com `reproducible_rng`) |

Valores `integer` e `number` vão como números JSON; o Studio usa o tipo da definição da variável para distinguir `2` de `2.0`.

## 6. Erros

As respostas de erro seguem o JSON-RPC 2.0. `error.data.code` traz um código legível, que o Studio usa para escolher a mensagem:

| `error.code` | `error.data.code` | Quando |
|---|---|---|
| -32700, -32600, -32601, -32602 | — | Erros padrão do JSON-RPC: JSON inválido, requisição inválida, método inexistente, parâmetros inválidos |
| -32001 | `UNAUTHENTICATED` | Mensagem antes do `hello` válido |
| -32002 | `UNSUPPORTED_VERSION` | MAJOR do protocolo ou `format_version` do bundle sem suporte |
| -32003 | `INVALID_PREVIEW_STATE` | Método fora dos estados da tabela do §3 (`data.state` diz o atual) |
| -32004 | `BUNDLE_INVALID` | Bundle ausente, ilegível ou com erro de schema (`data.path`, `data.detail`) |
| -32005 | `NOT_FOUND` | Capítulo, cena, nó, opção, hotspot, tela ou plugin inexistente (`data.kind`, `data.id`) |
| -32006 | `STATE_REJECTED` | Escrita recusada pelo State Manager; `data.vn_code` é o código do RT §6.2 (`READ_ONLY`, `TYPE_MISMATCH`, `OUT_OF_RANGE`, `CONSTRAINT_VIOLATION`…) |
| -32007 | `BUSY` | Outra requisição longa (`load`, `reload`) ainda em curso |
| -32099 | `INTERNAL` | Falha inesperada do runtime (`data.message`); o Studio oferece reabrir o Preview |

Erros de conteúdo durante o jogo (RT §9) não são respostas: saem como a notificação `error` e o jogo segue o fluxo normal.

## 7. Segurança

- Só `127.0.0.1`; o runtime nunca escuta em outras interfaces.
- O token é de uso único por processo e não vai para logs.
- `bundle_path` DEVE estar dentro da pasta de build temporária do Studio (`.vnstudio/preview/`); outro caminho dá `BUNDLE_INVALID`.
- Os builds de release não incluem o servidor de Preview: as opções `--vn-preview-*` são ignoradas fora dos builds de debug e do runtime embutido no Studio (BS §4).

## 8. Exemplo

```text
→ {"jsonrpc":"2.0","id":1,"method":"session.hello","params":{"token":"9f…","protocol":"1.0","studio_version":"0.1.0"}}
← {"jsonrpc":"2.0","id":1,"result":{"runtime_version":"1.0.0","godot_version":"4.7.2","protocol":"1.0","platform":"windows","features":["reproducible_rng","show_screen"]}}
→ {"jsonrpc":"2.0","id":2,"method":"preview.load","params":{"bundle_path":".vnstudio/preview/narrative"}}
← {"jsonrpc":"2.0","id":2,"result":{"content_hash":"sha256-…","format_version":"1.0.0","chapters":2,"scenes":5,"plugins":["vnstudio.fishing"]}}
→ {"jsonrpc":"2.0","id":3,"method":"preview.start","params":{"scene":"019a7a00-1388-…","variables":{"global.player_money":500},"paused":true}}
← {"jsonrpc":"2.0","id":3,"result":{"phase":"SCENE_RUNNING","preview":"PAUSED","scene":"019a7a00-1388-…","node":"019a7a00-2ee0-…", …}}
→ {"jsonrpc":"2.0","id":4,"method":"preview.step","params":{"until":"blocking"}}
← {"jsonrpc":"2.0","method":"node.entered","params":{"seq":1,"phase":"SCENE_RUNNING","scene":"019a7a00-1388-…","node":"019a7a00-2ee0-…","type":"background"}}
← …
← {"jsonrpc":"2.0","id":4,"result":{"node":"019a7a00-3a98-…","phase":"SCENE_RUNNING"}}
```
