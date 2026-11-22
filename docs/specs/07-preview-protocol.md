# Protocolo do Preview — v1.0.0-draft

- **Status:** rascunho para revisão
- **Base:** Runtime Spec §11; Plugin SDK §12.3; Requisitos de autoria §4; UI Spec §9
- **Schema:** [`schemas/preview-protocol.schema.json`](schemas/preview-protocol.schema.json)

O Studio mostra o jogo rodando de verdade, no próprio Runtime Godot, enquanto o autor edita. Não existe outro interpretador: o Preview é o runtime, exportado para Web no **painel** do Studio ou nativo numa **janela** (RT §11). Este documento define a conversa entre os dois: como o Studio abre o runtime, os métodos que pode chamar, as notificações que recebe e os erros. Ele detalha o RT §11, que fica como resumo.

As palavras **DEVE**, **DEVERIA** e **PODE** seguem a RFC 2119.

## 1. Transporte e sessão

As mensagens são as mesmas nos dois modos; muda só o transporte.

### 1.1. Painel (runtime Web)

1. O Studio carrega o **export Web do runtime para o Preview** (`.wasm`, `.js` e `.pck`, sem threads, BS §7.3) numa página isolada do webview, servida pelo protocolo próprio do Tauri (`vnpreview://`), sem servidor HTTP. Esse export é gerado na release do runtime e vem embutido no Studio (spec 09 §1): não é o template de exportação do jogo, que o Studio só baixa ao exportar (BS §2), então o painel funciona na primeira abertura e sem internet. O protocolo DEVE servir o `.wasm` com `Content-Type: application/wasm`, para o motor compilar em streaming. O spike serviu a página por HTTP; servir por `vnpreview://` no WebView2, na WKWebView e no WebKitGTK ainda precisa ser conferido no primeiro protótipo (README das specs, "A conferir").

   **O protocolo serve só o projeto aberto** (decisão de 2026-11-22). O handler do `vnpreview` no processo nativo do Studio responde a um mapa fixo de três prefixos e dá 404 para qualquer outro caminho, inclusive caminhos absolutos do disco:

   | Caminho no protocolo | Pasta servida |
   |---|---|
   | `/runtime/…` | Export Web do runtime para o Preview, embutido no Studio |
   | `/project/assets/…` | A pasta `assets/` do projeto aberto |
   | `/project/preview/…` | A pasta `.vnstudio/preview/` do projeto aberto (bundle do Preview e `.pck` dos plugins) |

   O Studio troca o mapa ao trocar de projeto e recusa caminhos com `..` ou que saiam da pasta depois de resolver links. A origem da página depende do sistema: `vnpreview://localhost/` no macOS e no Linux e `http://vnpreview.localhost/` no Windows (WebView2), como o Tauri expõe protocolos próprios. O Studio monta as URLs a partir dessa origem e de um dos três prefixos, e nunca põe um caminho absoluto do disco na URL (`convertFileSrc` com caminho absoluto não é usado).
2. O runtime expõe na página, via `JavaScriptBridge`, a função `vnPreview.send(text)`, por onde o Studio manda cada requisição, e entrega respostas e notificações chamando `vnPreview.onmessage(text)`, que o Studio registra antes de iniciar o motor. Cada chamada leva **uma** mensagem JSON-RPC 2.0 em texto. Lotes não são aceitos.
3. O `session.hello` vem sem `token`: a página só é acessível ao Studio. As regras de 5 segundos e de mensagem antes do `hello` valem como na janela, com o erro `UNAUTHENTICATED` no lugar do fechamento.
   
   Os plugins rodam na mesma página que a ponte. Um plugin que use `JavaScriptBridge` poderia chamar `vnPreview.onmessage` e se passar pelo runtime; por isso esse uso é W009 e a revisão do catálogo o recusa (Plugin SDK §12.2, §13.5). O Studio trata o que chega por `vnPreview.onmessage` como vindo de código não confiável: nenhuma mensagem do painel faz o Studio ler ou gravar fora de `.vnstudio/preview/` do projeto aberto (§1.4).
4. O Studio mantém a página viva entre edições: abrir o motor e o bundle custa de 1 a 5 segundos (teste de 2026-11-15), e cada edição depois disso vai por recarga incremental (§3). Fechar o painel descarta a página; não há processo para encerrar.

### 1.2. Janela (runtime nativo)

1. O Studio escolhe uma porta livre em `127.0.0.1` e gera um token aleatório de 32 bytes (hex).
2. O Studio abre o runtime com `--vn-preview-port <porta> --vn-preview-token <token>`, mais `--vn-user-dir <projeto>/.vnstudio/preview/user` quando o autor mantém os saves do Preview (§1.4) e `--remote-debug tcp://127.0.0.1:<porta>` no modo desenvolvedor (Plugin SDK §12.3).
3. O runtime abre um servidor WebSocket só em `127.0.0.1:<porta>`, aceita **uma** conexão por vez e espera `session.hello` com o token. Qualquer outra mensagem antes disso, token errado ou 5 segundos sem `hello` fecham a conexão com o código 4401. Uma segunda conexão é recusada com 4409.
4. Cada quadro de texto do WebSocket leva **uma** mensagem JSON-RPC 2.0 em UTF-8. Lotes (arrays) não são aceitos.
5. Ao fechar a janela do jogo, o runtime envia `session.closing` e fecha com 1000. Se a conexão cair, o runtime encerra sozinho em 10 segundos, para não deixar processos órfãos.
6. O binário é o Godot embutido no Studio, da versão fixada, e abre o pacote principal do runtime para o Preview (`runtime-preview.pck`, gerado na mesma release que o export Web do §1.1) com `--main-pack`. Os plugins entram como no painel (§1.3).

### 1.3. Assets e plugins no Preview

Decisão D18 (2026-11-17). O Preview não passa pelo import do editor do Godot: o Studio não reimporta nem empacota assets a cada edição.

- **Caminhos** (decisões de 2026-11-22). O bundle que o Studio grava para o Preview (`.vnstudio/preview/narrative/`) é **o mesmo** que o Build System gravaria, byte a byte: os assets do projeto ficam em `res://vn_content/assets/<caminho de assets.json>` e os do preset em `res://vn_runtime/…` (RT §2). Por isso o `content_hash` do Preview é o mesmo do jogo (BS §5.1), e os vetores de compilação valem para os dois. `preview.load` traz em `assets_base` onde está a pasta `assets/` do projeto, e o runtime em modo preview troca o prefixo `res://vn_content/assets/` por ela antes de ler os bytes:
  - **Painel:** `assets_base` é a URL `/project/assets/` do protocolo `vnpreview` (§1.1), na origem daquele sistema: `vnpreview://localhost/project/assets/` no macOS e no Linux, `http://vnpreview.localhost/project/assets/` no Windows (WebView2). O runtime codifica cada segmento do resto do caminho (RFC 3986, UTF-8 em `%xx`) antes de juntar, então acentos e espaços funcionam. `bundle_url` é `/project/preview/narrative/` na mesma origem.
  - **Janela:** `assets_base` é o caminho absoluto da pasta `assets/` do projeto, no formato do sistema. O runtime abre o arquivo pelo caminho (o Godot não abre URLs `file://`), sem codificação.

  Os assets do preset (`res://vn_runtime/…`) vêm no pacote do runtime e são carregados como num jogo. Fora do modo preview não há `assets_base`, e todo caminho é lido como `res://` normal.
- **Carregador.** Em modo preview, o runtime resolve os caminhos de `res://vn_content/assets/` pelo carregador de bytes `VNAssets`: lê os bytes e cria o recurso em memória (`ImageTexture` para PNG, JPG e WebP; SVG rasterizado na escala que o import usaria; `AudioStreamOggVorbis`, `AudioStreamMP3` ou `AudioStreamWAV`; `FontFile`). O carregador aplica ele mesmo as opções que o import do Godot aplicaria no build: o bloco `import` do asset em `assets.json`, `nine_slice`, `loop` de música, e o filtro de textura e os mipmaps do tema.
- **Mesmo resultado.** O Preview DEVE mostrar e tocar o mesmo que o jogo exportado. Só podem diferir a compressão (o build comprime texturas e áudio conforme `import`; o Preview usa os bytes originais), o tempo de carga e a memória. Qualquer outra diferença é defeito do carregador.
- **Troca.** Acrescentar, trocar ou apagar um asset vai em `preview.reload` com a troca `/assets/<id>` (§3). O runtime descarta o recurso em cache daquele id e redesenha o que estiver na tela com ele.
- **Plugins.** Nos dois modos, cada plugin entra como um pacote de recursos (`.pck`) montado em `res://vn_plugins/<namespace>/` com `ProjectSettings.load_resource_pack` (Plugin SDK §10.6). O Studio gera o `.pck` com o Godot embutido em modo headless, a partir de uma cópia do plugin em `.vnstudio/preview/plugins/<namespace>/` (import dos assets do plugin mais exportação do pacote), e só o refaz quando um arquivo do plugin muda.
- **A conferir no primeiro protótipo** (README das specs): o teste B dos assets (abrir no painel 200 imagens de 1920 × 1080 e 30 músicas, medir memória e tempo, e trocar um asset em uso); se o Godot registra os `class_name` de um `.pck` montado depois do boot; e quanto tempo leva gerar o `.pck` de um plugin a cada salvamento. Se o `class_name` falhar, os plugins entram num único `.pck` montado antes do boot do runtime, e `preview.reload_plugins` reabre o motor.

### 1.4. Dados do jogador no Preview

Decisão D21 (2026-11-17), com o `VNStorage` e a gravação pelo Studio decididos em 2026-11-22. Saves, perfil e configurações do Preview nunca se misturam com os de outro projeto nem com os do jogo instalado, e nunca ficam em `user://` (RT §8.5).

- **Padrão: em memória.** O `VNStorage` do Preview guarda tudo num dicionário. O perfil vem de `preview.start.profile` ou começa vazio; as configurações começam nos padrões do projeto (UI Spec §8). Nada sobrevive ao fechar o painel ou a janela.
- **"Manter saves do Preview"**, opção por projeto no Studio: `preview.load` com `user_data: "project"`. O runtime grava como o jogo grava (RT §8.5), mas os arquivos vão para a pasta do projeto, em `.vnstudio/preview/user/` (fora do Git, spec 09 §3.4). É a mesma pasta nos dois modos, então painel e janela veem os mesmos saves:
  - **Janela:** o Studio passa a pasta com `--vn-user-dir` (§1.2), e o `VNStorage` grava nela direto.
  - **Painel:** o runtime Web não grava no disco. `preview.load` traz em `user_files` o conteúdo atual da pasta (`{ caminho relativo → base64 }`), que o `VNStorage` põe na memória ao abrir. A cada gravação ou remoção, o runtime manda as notificações `storage.write { path, data }` (base64) e `storage.delete { path }` (§4), e o Studio as aplica em `.vnstudio/preview/user/`. O Studio recusa (e registra no log) caminho absoluto, com `..` ou fora dessa pasta, porque a mensagem vem de uma página onde também roda código de plugin (§1.1).
- O `profile` de `preview.start`, quando vem, substitui o perfil só naquela sessão, nos dois casos: não é gravado.

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
| `session.hello` | `CONNECTED` | `token` (só na janela), `protocol`, `studio_version` | `runtime_version`, `godot_version`, `protocol`, `platform`, `features` |
| `preview.load` | `READY`, `LOADED` | `bundle_path` (janela) ou `bundle_url` (painel, URL `/project/preview/narrative/` do protocolo `vnpreview`, §1.1 e §1.3): a pasta com a forma canônica (RT §2), igual à do build; `assets_base`: onde está a pasta `assets/` do projeto (§1.3); `locale`?; `user_data`?: `memory` (padrão) ou `project` (§1.4); `user_files`? (painel com `user_data: "project"`, §1.4) | `content_hash`, `format_version`, `chapters`, `scenes`, `plugins` |
| `preview.start` | `LOADED` | `chapter`?, `scene`?, `node`?, `variables`?, `profile`?, `content_filter`?, `seed`?, `paused`? | `GameState` |
| `preview.stop` | `RUNNING`, `PAUSED` | — | `{}` (volta a `LOADED`) |
| `preview.pause` / `preview.resume` | `RUNNING` / `PAUSED` | — | `{ node }` |
| `preview.step` | `PAUSED` | `until`: `node` (padrão), `blocking`, `scene_end`, `selection` | `{ node, phase }` (continua `PAUSED`) |
| `preview.input` | `RUNNING`, `PAUSED`; em `LOADED`, só `play_activity` e as ações de atividade do modo livre | `action`: `advance`, `choose` (`option`), `click` (`hotspot`), `skip_activity`, `cancel_activity`, `complete_activity` (`outcome`, `payload`?), `play_activity` (`activity`: `<namespace>.<atividade>`, `params`?) | `{ accepted }` |
| `preview.set_variables` | `PAUSED`, ou `RUNNING` fora de `ACTIVITY` | `variables`: `{ id qualificado → valor }` | `{ changes }` |
| `preview.get_state` | qualquer depois de `load` | `include`: lista de `variables`, `history`, `stage`, `backlog`, `plugins` (padrão: todos) | `GameState` |
| `preview.explain_selection` | `RUNNING`, `PAUSED` | `scene`? | `SchedulerEvaluation` (§4.3), sem alterar o estado |
| `preview.reload` | depois de `load` | `patch` (incremental) ou `bundle_path`/`bundle_url` com `changed` (completa) | `{ content_hash?, resumed }` |
| `preview.reload_plugins` | depois de `load` | `ids` | `{ reloaded, activity_restarted }` |
| `preview.show_screen` | `LOADED`, `RUNNING`, `PAUSED` | `screen` (id de `ui/`), `simulate`? (`has_save`, `in_game`, `platform`, `endings`, `content_filter`, `content_filter_available`, `last_activity_outcome`, `last_record_rank`, `seen_assets`, `gallery_unlock_all`) | `{}` |
| `preview.set_setting` | depois de `load` | `setting` (um `bind` da UI Spec §8), `value` | `{}` |
| `preview.set_locale` | depois de `load` | `locale` | `{}` |

Detalhes:

- **`preview.start`.** Sem `scene`, começa um jogo novo (RT §3.1) no `chapter` dado ou no `start_chapter`. Com `scene`, entra no capítulo da cena sem rodar a `entry_scene` e começa a cena; com `node`, começa nesse nó, depois de instanciar `scene.*`. `variables` sobrescreve valores depois dos defaults e do perfil (é o "começar daqui com estas variáveis" do Studio). `profile` substitui o `profile.json` só nesta sessão (para testar NG+, finais vistos e a galeria; §1.4). `content_filter` liga ou desliga o modo stream desde o início, sem mexer nas configurações guardadas. Com `settings.reproducible_rng`, `seed` (16 hex) semeia o PCG32; sem ela, semeia o RNG comum do motor, o que ajuda a reproduzir um bug mas não garante o mesmo traço (RT §12.2). `paused: true` para no primeiro nó.
- **`preview.set_variables`** passa pelo State Manager como uma transação com origem `preview`: as mesmas validações do RT §6.2, menos a de permissão. Variáveis `sys.*` e derivadas dão `READ_ONLY`. A resposta e a notificação `state.changed` trazem as mudanças.
- **`preview.input`** é o que a automação de testes e o "repetir a partir daqui" do Studio usam. `choose` e `click` recebem o UUID da opção ou do hotspot; uma opção invisível ou desabilitada dá `accepted: false`. `complete_activity` conclui a atividade em curso com `outcome` (um dos `outcomes` declarados) e `payload` (validado contra o `result_schema`), como se o plugin chamasse `complete` (Plugin SDK §6): é o que o painel usa para plugins sem `web` (Plugin SDK §10.6). As ações de atividade fazem o que o jogador faria (decisão de 2026-11-22):
  - `skip_activity`: na história, pula como o botão "Pular minijogo" da pausa, com `default_outcome` (RT §5.3, passo 7); `accepted: false` se a atividade não é `skippable` ou se é do modo livre.
  - `cancel_activity`: no modo livre, sai como o "Sim" de "Sair do minijogo?" e volta com `cancelled` (Plugin SDK §6.1); na história, `accepted: false`, porque a história não tem saída sem resultado.
  - `play_activity`: em `LOADED`, roda a atividade no modo livre como a ação de menu do mesmo nome (UI Spec §4), com os `params` de `free_play` sobrepostos pelos dados; `accepted: false` sem `free_play` (P020). O estado continua `LOADED`, e as notificações `activity.*` saem com `mode: "free_play"`.
- **`preview.reload`.** Tem duas formas:
  - **Incremental** (`patch`): uma lista de trocas `{ file, pointer, value? }` sobre a forma canônica (RT §2). `file` é `bundle.json`, `licenses.json` (ponteiro `/entries`) ou `locales/<idioma>.json`. `pointer` é um JSON Pointer (RFC 6901) até uma entidade inteira: em `bundle.json`, `/scenes/<uuid>`, `/chapters/<uuid>`, `/characters/<uuid>`, `/ui/<id>`, `/sets/<id>`, `/assets/<id>` ou `/theme`; nos idiomas, `/strings/<caminho de texto>`, com cada `/` do caminho escrito `~1`, como manda a RFC. Com `value`, a entidade é criada ou substituída; sem `value`, é removida. O Studio já manda as entidades compiladas, com defaults resolvidos, como o Build System as gravaria. O runtime aplica a lista inteira na memória e revalida só o que depende dela, sem reler o bundle nem recalcular o `content_hash` (o resultado vem sem ele). É o que o Studio manda a cada edição, e DEVERIA levar menos de 50 ms num projeto grande. No teste de 2026-11-15 (bundle de 3,55 MB, 405 cenas; README das specs), o p95 ficou em 4,6 ms no motor do WebView2 (Windows, com GPU), 18 ms na WKWebView (macOS), 20 ms no Chromium e 40 ms no WebKitGTK (Linux, sem GPU); reler o bundle inteiro levava de 1 a 2,4 s, quase tudo para buscar o arquivo e calcular o hash. Trocas em `/project`, `/variables` e `/aliases`, e mudanças em `plugins.json`, exigem a forma completa (`BUNDLE_INVALID` com `data.detail: "full_reload_required"`), porque mudam a estrutura do estado.
  - **Completa** (`bundle_path` ou `bundle_url`, e `changed` com os caminhos do projeto que mudaram): relê o bundle e recalcula o `content_hash`. O Studio usa ao mudar o projeto, as variáveis ou os plugins, quando uma recarga incremental falha e a cada 50 recargas incrementais, para conferir que o estado na memória bate com o disco.

  Nas duas formas, o runtime tenta continuar na mesma cena e no mesmo nó (`resumed: "node"`). Se o nó sumiu, reinicia a cena (`"scene_restarted"`); se a cena sumiu, volta ao ponto de seleção (`"selection_point"`). Valores de variáveis são mantidos e passam pelas regras do RT §8.4. Mudanças só em `ui/`, `sets/` ou `theme.json` redesenham a tela sem mexer no jogo (`"ui_only"`). Uma troca de `patch` com erro de schema dá `BUNDLE_INVALID` (`data.path` aponta a troca) e nada é aplicado.
- **`preview.reload_plugins`.** Na janela, recarrega scripts e cenas do disco (Plugin SDK §12.3). No painel, o Studio reempacota o plugin como `.pck` e o runtime o carrega de novo com `ProjectSettings.load_resource_pack`, substituindo os recursos em cache (Plugin SDK §10.6).
- **`preview.show_screen`** abre uma tela de `ui/` por cima de tudo, para o Menu Editor (UI Spec §9). `simulate` finge os valores de `sys.ui.*` e `sys.endings.*`, para o autor ver o título "depois do final" sem jogar: `content_filter` e `content_filter_available` fingem as variáveis do modo stream; `last_activity_outcome` e `last_record_rank`, as do fim de um minijogo; `seen_assets` finge a lista do perfil para a galeria, e `gallery_unlock_all: true` mostra a galeria inteira desbloqueada ("Ver como se tudo estivesse desbloqueado", Req §11.1). Os valores fingidos valem só enquanto a tela está aberta.
- **`preview.set_setting`** muda uma configuração do jogador como se ele a tivesse mudado numa tela (UI Spec §8): aplica na hora e emite o evento correspondente, por exemplo `sys.content_filter_changed` para `content_filter` (RT §5.5). É o botão "Modo stream" da barra do Preview (Req §11.2). Com `user_data: "memory"`, a mudança vale só na sessão.

## 4. Notificações (Runtime → Studio)

Toda notificação tem `seq` (inteiro crescente na sessão, a partir de 1) e `phase` (estado do motor). O Studio usa `seq` para ordenar e detectar perdas.

| Notificação | Quando | Parâmetros |
|---|---|---|
| `session.closing` | O runtime vai fechar | `reason`: `window_closed`, `stop`, `error` |
| `storage.write` / `storage.delete` | Só no painel com `user_data: "project"`: o `VNStorage` gravou ou apagou um arquivo (§1.4) | `path` (relativo, com `/`), e em `storage.write` `data` (base64) |
| `chapter.started` / `chapter.ended` | RT §3.2, §3.3 | `chapter` |
| `scene.started` | Uma cena começa | `scene`, `chapter`, `selection_count`, `reason`: o `reason` da seleção (§4.3); `entry` quando é a `entry_scene` do capítulo (RT §3.2, sem passar pelo Scheduler); `start` quando o Preview forçou a cena com `preview.start({scene})` |
| `scene.ended` | Fim de cena (RT §5.4) | `scene`, `then` |
| `node.entered` | Antes de executar cada nó. Um nó pulado pelo modo stream (`censor`, RT §5.5) não executa e não gera `node.entered` | `scene`, `node`, `type` |
| `state.changed` | Cada transação aplicada | `changes` (`{variable, old, new}`), `source`: `scene`, `choice`, `plugin:<id>`, `ui`, `preview`, `system` |
| `event.emitted` | Evento entregue pelo Event Bus | `name`, `payload`, `source` |
| `scheduler.evaluated` | Cada ponto de seleção | `SchedulerEvaluation` (§4.3) |
| `activity.started` / `activity.ended` | RT §5.3, Plugin SDK §6.1 | `activity`, `mode` (`story` ou `free_play`), `scene` e `node` (só em `story`); no fim, `outcome` (no modo livre, também `cancelled` ou `failed`), `skipped`, `failed` |
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

- Na janela, só `127.0.0.1`; o runtime nunca escuta em outras interfaces. O token é de uso único por processo e não vai para logs.
- No painel, a página do runtime só é servida ao webview do Studio, sem acesso à rede: a CSP limita `connect-src` ao protocolo `vnpreview:`.
- `bundle_path` e `bundle_url` DEVEM apontar para a pasta de build temporária do Studio (`.vnstudio/preview/`); outro caminho dá `BUNDLE_INVALID`.
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
→ {"jsonrpc":"2.0","id":5,"method":"preview.reload","params":{"patch":[{"file":"bundle.json","pointer":"/scenes/019a7a00-1388-…","value":{…}}]}}
← {"jsonrpc":"2.0","id":5,"result":{"resumed":"node"}}
```

O exemplo é da janela; no painel, o `hello` vem sem `token` e o `load` usa `bundle_url`.
