# Revisão das especificações — 2026-11-17

- **Tipo:** busca de lacunas, inconsistências e ambiguidades, com sugestões.
- **Situação:** sugestões N-01 a N-20 e decisões D18 a D21 aceitas pelo Luis e aplicadas nas specs (README das specs, "Decisões de 2026-11-17"). N-12 vai num pull request no repositório da demo.
- **Material:**
  - `luisfernandosouza/gd-vn-studio`, `main` em `36fb618` (inclui os PRs #3 a #8): specs 00 a 09, schemas, presets, exemplos, vetores, ferramentas e `spikes/preview-web/`.
  - `luisfernandosouza/gd-vn-studio-demo`, `main` em `a686daa`.
- **Foco:** as três decisões recentes:
  1. O runtime Godot é o único interpretador do Preview (encerrada em 2026-11-16).
  2. A galeria é opcional e vem desligada.
  3. O modo stream muda só a apresentação.
- **Ferramentas:**
  - `validate.py` sobre o exemplo das specs: 0 erros e 0 avisos.
  - `test_validate.py`: 130/130.
  - `test_schemas.py`: 24/24.
  - `conformance.py`: 137/137.
  - `compile_bundle.py`: bundle gerado.
  - `validate.py` sobre o repositório da demo: 0 erros e **4 avisos** (N-12).
- **Relação com as revisões anteriores:** os achados da auditoria documental de 2026-11-14 que já foram resolvidos não são repetidos: A-01 a A-04, M-02 e A-06 (decidido). Os itens da auditoria que continuam abertos estão só listados na seção 4, sem repetir a análise. A-05 é a exceção: ele volta como N-01, porque o README passou a dizer que o Preview está encerrado.

## 1. Resumo

As três decisões estão bem escritas onde são o assunto principal (RT §5.5 e §11, DM §10.4 e §10.5, PP §1 e §3, UI §2.1). Os problemas aparecem nas bordas:

- **Preview.** A decisão foi encerrada sem resolver como imagens, sons, fontes e plugins chegam ao runtime do painel e da janela. O próprio spike diz que não testou assets (N-01).
- **Modo stream.** Há três furos na regra "só a apresentação muda":
  - o palco guarda o que um passo `censor: skip` mostrou, mesmo depois de o modo ser ligado (N-02);
  - uma tela de HUD pode mudar a história conforme o modo, e o validador aceita (N-03);
  - legendas e rótulos de hotspot não têm versão censurada (N-09).
- **Galeria.** As specs estão coerentes. O repositório da demo ficou para trás (N-12), e um jogo que ganhar galeria numa atualização começa com ela vazia para quem já jogou (N-11).

**Contagem:** 20 achados novos.

| Gravidade | Achados |
|---|---|
| ALTO | 3 |
| MÉDIO | 9 |
| BAIXO | 8 |

Há também 4 decisões para o Luis (seção 5).

## 2. Achados novos

### 2.1. ALTO

#### N-01. Preview sem caminho definido para assets e plugins, embora a decisão esteja "encerrada"

- **Onde:**
  - README, linhas 277, 301 e 319;
  - RT §2.1 e §11;
  - PP §1.1, §1.2 e §3 (`preview.load` e `preview.reload`, troca em `/assets/<id>`);
  - `spikes/preview-web/README.md`, "Limites do teste";
  - auditoria, A-05.
- **Problema:**
  - O README diz "não há mais pendência sobre o Preview". O spike, que embasou a decisão, diz o contrário: "**Sem assets.** O spike não carrega imagens, áudio nem vídeo. A proposta B (carregador `VNAssets`) precisa de um teste separado, inclusive de como os bytes chegam do Studio ao runtime Web". A "proposta B" não está documentada em nenhuma spec.
  - O RT §2.1 afirma que o Godot "só carrega imagens, sons e fontes que o editor importou" e que `bundle.json → assets` mapeia ids para `res://…`. No painel (export Web), os PNG, OGG e TTF do autor não estão no `.pck` do runtime e nunca foram importados. Na janela, o PP não diz qual projeto Godot ou pacote o binário embutido abre, nem como `res://vn_plugins/<ns>/` aponta para a pasta do plugin vinculado.
  - Uma troca de `/assets/<id>` no `preview.reload` mandaria um caminho `res://` que não existe no Preview.
- **Impacto:** o requisito central do Studio (ver o jogo de verdade enquanto edita) não tem caminho técnico para o que o autor mais faz: arrastar uma imagem ou um som. A escolha muda o Build Manager, o PP e o runtime: carregar bytes crus ou importar e empacotar.
- **Sugestão:**
  1. Reabrir o item no README como **D18** e tirar o "não há mais pendência".
  2. Escrever a proposta B no RT §11 ou num §2.2 novo, "Assets no Preview". Recomendação: no Preview (painel e janela), o runtime resolve `assets` por um carregador de bytes, com estes passos:
     - o Studio manda `{id → url vnpreview:// ou caminho absoluto}`;
     - o runtime cria `ImageTexture`, `AudioStreamOggVorbis`/`AudioStreamMP3`/`AudioStreamWAV` e `FontFile` em memória;
     - o carregador aplica, ele mesmo, as opções que o import do Godot aplicaria no build: `import` de `assets.json`, `nine_slice`, `loop` de música, filtro de textura e escala de SVG.
  3. Fixar a regra "o Preview mostra o mesmo que o jogo exportado" com uma lista do que pode diferir (compressão `lossy`, por exemplo).
  4. Fazer o teste B antes de começar o Studio: abrir no painel 200 imagens de 1920×1080 e 30 músicas, medir a memória e o tempo, e trocar um asset em uso.
  5. Para a janela, dizer qual pacote ou projeto o binário embutido abre e como os plugins vinculados ficam em `res://vn_plugins/<ns>/`.

#### N-02. Modo stream: o palco guarda o que um passo `censor: skip` mostrou

- **Onde:** RT §5.5 ("Mudança no meio do jogo", "Um passo `skip`/`only` que já passou não é refeito"); RT §8.2 e §8.3 passo 7; DM §10.4; `save.schema.json → state.scene.stage`; vetores `modo_stream_*` de `flow.json`.
- **Problema:** `censor` vale para `background`, `show` e `audio`, e esses passos deixam coisas no palco: um cenário, um sprite, uma música em loop. Se o modo estava desligado quando o passo rodou e o streamer liga o modo em seguida, o cenário ou sprite explícito continua na tela até outro passo trocá-lo. O RT §5.5 só redesenha "com a nova resolução de assets", e um asset sem `censored` resolve para ele mesmo. O mesmo vale ao carregar um save feito com o modo desligado: o palco é salvo com os ids originais e sem a marca de qual passo os pôs ali. O caso inverso, um passo `only` com o modo desligado depois, é menos grave, mas igual.
- **Impacto:** quebra a promessa central do modo, "liga a qualquer momento" (DM §10.4), justamente para quem transmite ao vivo.
- **Sugestão (D19):** o palco guarda, em cada item (cenário, personagem e canal de áudio), o `censor` do passo que o colocou ali. Isso exige um campo `censor` em `state.scene.stage`. Ao mudar o modo, ou ao carregar, o Stage esconde os itens cujo passo não valeria no modo atual, como se o passo não tivesse rodado:
  - um cenário volta ao anterior ou ao `placeholder`;
  - um sprite some;
  - uma música silencia com fade.
  - Um vetor `flow` novo cobre o caso "ligar o modo depois de um `show` com `skip`".
  - Alternativa mais simples, mas que limita o autor: proibir `censor` em `background`, `show` e `audio` (`play`) e exigir a marcação por asset.

#### N-03. Uma tela pode mudar a história conforme o modo stream, e o validador aceita

- **Onde:** DM §10.4 ("O estado do filtro… só pode ser lido por telas e sets"); R022; UI §3.2 e §4 (ações `effects` e `emit` valem no jogo); `tools/validate.py`, onde `check_ui` não confere R022.
- **Evidência:** cópia da demo com uma `ui/hud.json` em que um botão tem `{"do":"effects","if":[{"variable":"sys.ui.content_filter",…}],"effects":[{"op":"set","variable":"global.fishing_won","value":true}]}` e um `emit` de `story.met_master` com a mesma condição. `validate.py` dá 0 erros e 0 avisos.
- **Problema:** a regra de ouro só é garantida nas cenas, nos capítulos e nas derivadas. No HUD, na pausa e em telas próprias abertas durante o jogo, uma condição sobre `sys.ui.content_filter` pode decidir um `effects` ou um `emit`, ou decidir se o botão que os dispara aparece (`visible_if`, `enabled_if`). A história passa a depender do modo.
- **Sugestão:** estender R022 às telas. É erro ler `sys.ui.content_filter*` numa condição que controla uma lista de ações com `effects` ou `emit`: o `if` da própria ação, de uma ação que a envolve, ou o `visible_if`/`enabled_if` do elemento que a dispara. Para enfeites (um selo "modo stream" no HUD), a leitura continua livre. Acrescentar o caso em `test_validate.py` e uma linha no DM §10.4, "O que garante a regra de ouro".

### 2.2. MÉDIO

#### N-04. O Preview não liga o modo stream nem simula galeria desbloqueada

- **Onde:** Req §11.2 ("O botão do Preview que liga o modo… entra no Protocolo do Preview na próxima revisão dele"); Req §11.1 ("Ver como se tudo estivesse desbloqueado"); PP §3 (`preview.start`, `preview.show_screen`); `preview-protocol.schema.json → Preview_show_screen_params.simulate`, que só tem `has_save`, `in_game`, `platform` e `endings`.
- **Problema:** as duas promessas do Req não têm método no protocolo. O autor não consegue ver a cena censurada no Preview nem a galeria desbloqueada no Menu Editor. `simulate` também não cobre `sys.ui.content_filter`, `content_filter_available`, `last_activity_outcome` nem `last_record_rank`, que são as variáveis das telas novas.
- **Sugestão:**
  - `preview.set_setting({setting, value})`, que aplica qualquer `bind` do UI §8 como se o jogador tivesse mudado e emite `sys.content_filter_changed`;
  - `content_filter` em `preview.start`;
  - em `simulate`: `content_filter`, `content_filter_available`, `last_activity_outcome`, `last_record_rank` e `seen_assets` (ou `gallery_unlock_all: true`).

#### N-05. Onde ficam os saves, o perfil e as configurações do Preview

- **Onde:** RT §8.5 (`user://`, IndexedDB no Web); PP §1.1 (`vnpreview://`); PP §3 (`profile` "só nesta sessão"); RT §5.2 ("Preview"); spec 09 §3.4.
- **Problema:** o PP não diz onde fica o `user://` do Preview.
  - No painel, todos os projetos são servidos pela mesma origem `vnpreview://`, então dividem a mesma IndexedDB: "Continuar", os slots, `profile.json` (finais e galeria) e `settings.json` vazariam de um projeto para outro.
  - Na janela, o diretório de usuário vem do nome do projeto Godot do runtime, que é o mesmo para todos os projetos.
  - Também não está dito se o Preview grava algo quando `preview.start` vem sem `profile`.
- **Sugestão (D21):** o Preview usa um `user://` **em memória** por padrão. O perfil vem de `preview.start.profile`, ou começa vazio, e nada sobrevive ao fechar o painel. Uma opção "Manter saves do Preview" grava em `.vnstudio/preview/user/`, por projeto: no painel, por uma chave de projeto na IndexedDB; na janela, por um diretório de usuário próprio. Escrever no PP §1 e citar na spec 09 §3.4.

#### N-06. O runtime Web do painel depende de um "template" que o Studio só baixa na exportação

- **Onde:** PP §1.1 ("os arquivos `.wasm`, `.js` e `.pck` do template da versão fixada do Godot"); BS §2 (templates "baixados sob demanda"); Req §7.1 passo 5; README (tamanho do Studio de 150 a 250 MB).
- **Problema:**
  - Lido ao pé da letra, o Preview só funciona depois de o Studio baixar os templates de exportação, que hoje só são pedidos ao exportar. Na primeira abertura, ou sem internet, o painel não teria o motor.
  - O que o painel roda é o **runtime exportado para Web** (o `.pck` do runtime mais o `.wasm` do template), e não está dito quem gera esse export nem quando: no build do Studio, com a release, ou na máquina do autor. Também não está dito se ele entra na conta dos 150 a 250 MB.
  - O spike serviu a página por HTTP (`tools/serve.mjs`). O protocolo próprio `vnpreview://`, com o tipo `application/wasm` necessário para compilar o WASM em streaming, não foi testado nos três webviews.
- **Sugestão:** escrever no RT §11 ou na spec 09 que o export Web do runtime para o Preview é gerado na release do runtime e embutido no Studio. Ele é diferente dos templates de exportação do jogo e funciona sem internet. Acrescentar ao "A conferir no primeiro protótipo" do README: servir o export por `vnpreview://` no WebView2, na WKWebView e no WebKitGTK.

#### N-07. Plugins como `.pck` separado no painel: riscos além da recarga

- **Onde:** SDK §10.6; PP §3 (`preview.reload_plugins`); README, "A conferir"; o spike carregou o plugin de pesca com `preload` dentro do pacote principal (`spikes/preview-web/godot/main.gd:9`).
- **Problema:** o README lista só "recarregar trocando o `.pck`". Há dois riscos que valem o mesmo teste:
  1. **`class_name` de scripts dentro de um pacote carregado depois do boot.** O SDK obriga o prefixo (P011), o que mostra que plugins usam `class_name`. O registro de classes globais do Godot é montado na exportação. Se ele não enxergar as classes de um pacote carregado depois, o plugin não abre no painel, embora funcione no jogo exportado, onde entra no staging.
  2. **Quem gera o `.pck` de cada plugin.** É o Godot embutido em modo headless, com o import dos assets do plugin. Não está dito quanto tempo isso leva a cada salvamento de um plugin vinculado.
- **Sugestão:** pôr os dois pontos no "A conferir". Se o item 1 falhar, a regra passa a ser: no painel, os plugins entram num único `.pck` montado junto com o runtime, refeito na recarga (`preview.reload_plugins` reabre o motor), ou o modo desenvolvedor usa sempre a janela.

#### N-08. Nada confere que o compilador do Studio gera o mesmo bundle que a referência

- **Onde:** BS §5.1 ("O compilador do Studio DEVE gerar o mesmo `bundle.json`, byte a byte"); PP §3 (o Studio manda entidades "já compiladas" na recarga incremental); spec 08.
- **Problema:** com um interpretador só, o código de jogo que existe em duas linguagens passa a ser o **compilador** (TypeScript no Studio, Python na referência) e o validador. O validador tem `test_validate.py`. O compilador não tem nenhum caso além do exemplo das specs. A compilação por entidade (recarga incremental) também não é conferida contra a compilação completa: defaults do `scheduler` do projeto, galeria, preset e instanciação de variáveis de personagem dependem de mais de um arquivo.
- **Sugestão:** criar um grupo de vetores `compile`, com projetos pequenos e o `content_hash` esperado. Cobrir preset, galeria ligada e desligada, `--edition censored`, `renamed_from` e variáveis de personagem. Acrescentar uma regra de CI: para cada caso, compilar por entidade e aplicar os patches dá o mesmo bundle que compilar tudo.

#### N-09. Textos sem versão censurada: legendas, rótulos de `interact` e títulos

- **Onde:** DM §10.4 (nível "Texto"); DM §8.2 (`audio.caption`; `interact.hotspots[].label`, `exit`); Req §12 (legendas); `scene.schema.json`, onde só `line`, `choice`, opção e `interact.prompt` têm campo censurado.
- **Problema:**
  - Um `sfx` com `censored.hide` fica mudo, mas a legenda (`caption`) continua aparecendo com `subtitles` ligado. O texto descreve justamente o som escondido.
  - O `label` de um hotspot ou do `exit` não tem versão censurada.
  - Títulos e descrições de finais e o `display_name` de personagens também não. Nesse caso pode ser intencional, mas não está escrito.
- **Sugestão:**
  - `caption` segue o asset: com `hide`, não aparece; com `replace_with`, usa `censored_caption`, se houver.
  - Acrescentar `censored_label` em hotspots e no `exit`, com o caminho `…/<hotspot>/censored`.
  - Escrever no DM §10.4 que nomes, títulos de capítulo e de final não têm versão censurada e precisam ser neutros, ou estendê-los também.

#### N-10. Um plugin pode mudar o resultado conforme o modo stream

- **Onde:** SDK §5.2 (`ctx.content_filter`); SDK §5.6; SDK §13.4 (revisão).
- **Problema:** o plugin lê o modo e devolve `outcome` e `payload`, que decidem desvios e efeitos da cena. Nada proíbe devolver outro resultado com o modo ligado. A regra de ouro fica sem garantia nos minijogos.
- **Sugestão:**
  - Uma frase normativa no SDK §5.6: o modo NÃO DEVE mudar `outcome`, `payload`, escritas em variáveis nem eventos, só o que o jogador vê e ouve.
  - Um item no checklist de revisão do §13.4.
  - Uma opção `content_filter` no `VNTestHarness`, para o dev testar que o mesmo `VNScriptedInput` dá o mesmo resultado nos dois modos.

#### N-11. Uma galeria acrescentada numa atualização começa vazia para quem já jogou

- **Onde:** DM §10.5; RT §5.2 ("Só quando o projeto a tem, o runtime registra…"; "O compilador já tirou a marca dos assets cuja seção o projeto não ativou").
- **Problema:** `profile.seen_assets` só é gravado quando a galeria e a seção existem e o asset tem `gallery: true` naquela versão do jogo. O jogo 1.0 sem galeria, ou com uma CG que só ganhou `gallery: true` na 1.1, não guarda nada. Quem atualizar encontra a galeria vazia, mesmo tendo visto tudo. Os finais não têm o problema, porque são sempre gravados.
- **Sugestão (D20):** o runtime grava sempre em `seen_assets` os assets `image`, `background` e `audio_music` vistos em nós de cena, com ou sem galeria, e a galeria filtra na hora de mostrar. A lista é limitada pelo número de assets do jogo. Se a decisão for manter como está, escrever a consequência no DM §10.5 e no Req §11.1, para o autor saber que a galeria precisa existir desde o lançamento.

#### N-12. O repositório da demo não acompanha os PRs #6 e #8

- **Onde:** `gd-vn-studio-demo` em `a686daa`; `docs/specs/examples/demo-project/`; auditoria B-14.
- **Evidência:** `validate.py` sobre a demo dá estes avisos:
  - U013 três vezes (`bg/beach_day`, `bg/pier_sunset`, `music/waves` com `gallery: true` sem seção);
  - U014 uma vez (`ui/title.json#btn_gallery` abre uma galeria que não existe).
  
  `diff` contra o exemplo das specs mostra estes arquivos diferentes: `assets.json`, `project.json`, `scenes/ch01/scene_beach.json`, `ui/title.json`, `ui/settings.json` e a tradução `en` da cena da praia.
- **Problema:** o jogo jogável, que é onde "o jogo evolui", já não usa a galeria (o botão do título não faz nada) nem mostra o modo stream. A duplicidade que a auditoria apontou (B-14) virou divergência real.
- **Sugestão:** um PR na demo trazendo `project.json → gallery` e o exemplo de modo stream do exemplo das specs. Definir de vez qual cópia é a fonte; o mais simples é a demo, com a CI gerando `examples/demo-project/` a partir dela, como a spec 09 já faz com o plugin.

### 2.3. BAIXO

| # | Onde | Problema | Sugestão |
|---|---|---|---|
| N-13 | README, linhas 277 e 319 × 301 | "Não há mais pendência sobre o Preview" ao lado de "A conferir no primeiro protótipo" | Trocar por "decisão tomada; pendências técnicas: …" e listar N-01, N-06 e N-07 |
| N-14 | DM §11, último parágrafo | Cita "U001–U011, W020"; os códigos já vão até U014 | Trocar para U001–U014 |
| N-15 | UI §3.1 `gallery_grid` | "`images` e `music` listam os assets com `gallery: true` (cenários e músicas)": parece excluir `image`, que U013 e DM §10.5 aceitam | Escrever "(imagens e cenários; músicas)" |
| N-16 | Req §11.1 | "Sugere marcar os cenários usados em `then: "end_game"`": um `then` não usa cenário | "Os cenários mostrados nas cenas que terminam com um final" |
| N-17 | RT §3.0 passo 6 × RT §8.5 | A pergunta da primeira abertura depende de `settings.json` não ter `content_filter`, mas o arquivo só grava o que o jogador mudou. Uma resposta igual ao padrão pode não ser gravada, e a pergunta se repete | Dizer que a resposta é sempre gravada, mesmo igual ao padrão, ou usar um campo `content_filter_asked` |
| N-18 | DM §10.4 (nível "Texto") | Uma fala com `censored_text` e `voice` sem `censored` toca a voz original sob o texto censurado | Aviso novo no validador (W025) |
| N-19 | PP §4 × `flow.json` | Os vetores não têm `node` para passos pulados pelo `censor`; o PP diz que `node.entered` sai "antes de executar cada nó" | Escrever no PP que passos pulados pelo modo stream não geram `node.entered` (ou criar `node.skipped`, útil no Preview) |
| N-20 | BS §5.4 × DM §10.5 | Na edição censurada, um asset com `hide` e `gallery: true` vira um item da galeria que só mostra o placeholder, para sempre | O compilador da edição censurada tira `gallery` dos assets com `hide` |

## 3. O que foi conferido e está coerente

- **Um interpretador só:** RT intro, §11 e §12; PP §1 a §3; SDK §10.6 (sem mock e com `complete_activity`); spec 08 §4 (runner nativo e Web); spec 09 (`studio/preview/`, sem `studio/interpreter/`); ADD §3.3 (nota). Não sobrou menção ao interpretador TypeScript.
- **Galeria opcional:** `project.json → gallery` no schema; `sys.ui.has_gallery` e `sys.ui.gallery_*` no DM §4.3, na UI §3.2 e no validador; U011 a U014 implementados e testados; `presets/classic/ui/gallery.json` e `title.json` com `visible_if`; `profile.seen_assets` e `endings` no `save.schema.json`; regra de contagem do RT §5.2 compatível com W014 (o nó `background` aceita `image`).
- **Modo stream:** R022 a R024 e W024 implementados; `censor` só em passos de apresentação; vetores `flow` com o modo ligado e desligado; edição censurada no compilador; textos novos do preset nos 9 idiomas (86 chaves em cada arquivo, sem faltas).

## 4. Itens da auditoria de 2026-11-14 que continuam abertos

Conferidos no texto atual. Não são repetidos aqui; a análise está na auditoria.

| Item | Situação em 2026-11-17 |
|---|---|
| A-05 | Volta como N-01 |
| A-07, M-13 | Studio sem especificação funcional nem requisitos numerados |
| M-01 | RT §3.0 passo 2 ainda manda `g001` para hash diferente; BS §13.1 diz G002 |
| M-03 | `profile.plugins` e `state.plugins` continuam sem o id do plugin |
| M-04 | `bundle-plugins.schema.json` continua sem `integrity`; o RT §3.0 passo 5 ainda "confere `integrity`" |
| M-05, B-03 | RT §2 cita `project.json → ui.preset`, que o schema não tem; DM §10.3 e UI §1 ainda citam `modern` e `minimal` |
| M-06 | Quatro versões de `sys.ui.last_activity_outcome` (DM §4.3, UI §3.2, RT §5.3, SDK §6.1) |
| M-07 | Vida de `sys.save_modified` |
| M-08 | `CONSTRAINT_VIOLATION` em `on_result.effects`, hotspots e ações de tela |
| M-09 | Tecla A em `vn_left` e `vn_auto` |
| M-10 | `settings.resolution` e `settings.autosave` sem padrão |
| M-11, M-12 | ADD v0.1 e estado normativo |
| M-14 a M-20 | RNF, referências dos SDKs, catálogo de mensagens, catálogo de plugins, decisões de produto, `trust: local`, plano de testes e CI |
| M-21 | Diagrama do ciclo de vida sem pausa, volta ao título e modo livre |
| B-02, B-04, B-05, B-09, B-12, B-23, B-24 | Sem mudança |

## 5. Decisões para o Luis

| # | Decisão | Recomendação |
|---|---|---|
| D18 | Como imagens, sons e fontes chegam ao Preview (N-01) | O runtime carrega os bytes crus no Preview (painel e janela) e reproduz as opções de import, depois de um teste como o do spike. Sem essa decisão, o Studio não deveria começar |
| D19 | O palco no modo stream (N-02) | Guardar o `censor` de cada item do palco e reaplicar ao mudar o modo e ao carregar |
| D20 | O que a galeria registra (N-11) | Registrar sempre o que foi visto e filtrar ao mostrar |
| D21 | Saves e perfil do Preview (N-05) | Em memória por padrão, com a opção de manter por projeto |

## 6. Ordem sugerida

1. **Antes do runtime**, porque mudam o Stage e o save: N-02 (D19), N-03, N-09, N-17, N-18 e N-19. Junto, os itens antigos M-01, M-05, M-06 e M-09.
2. **Na demo:** N-12, em paralelo, num PR no repositório da demo.
3. **Antes do Studio:** N-01 (D18, com o teste B), N-04, N-05 (D21), N-06, N-07 e N-08.
4. **Editoriais**, em qualquer rodada: N-10, N-11 (D20), N-13 a N-16 e N-20.
