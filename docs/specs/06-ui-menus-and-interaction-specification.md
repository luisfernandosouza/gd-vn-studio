# Menus, botões e interação — Especificação v1.0.0-draft

- **Status:** rascunho para revisão
- **Base:** pedido de 2026-11-14 (o autor monta o menu da novel, escolhe onde fica cada botão, personaliza os botões e cria botões que interagem com o cenário do menu e das cenas); [Narrative Data Model](01-narrative-data-model.md) §8–10; [Runtime Spec](02-narrative-runtime-specification.md) §5 e §8; [Requisitos de autoria](04-studio-authoring-requirements.md) §11–12
- **Schemas:** [`ui-screen.schema.json`](schemas/ui-screen.schema.json) (telas), [`set.schema.json`](schemas/set.schema.json) (cenários compostos), [`theme.schema.json`](schemas/theme.schema.json) (estilos), `scene.schema.json` (nó `interact`, `background.set`), `save.schema.json → PlayerSettings`
- **Exemplo:** [`examples/demo-project/ui/title.json`](examples/demo-project/ui/title.json), [`ui/settings.json`](examples/demo-project/ui/settings.json), [`sets/beach_title.json`](examples/demo-project/sets/beach_title.json)

Este documento define como o autor monta **todas as telas** da novel (título, pausa, salvar/carregar, configurações, galeria, créditos, HUD durante as cenas e telas próprias), como personaliza os botões, e como cria elementos que **interagem com o cenário**, tanto no menu quanto dentro das cenas.

As palavras **DEVE**, **DEVERIA** e **PODE** seguem a RFC 2119.

---

## 1. Princípios

1. **Tudo é dado, editado visualmente.** Uma tela é um arquivo JSON com elementos posicionados; o autor arrasta, solta e ajusta num editor visual (Menu Editor, §9). Nada exige código nem o Godot.
2. **Estilo separado do layout.** `theme.json` diz **como** um botão é (imagens, fonte, cores, animações, sons); a tela diz **onde** ele fica e **o que** ele faz. Trocar o estilo muda todos os botões que o usam.
3. **Interação cosmética × interação narrativa.** Clicar num objeto do cenário para acender uma lâmpada é **cosmético**: não mexe em variáveis e pode acontecer a qualquer momento. Clicar num objeto para investigar e mudar a história é **narrativo**: só acontece num nó `interact` da cena, que funciona como uma escolha espacial. Isso mantém o Scene Scheduler e o Narrative Engine como autoridades sobre a história (ADD §15).
4. **Funciona sem mouse.** Todo elemento clicável é alcançável por teclado, gamepad e toque, com foco visível (Req §12).
5. **Um preset sempre funciona.** Um projeto novo já vem com todas as telas prontas a partir do preset do tema (no v1, só `classic`); o autor só altera o que quiser.

## 2. Arquivos

```text
meu-projeto/
├── theme.json              # estilos: fontes, cores, caixa de diálogo, estilos de botão
├── ui/                     # uma tela por arquivo
│   ├── title.json          # menu inicial
│   ├── pause.json          # menu de pausa
│   ├── save.json, load.json
│   ├── settings.json       # configurações
│   ├── gallery.json, credits.json
│   ├── hud.json            # botões sobre a cena durante o jogo (opcional)
│   └── extras.json         # telas próprias do autor (qualquer id)
└── sets/                   # cenários compostos (camadas + objetos clicáveis), usados por telas e cenas
    └── beach_title.json
```

| Arquivo | Schema | Quem escreve |
|---|---|---|
| `ui/<id>.json` | `ui-screen.schema.json` | Studio (Menu Editor) |
| `sets/<id>.json` | `set.schema.json` | Studio (Menu Editor / Scene Editor) |

Tela ausente em `ui/` vem do preset. O id da tela é o nome do arquivo e segue o formato `Id` (`^[a-z][a-z0-9_]{0,63}$`). As telas `title`, `pause`, `save`, `load`, `settings`, `gallery`, `credits` e `hud` têm papel fixo no runtime (§6); qualquer outro id é uma **tela própria**, aberta por uma ação `open_screen`.

### 2.1. Presets

Um preset é um projeto parcial, no mesmo formato e validado pelos mesmos schemas: `presets/<nome>/theme.json`, `presets/<nome>/ui/*.json` e `presets/<nome>/locales/<lang>.json`. O v1 traz o preset **`classic`** ([`presets/classic/`](presets/classic/)); `modern` e `minimal` ficam para depois. O projeto escolhe o preset em `theme.json → preset`, e sem o campo (ou sem `theme.json`) vale `classic`. O schema só aceita presets que existem, então um nome desconhecido é erro de validação, e não uma falha do compilador. O compilador do bundle (Build System §5.1) aplica o preset assim:

- **Tema:** fusão profunda do `theme.json` do preset com o do projeto; o projeto vence em cada chave. O preset define o estilo padrão de cada tipo de elemento (`button`, `choice`, `slot`, `slider`, `toggle`, `select`, `hotspot`, `label`), mais `title_label` e `hud_button`, e o layout padrão da caixa de texto, da plaquinha de nome e das escolhas.
- **Telas:** uma tela do projeto substitui inteira a do preset com o mesmo id. O `classic` traz `title`, `pause`, `save`, `load`, `settings`, `gallery`, `credits`, `hud`, `backlog` (aberta por `open_backlog`) e `minigames`.
- **`gallery`:** só entra se o projeto tiver galeria (`project.json → gallery`, Data Model §10.5); sem ela, a tela some (mesmo a do projeto, aviso U014) e `sys.ui.has_gallery` é falso. A tela do preset mostra só as abas das seções ativas (`visible_if` com `sys.ui.gallery_endings`, `sys.ui.gallery_images` e `sys.ui.gallery_music`) e abre na primeira delas; o botão "Galeria" do título tem `visible_if` com `sys.ui.has_gallery`.
- **`minigames`:** se o projeto não tiver a própria, o compilador a gera a partir das atividades de plugin com `free_play`: um botão `play_activity` por atividade e o quadro de recordes do plugin. Sem nenhuma atividade com `free_play`, a tela some e `sys.ui.has_minigames` é falso.
- **Textos:** o preset traz as traduções dos seus textos (`ui/<tela>/<elemento>`) e das mensagens do runtime (`runtime/…`) para os idiomas do produto (Req §9.1). As traduções do projeto vencem as do preset. Para um idioma do jogo, o compilador procura a tag exata no preset, depois a tag base (`es-MX` usa `es`) e, na falta das duas, usa o inglês. Nesse último caso, as telas do preset e as mensagens do runtime aparecem em inglês até o projeto traduzi-las, e o validador avisa (W021) quando faltam chaves `runtime/`.
- **Título do jogo:** um texto do preset igual a `$project.title` é trocado pelo `title` do projeto.
- **Fontes:** os ids `preset/font_*` são reservados e apontam para fontes embutidas no runtime (`res://vn_runtime/presets/fonts/…`). Um projeto pode sobrescrever um desses ids em `assets.json`.

## 3. Tela

```json
{
  "id": "title",
  "kind": "title",
  "set": "beach_title",
  "music": "music/waves",
  "transition": { "kind": "fade", "duration": 0.6 },
  "focus_start": "btn_new_game",
  "elements": [ … ],
  "on_open": [ { "do": "set_state", "target": "set:sky", "state": "night", "if": [{ "variable": "sys.endings.festival_ending", "operator": "equals", "value": true }] } ]
}
```

| Campo | Significado |
|---|---|
| `kind` | `title`, `pause`, `save`, `load`, `settings`, `gallery`, `credits`, `hud` ou `custom` |
| `set` | Cenário composto ao fundo (§5); ou `background` (um asset só) |
| `music` | Música da tela; ausente = continua a atual (na pausa, a música da cena segue com volume reduzido) |
| `transition` | Transição ao abrir e fechar |
| `modal` | Só telas `custom`: abre por cima da tela atual (padrão `true`) ou a substitui |
| `focus_start` | Elemento com foco inicial no teclado/gamepad |
| `elements` | Elementos posicionados (§3.1) |
| `on_open`, `on_close` | Ações ao abrir e fechar (§4) |
| `back` | O que `vn_cancel` (Esc, botão B) faz; padrão `close_screen` (no título: nada) |

### 3.1. Elementos

Todo elemento tem `id` (legível, único na tela), `type` e uma **posição**:

| Campo | Significado |
|---|---|
| `position` | `[x, y]` em fração da resolução base (`settings.resolution`), de 0 a 1 |
| `pivot` | Ponto do elemento que fica em `position`, em fração do elemento; padrão `[0.5, 0.5]` |
| `size` | `[largura, altura]` em pixels da resolução base; ausente = tamanho do conteúdo |
| `anchor` | `stretch` (padrão: escala junto com a tela) ou `edge` (gruda na borda mais próxima e mantém o tamanho; para HUD em telas ultrawide) |
| `z` | Ordem de desenho |
| `visible_if`, `enabled_if` | Condições (Data Model §5) |
| `style` | Estilo do tema (§7); ausente = estilo padrão do tipo |
| `tooltip` | Texto ao passar o mouse ou focar |
| `shortcut` | Ação de input que dispara o elemento (ex.: `vn_quick_save`) |
| `focus` | Vizinhos de navegação `{up, down, left, right}`; ausente = calculado pela posição |
| `appear` | Animação de entrada (§7.3), com `delay` para entrar em sequência |

| `type` | Para quê | Campos próprios |
|---|---|---|
| `button` | Botão com texto, ícone ou imagem | `text`, `icon`, `actions` |
| `image` | Imagem decorativa | `asset`, `animation` |
| `label` | Texto (aceita interpolação e marcação) | `text`, `align` |
| `hotspot` | Área clicável sem visual próprio, sobre o cenário | `area` (§5.2), `cursor`, `highlight`, `actions` |
| `slider` | Controle deslizante ligado a uma configuração | `bind`, `min`, `max`, `step` |
| `toggle` | Liga/desliga ligado a uma configuração | `bind` |
| `select` | Lista de opções ligada a uma configuração | `bind`, `options` (ausente = opções do próprio `bind`) |
| `slot_grid` | Grade de slots de save | `mode` (`save`/`load`), `columns`, `rows`, `slot_style`. Com o modo stream ligado, miniaturas `thumbnail_sensitive` aparecem como `content_filter.placeholder` (RT §8.5) |
| `gallery_grid` | Grade da galeria | `source` (`endings`, `images`, `music`), `columns`, `locked_asset`. A seção de `source` tem de estar em `project.json → gallery.sections` (U012, Data Model §10.5). `endings` lista `project.json → endings`; `images` e `music` listam os assets com `gallery: true` em `assets.json` (`images`: imagens e cenários; `music`: músicas), na ordem de `gallery_order` e depois do id. Itens ainda não vistos (`profile.seen_assets`, RT §5.2) aparecem com `locked_asset` e o texto `runtime/gallery/locked`. Com o modo stream ligado (§8), cada item mostra a substituta de `censored.replace_with`; um item com `censored.hide` aparece com o placeholder e o texto `runtime/content_filter/hidden`. Ver a versão censurada desbloqueia o item (RT §5.2) |
| `backlog_list` | Histórico de falas | `max_items` |
| `container` | Agrupa e alinha elementos | `layout` (`row`, `column`, `grid`), `spacing`, `children` |
| `records_list` | Quadro de recordes de um minijogo (Plugin SDK §9.1) | `board` (`<namespace>.<quadro>`), `max_items`, `empty_text` |
| `licenses_list` | Licenças e créditos de terceiros, para a tela de créditos (Build System §4.5) | `include` (`plugins`, `fonts`, `assets`; padrão: os três). `assets` lista o `credit` dos assets do projeto que entram no jogo (Data Model §10.1) |

### 3.2. Condições no menu

No título ainda não existe partida, então `visible_if`, `enabled_if` e condições de ações só podem usar variáveis `profile`, `sys.endings.*` e as variáveis de interface abaixo (o validador confere, regra U003):

| Variável | Tipo | Significado |
|---|---|---|
| `sys.ui.has_save` | boolean | Existe algum save (para mostrar "Continuar") |
| `sys.ui.in_game` | boolean | Há uma partida em andamento (pausa, HUD) |
| `sys.ui.platform` | string | `windows`, `linux`, `macos`, `web` (ex.: esconder "Sair" no Web) |
| `sys.ui.activity` | boolean | Um minijogo está rodando |
| `sys.ui.has_minigames` | boolean | Existe ao menos uma atividade com `free_play` (botão "Minijogos") |
| `sys.ui.has_gallery` | boolean | O projeto tem galeria (botão "Galeria", Data Model §10.5) |
| `sys.ui.gallery_endings`, `sys.ui.gallery_images`, `sys.ui.gallery_music` | boolean | A seção está ativa em `project.json → gallery.sections` (abas da tela `gallery`) |
| `sys.ui.last_activity_outcome` | string | Resultado da última atividade jogada no modo livre: o `outcome` declarado no `complete`, `failed` ou `cancelled` (Plugin SDK §6.1); vazio antes da primeira |
| `sys.ui.last_record_rank` | integer | Posição do último recorde enviado no modo livre; 0 se não entrou no quadro |
| `sys.ui.content_filter` | boolean | Modo stream ligado (ex.: um selo no HUD) |
| `sys.ui.content_filter_available` | boolean | O jogador pode ligar e desligar o modo stream (há conteúdo marcado e o build não é a edição censurada); o preset esconde o controle quando é falso |

Durante a partida (pausa, HUD, telas próprias abertas no jogo), valem também as variáveis globais e de personagem.

### 3.3. Textos e tradução

Textos de telas e sets são escritos no idioma `default_locale` e traduzidos como os demais (Data Model §9):

| Texto | Caminho | Arquivo em `locales/<lang>/` |
|---|---|---|
| `text` de botão e `label`, rótulo (`label`) de controle e de hotspot | `ui/<tela>/<elemento>` | `ui/<tela>.json` |
| `tooltip` | `ui/<tela>/<elemento>/tooltip` | `ui/<tela>.json` |
| Texto de opção de `select` | `ui/<tela>/<elemento>/option/<valor>` | `ui/<tela>.json` |
| `text` da n-ésima ação `confirm` de um elemento (ou de `on_open`, `on_close`, `back`) | `ui/<tela>/<elemento>/confirm<n>` | `ui/<tela>.json` |
| `label` de hotspot de set | `sets/<set>/<hotspot>` | `sets/<set>.json` |
| `prompt`, `label` de hotspot e de `exit` do nó `interact` | `<cena>/<nó>`, `<cena>/<nó>/<hotspot>`, `<cena>/<nó>/exit` | `scenes/<cena>.json` |

`<n>` conta a partir de 1, na ordem em que as ações aparecem (inclusive dentro de `else` e `then`). No título, a interpolação segue a regra de §3.2.

## 4. Ações

Botões, hotspots e eventos de tela executam uma **lista de ações**, em ordem. Toda ação aceita `if` (condição) e `else` (outra lista).

| `do` | Parâmetros | Onde vale |
|---|---|---|
| `new_game` | — | Título |
| `continue` | — | Título (save mais recente, RT §8.5) |
| `open_screen` | `screen` | Qualquer tela |
| `close_screen` / `back` | — | Qualquer tela |
| `return_to_title` | `confirm` (padrão `true`) | Jogo |
| `quit` | `confirm` | Qualquer (escondido no Web) |
| `save` / `load` | `slot` (ausente = abre a tela) | `save`: jogo; `load`: qualquer |
| `quick_save` / `quick_load` | — | Jogo / qualquer |
| `toggle_auto`, `toggle_skip`, `hide_textbox`, `open_backlog` | — | Jogo. `open_backlog` abre a tela `backlog` |
| `set_setting` | `setting`, `value` | Qualquer |
| `play_sfx` | `asset` | Qualquer |
| `set_state` | `target`, `state` | Qualquer (§5.1) |
| `toggle_state` | `target`, `states` (lista; avança para o próximo) | Qualquer |
| `play_animation` | `target`, `animation` | Qualquer |
| `show` / `hide` / `toggle_visible` | `target` | Qualquer |
| `effects` | `effects` (Data Model §6.2) | Título: só variáveis `profile`. Jogo: qualquer variável gravável, como transação; vale para a **próxima** seleção de cena (RT §4.1) |
| `emit` | `event` (`story.*`), `payload` | Jogo |
| `open_url` | `url` | Qualquer; sempre pede confirmação; desligado no Web e com `build.allow_urls: false` |
| `confirm` | `text`, `then`, `else` | Qualquer: caixa de confirmação do tema |
| `play_activity` | `activity` (`<namespace>.<atividade>`), `params` | Fora do jogo (título e telas abertas a partir dele): joga o minijogo no modo livre (Plugin SDK §6.1) e volta à tela. Com uma partida em andamento, o botão fica oculto e a ação é recusada, mesmo numa tela própria aberta da pausa (RT §5.3) |
| `reset_profile` | `text` (opcional; padrão `runtime/confirm/reset_profile`) | Só fora do jogo (título e telas abertas a partir dele): pede confirmação e apaga o perfil, ou seja, finais, galeria, textos lidos, variáveis `profile` e recordes. Os saves ficam (RT §8.5) |

`target` aponta para um elemento da tela (`btn_new_game`), uma camada ou hotspot do cenário (`set:sky`) ou, numa cena, para o cenário em cena (`stage:lamp`).

Ações nunca escolhem nem pulam cenas. Para a história reagir a um botão do HUD (por exemplo, um "mapa"), o botão usa `effects` ou `emit`, e a próxima seleção de cena leva isso em conta (`event_since_last_selection`).

## 5. Cenários compostos e interação cosmética

### 5.1. Set

Um **set** é um cenário feito de camadas, com estados e objetos clicáveis. O mesmo formato serve para o fundo do menu e para o fundo das cenas.

```json
{
  "id": "beach_title",
  "layers": [
    { "id": "sky", "asset": "bg/sky_day", "parallax": 0.01,
      "states": { "night": { "asset": "bg/sky_night" } } },
    { "id": "sea", "asset": "bg/sea", "animation": { "kind": "float", "amount": 6, "duration": 4, "loop": true } },
    { "id": "lamp", "asset": "obj/lamp_off", "position": [0.8, 0.62],
      "states": { "on": { "asset": "obj/lamp_on" } } }
  ],
  "hotspots": [
    { "id": "lamp_click", "area": { "layer": "lamp" }, "cursor": "use", "highlight": "outline",
      "on_press": [ { "do": "toggle_state", "target": "lamp", "states": ["default", "on"] },
                    { "do": "play_sfx", "asset": "sfx/click" } ] }
  ]
}
```

- `layers`: imagens (ou vídeo `.ogv` em loop) empilhadas; `position` e `pivot` como os elementos; `parallax` move a camada com o mouse ou o giroscópio (desligado com `reduce_motion`).
- `states`: variações nomeadas de cada camada (`asset`, `visible`, `opacity`, `tint`). O estado inicial é `default`.
- `hotspots`: áreas clicáveis **cosméticas**, com `on_hover`, `on_press` e `on_release`. Só aceitam ações cosméticas: `set_state`, `toggle_state`, `play_animation`, `play_sfx`, `show`, `hide`, `toggle_visible`. Qualquer outra ação é erro U004.

Numa cena, `background` aceita `set` no lugar de `asset`. Enquanto o set está em cena, seus hotspots respondem sempre que o jogador está numa fala ou escolha (não durante transições nem minijogos). O estado das camadas vai no save (`state.scene.stage.set_states`).

### 5.2. Áreas clicáveis

| `area` | Significado |
|---|---|
| `{ "rect": [x, y, w, h] }` | Retângulo em fração da tela |
| `{ "polygon": [[x, y], …] }` | Polígono em fração da tela (3 a 32 pontos) |
| `{ "layer": "lamp" }` | Os pixels não transparentes da camada (máscara alfa) |
| `{ "character": "<uuid>" }` | O sprite do personagem em cena (só em nós `interact`) |

`cursor`: `default`, `look`, `talk`, `use`, `walk` ou um asset. `highlight`: `none`, `outline`, `glow`, `tint` (ao passar o mouse e ao focar). Com `PlayerSettings.show_hotspots`, todos os hotspots ficam destacados (ajuda de acessibilidade).

## 6. Interação narrativa: nó `interact`

Para cliques que **mudam a história**, a cena usa o nó `interact`, uma escolha espacial: o jogo para, mostra as áreas e espera o jogador clicar.

```json
{ "id": "…", "type": "interact",
  "prompt": "O que você quer olhar?",
  "hotspots": [
    { "id": "…", "label": "Concha", "area": { "rect": [0.2, 0.7, 0.08, 0.06] },
      "cursor": "look", "once": true, "goto": "…" },
    { "id": "…", "label": "Alice", "area": { "character": "…" }, "cursor": "talk",
      "visible_if": [{ "variable": "character.alice.met", "operator": "equals", "value": true }],
      "effects": [{ "op": "add", "variable": "character.alice.affection", "value": 1 }], "goto": "…" }
  ],
  "exit": { "label": "Seguir em frente", "goto": "…" },
  "record": "scene.last_clicked" }
```

- Semântica igual à da `choice` (Data Model §8.2): `visible_if`, `enabled_if`, `effects` + `record` numa transação, `goto` (ausente: `next`). Sem hotspot visível, segue `next` (aviso W006).
- `once: true`: o hotspot some depois de usado nesta execução da cena. O padrão "investigar até sair" é o `goto` de cada hotspot voltar ao próprio nó `interact` depois das falas; `exit` é o botão de saída (opcional).
- `label` é traduzível (caminho `<cena>/<nó>/<hotspot>`) e aparece como dica e na navegação por teclado/gamepad, que percorre os hotspots em ordem.
- Os hotspots cosméticos do set em cena continuam ativos durante o `interact`.
- O save pode acontecer num nó `interact` (como numa `choice`); os hotspots `once` já usados vão em `state.scene.used_hotspots`.

## 7. Personalização de botões (tema)

### 7.1. Estilos

`theme.json → styles` define estilos com nome. Uma tela usa `"style": "gold"`; sem `style`, vale o estilo padrão do tipo (`button`, `choice`, `slot`, `slider`…).

```json
"styles": {
  "gold": {
    "extends": "button",
    "image": { "normal": "ui/btn_gold", "hover": "ui/btn_gold_hover", "pressed": "ui/btn_gold_down",
               "disabled": "ui/btn_gold_off", "focus": "ui/btn_gold_hover" },
    "font": "font/title", "font_size": 34,
    "text_color": { "normal": "#3b2400", "hover": "#000000", "disabled": "#7a6a50" },
    "padding": [24, 12, 24, 12],
    "hover": { "scale": 1.06, "offset": [0, -2], "glow": "#ffd76a", "duration": 0.12 },
    "press": { "scale": 0.97 },
    "sounds": { "hover": "sfx/hover", "press": "sfx/click" },
    "cursor": "default"
  }
}
```

| Campo | Significado |
|---|---|
| `extends` | Herda de outro estilo |
| `image` | Imagem por estado (`normal`, `hover`, `pressed`, `disabled`, `focus`, `selected`), com `nine_slice` do asset |
| `shape` | Sem imagem: `rect`, `rounded` (com `radius`), `pill`, `circle`, com `fill`, `border`, `border_width` por estado |
| `font`, `font_size`, `text_color`, `outline`, `shadow` | Texto |
| `icon_position` | `left`, `right`, `top`, `only` |
| `hover`, `press`, `focus` | Efeitos: `scale`, `offset`, `rotation`, `tint`, `glow`, `duration`, `easing` |
| `idle` | Animação contínua (§7.3) |
| `sounds` | `hover`, `press`, `disabled_press` |
| `auto_shrink` | Reduz a fonte para o texto caber (textos traduzidos ficam maiores) |

### 7.2. Fontes por idioma

`theme.json → fonts.fallbacks` lista fontes extras por sistema de escrita (`ja`, `zh-Hans`, `zh-Hant`, `ko`…). O runtime usa a fonte do estilo e, para caracteres que ela não tem, a primeira fonte de reserva do idioma atual. O validador avisa (W020) quando o projeto tem um idioma cujo alfabeto não é coberto por nenhuma fonte do tema. O preset traz as fontes Noto como reserva, incluídas no build só para os idiomas de `build.locales`.

### 7.3. Animações prontas

`animation`, `appear` e `idle` usam presets parametrizáveis: `fade`, `slide` (`from`: `left`/`right`/`top`/`bottom`), `scale`, `pulse`, `float`, `shake`, `rotate`, `blink`, com `duration`, `delay`, `amount`, `loop` e `easing`. Com `PlayerSettings.reduce_motion`, só `fade` e corte seco são usados.

## 8. Configurações do jogador

A tela `settings` liga controles (`slider`, `toggle`, `select`) a configurações por `bind`. O valor vai para `settings.json` (RT §8.5) e vale na hora.

| `bind` | Controle sugerido | Valores |
|---|---|---|
| `volume.master`, `volume.music`, `volume.ambient`, `volume.sfx`, `volume.voice` | slider | 0 a 1 |
| `display_mode` | select | `windowed`, `fullscreen`, `borderless` (escondido no Web) |
| `resolution` | select | Lista de `project.json → settings.display.resolutions`, filtrada pelo tamanho do monitor (escondido no Web e em tela cheia exclusiva) |
| `vsync` | toggle | — |
| `fps_limit_vn` | select | `30`, `60`, `120`, `144`, `0` (sem limite); padrão `60` |
| `fps_limit_activity` | select | Mesmas opções; padrão `0` (sem limite) |
| `text_speed`, `auto_delay`, `skip_unread` | slider / toggle | RT §8.5 |
| `locale` | select | Idiomas do build |
| `text_scale`, `reduce_motion`, `subtitles`, `high_contrast`, `show_hotspots` | slider / toggle | Req §12 |
| `content_filter` | toggle | Modo stream: mostra a versão censurada (Data Model §10.4, RT §5.5) |

**FPS da novel × FPS dos minijogos.** Uma VN quase parada não precisa de 144 quadros por segundo (gasta bateria e esquenta notebook), mas um minijogo de ação precisa. O runtime aplica `fps_limit_vn` fora de atividades e troca para `fps_limit_activity` quando uma atividade de plugin começa, voltando ao terminar (RT §5.3). Uma atividade PODE declarar `min_fps` no manifesto (Plugin SDK §6). Se o limite vem do padrão do projeto e é menor que `min_fps`, o runtime usa `min_fps` durante aquela atividade. Se o próprio jogador gravou o limite em `settings.json` (por exemplo, para economizar bateria), vale a escolha dele, e a tela de configurações mostra um aviso ao lado do controle. No Web, o navegador controla a taxa; os dois controles ficam escondidos.

O autor escolhe quais controles aparecem e onde; um controle omitido usa o valor padrão do projeto (`project.json → settings`) ou, na falta dele, o padrão do runtime:

| Configuração | Padrão |
|---|---|
| `locale` | Idioma do sistema, se o jogo o tiver; senão `default_locale` |
| `text_speed` | 40 caracteres por segundo (`0` = instantâneo) |
| `auto_delay` | 1,5 s |
| `skip_unread` | `false` |
| `display_mode` | `windowed` |
| `resolution` | A primeira de `settings.display.resolutions` que cabe no monitor |
| `vsync` | `true` |
| `fps_limit_vn` / `fps_limit_activity` | 60 / 0 |
| `volume.master`, `volume.music`, `volume.ambient`, `volume.sfx` | 0,8 |
| `volume.voice` | 1,0 |
| `text_scale` | 1,0 |
| `reduce_motion`, `high_contrast`, `show_hotspots` | `false` |
| `subtitles` | `true` |
| `content_filter` | `project.json → content_filter.default`, senão `false`; sempre `true` na edição censurada |

**Modo stream.** O preset `classic` traz o controle "Modo stream (versão censurada)" na tela de configurações, visível só com `sys.ui.content_filter_available`. O autor PODE pôr o mesmo controle (ou uma ação `set_setting` de `content_filter`) na pausa ou no HUD, para o streamer ligar sem sair da cena; a mudança vale na hora (RT §5.5). Sem nenhum controle, `ask_on_first_launch` nem `default: true`, o validador avisa (W024). Na edição censurada (Build System §5.4), o runtime esconde todo controle e ignora `set_setting` de `content_filter`.

Os mesmos valores estão como `default` em `save.schema.json → PlayerSettings`. O antigo campo `fullscreen` foi removido: o modo de tela é só `display_mode`.

## 9. Menu Editor (Studio)

- **Canvas** na resolução base, com guias de área segura, encaixe em grade e nos outros elementos, e alternância de prévia entre 16:9, 16:10, 21:9, 4:3 e retrato.
- **Biblioteca de elementos** (botão, imagem, texto, hotspot, slider…) arrastável; **biblioteca de estilos** do tema, aplicável com um clique.
- **Construtor de ações em frases**: "Ao clicar: abrir *Configurações*", "Ao passar o mouse: trocar *lâmpada* para *acesa*".
- **Estados**: o autor alterna entre normal, hover, pressionado, desabilitado e foco para ajustar cada um.
- **Prévia ao vivo** com mouse, teclado e gamepad, em qualquer idioma do projeto (para ver se o texto traduzido cabe).
- **Modelos de tela** prontos (§10.2) como ponto de partida.
- **Checagens**: contraste, elementos fora da tela em alguma proporção, botões sem rótulo para teclado, foco inalcançável.

## 10. Ideias de personalização

### 10.1. Botões

1. **Botões com estados desenhados**: o artista entrega 3 a 5 imagens (normal, hover, pressionado, desabilitado, foco) e o Studio monta o estilo.
2. **Botões sem imagem**: forma (pílula, arredondado, círculo) com cores e borda por estado. Dá um visual limpo sem precisar de artista.
3. **Efeitos de hover combinados**: crescer 6%, subir 2 px, brilho dourado e som de "tick", tudo num estilo reutilizável.
4. **Ícone + texto** (engrenagem + "Configurações") ou **só ícone** com dica, bom para o HUD.
5. **Entrada em cascata**: os botões do título entram deslizando um a um (`appear` com `delay` crescente).
6. **Animação ociosa** sutil no botão principal ("Novo jogo" pulsando devagar).
7. **Botão desbloqueável**: "Extras" só aparece depois de ver um final (`visible_if` com `sys.endings.*`), ou aparece com cadeado e dica "Termine a história para desbloquear".
8. **Botão com contador**: "Galeria (3/10)" usando interpolação no texto.
9. **Atalhos de teclado** mostrados no próprio botão ("[F5] Salvar rápido").
10. **Texto que se ajusta** ao idioma (`auto_shrink`), para "Configurações" caber também em alemão.

### 10.2. Layouts de menu

1. **Clássico**: coluna de botões à esquerda, arte do personagem à direita.
2. **Barra inferior**: botões em linha no rodapé, cenário ocupando a tela toda.
3. **Menu diegético**: não há botões visíveis; os objetos do cenário são o menu. A porta é "Novo jogo", o diário é "Carregar", o rádio abre "Configurações" e a janela é "Sair" (hotspots com `area.layer` e `highlight: glow`).
4. **Menu radial** em volta de um objeto central (um relógio, uma bússola).
5. **Cartas ou fotos** espalhadas na mesa, cada uma um botão, que se endireitam no hover.
6. **Livro**: o título é a capa, e as páginas viram ao abrir outras telas (`transition` de página).
7. **Tela de título que evolui**: depois de cada final, o cenário muda (estado `night`, personagem diferente, música nova) usando `on_open` com condições sobre `sys.endings`.
8. **Personagem que reage**: passar o mouse sobre "Novo jogo" faz a personagem sorrir, sobre "Sair" ela fica triste (`on_hover` → `set_state`).

### 10.3. Cenário interativo

1. **Parallax** com o mouse nas camadas do céu, mar e primeiro plano.
2. **Objetos que respondem**: lâmpada que acende, gato que mia, onda que espirra ao clicar, só cosmético.
3. **Ciclo dia/noite** no título conforme o progresso (estado escolhido em `on_open`). Usar o horário real exigiria uma variável `sys.ui.hour`, fora do v1.
4. **Investigação na cena** (nó `interact`): clicar em objetos para descobrir pistas, com hotspots `once` e um botão de saída.
5. **Conversar clicando no personagem** (`area.character`) em vez de escolher num menu.
6. **HUD temático**: um celular no canto que abre uma tela própria com "mensagens" (texto com interpolação de variáveis) e emite `story.read_messages` para a próxima cena reagir.
7. **Sala de jogos** nos extras: cada minijogo com `free_play` vira um botão `play_activity`, com o quadro de recordes (`records_list`) ao lado.
8. **Mapa clicável** como tela própria: cada local é um hotspot com `effects` em `global.next_location`, e o Scheduler escolhe a próxima cena pelo local.

### 10.4. Futuro (fora do v1)

- Widgets de plugin: plugins registram novos tipos de elemento (relógio, inventário em grade) com uma capacidade `ui.widgets`.
- Telas animadas na linha do tempo (keyframes) em vez de presets.
- Temas sazonais por data.

## 11. Validação

| Código | Nível | Regra |
|---|---|---|
| U001 | erro | Ação, `target`, `focus`, `focus_start`, `set`, área ou `board` cita elemento, camada, estado, set, tela ou quadro de recordes inexistente; id de tela ou set diferente do nome do arquivo; id repetido na tela ou no set |
| U002 | erro | Estilo inexistente no tema, ou ciclo em `extends` |
| U003 | erro | Condição de tela de título usa variável que não é `profile`, `sys.endings.*` nem `sys.ui.*` |
| U004 | erro | Ação não cosmética em hotspot de set; ação fora do lugar onde vale (§4), inclusive `play_activity` ou `reset_profile` em `pause` ou `hud`; `effects` no título em variável que não é `profile` |
| U005 | erro | Controle ou valor que não combina com a configuração: `toggle` em configuração não booleana, `slider` em não numérica, opção de `select` ou `set_setting` com tipo errado, idioma fora de `project.json → locales` (configuração desconhecida já é barrada pelo schema) |
| U006 | erro | Tela obrigatória sem botão para sair: título sem `new_game`, pausa sem `close_screen`/`back` |
| U007 | aviso | Elemento com `size` que sai da tela na resolução base. Conferido pelo Studio; o validador de referência não calcula o tamanho de elementos sem `size` |
| U008 | aviso | Elemento clicável sem texto nem `tooltip` (sem nome para teclado e acessibilidade) |
| U009 | aviso | A tela `credits` não tem `licenses_list`, mas algum plugin habilitado ou fonte do tema traz licença, ou algum asset tem `credit`; ou a `licenses_list` deixa `assets` de fora de `include` e algum asset tem `credit` |
| U010 | aviso | Um `play_activity` pode ser alcançado a partir da pausa ou do HUD (por uma cadeia de `open_screen`); o botão vai ficar oculto durante a partida |
| U011 | aviso | Uma seção ativa da galeria está vazia: `endings` sem finais em `project.json → endings`, `images` ou `music` sem nenhum asset desse tipo com `gallery: true` |
| U012 | erro | `gallery_grid` com `source` que não está em `project.json → gallery.sections` (inclusive num projeto sem galeria) |
| U013 | aviso | Asset com `gallery: true` que não vai aparecer: a seção do tipo dele não está ativa, ou o tipo não entra na galeria (só `image`, `background` e `audio_music`) |
| U014 | aviso | Projeto sem galeria com tela `ui/gallery.json` ou com uma ação `open_screen` para `gallery`: a tela não entra no jogo e a ação não faz nada |
| W020 | aviso | Texto de um idioma usa caracteres que nem a fonte do estilo nem as reservas daquele idioma cobrem. Conferido pelo Studio, que lê os arquivos de fonte; o validador de referência não confere, porque não tem os arquivos |

Telas também passam pela regra R022 do Data Model (§11 de lá): `sys.ui.content_filter` e `sys.ui.content_filter_available` podem decidir o que aparece (um selo "modo stream", um texto alternativo), mas não uma ação `effects` ou `emit`. É erro lê-las no `if` dessas ações ou de uma ação que as envolve, nos valores de `effects` e `payload`, ou no `visible_if`/`enabled_if` do elemento que dispara a lista (`actions`, `on_hover`) ou de um `container` que o contém. Assim o modo stream continua sem mudar a história (Data Model §10.4).

## 12. Runtime

- O **UI Manager** mantém uma pilha de telas. `open_screen` empilha; `close_screen` desempilha. Abrir a pausa ou uma tela própria durante o jogo pausa o Narrative Engine (como o menu de pausa), exceto a `hud`, que fica sempre por cima da cena.
- Ações rodam na thread principal, em ordem; `effects` e `emit` passam pelo State Manager e pelo Event Bus, como qualquer efeito (RT §6–7).
- Telas e sets são compilados no bundle (`bundle.json → ui`, `bundle.json → sets`) e seus assets entram no build (BS §6.1).
- Durante uma atividade com `input.capture`, só os elementos da `hud` com `during_activity: true` (por exemplo, pausa) recebem input.
