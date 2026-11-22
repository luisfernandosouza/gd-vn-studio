# Revisão das especificações — 2026-11-22 (2ª rodada)

- **Tipo:** busca de lacunas, inconsistências e ambiguidades, com uma solução concreta para cada achado.
- **Situação:** achados X-01 a X-13 aceitos pelo Luis em 2026-11-22, com as opções recomendadas de D24 (A), D25 (A) e D26 (A), e aplicados nas specs (README das specs, "Decisões de 2026-11-22: segunda revisão") e na demo.
- **Material:**
  - `luisfernandosouza/gd-vn-studio`, `main` em `fd3d488` (depois dos PRs #10 e #11);
  - `luisfernandosouza/gd-vn-studio-demo`, `main` em `d1544f7` (o commit de `SOURCE.json`).
- **Ferramentas, sobre a `main`:**
  - `validate.py` no exemplo com o plugin: 0 erros e 0 avisos; na demo e no projeto congelado `conformance/compile/base/`: também 0 e 0;
  - `test_validate.py`: 139/139; `test_schemas.py`: 39/39; `conformance.py`: 140/140; `test_compile.py`: 8/8 (os números do README e da spec 08 batem);
  - `sync_demo_example.py <demo> --check`: o exemplo confere com a demo;
  - workflow `specs.yml` no merge do PR #11 (run 45041575997): verde, e os passos que usam o secret `DEMO_REPO_TOKEN` rodaram (o secret está configurado).
- **O que não se repete aqui:** V-01 a V-14 e D22/D23 (revisão de 2026-11-22, PR #10), M-01, M-04, M-05 e M-06 (PR #11), e os itens abertos da auditoria de 2026-11-14, que só são citados quando um achado novo os toca (B-20, M-21).

## 1. Resumo

Os PRs #10 e #11 entraram limpos: ferramentas verdes, números certos, nenhum id antigo de cenário sobrando, e a demo e o exemplo iguais. Os problemas novos estão quase todos nas decisões que esses PRs tomaram:

1. **Caminhos relativos no bundle do Preview** (ajuste de D18) quebram uma regra DEVE do Build System: "mesmo conteúdo, mesmo `content_hash` no Preview e no jogo" (X-02). E o protocolo `vnpreview`, como descrito, dá acesso a qualquer arquivo do disco a código de plugin rodando no painel (X-04).
2. **`VNStorage`** (ajuste de D21) deixou quatro documentos dizendo que os saves mantidos do Preview ficam em `.vnstudio/preview/user/`, enquanto a PP §1.4 e a RT §8.5 põem os do painel na IndexedDB do webview, fora do projeto (X-03).
3. **Créditos no asset** resolveram a arte de terceiros, mas o jogo exportado continua sem o aviso de licença do Godot e das bibliotecas dele, que todo jogo é obrigado a mostrar (X-01). O formato de `licenses.txt` nunca foi definido, e o `licenses_list` precisa dele para filtrar por tipo (X-05).

**Contagem:** 13 achados novos.

| Gravidade | Achados |
|---|---|
| ALTO | 2 |
| MÉDIO | 6 |
| BAIXO | 5 |

Há também 3 decisões para o Luis (seção 5).

## 2. Achados novos

### 2.1. ALTO

#### X-01. O jogo exportado não leva o aviso de licença do Godot, das bibliotecas dele, do runtime e das fontes do preset

- **Onde:** BS §4.5 (`vn_content/licenses.txt`: "licenças de todos os plugins e das fontes do tema, e o `credit` de cada asset"); UI §3.1 (`licenses_list.include`: `plugins`, `fonts`, `assets`); spec 09 §1 (runtime MIT); `compile_bundle.py` (fontes Noto do preset em `res://vn_runtime/presets/fonts/`).
- **Problema:**
  - O Godot é MIT e pede que o aviso de copyright vá junto do jogo; a documentação do Godot ("Complying with licenses") manda pôr o texto na tela de créditos ou num arquivo junto do jogo. O motor também inclui bibliotecas com avisos próprios (FreeType, ENet, mbedTLS e outras), listadas em `Engine.get_copyright_info()`.
  - O runtime e os SDKs são MIT (decisão de 2026-11-14), e a licença MIT também pede o aviso em cópias do software. Todo jogo exportado contém o runtime.
  - As fontes Noto do preset são OFL, que pede o texto da licença junto de cada cópia.
  - Nenhum desses entra em `licenses.txt`. Hoje, **todo** jogo exportado pelo Studio sairia sem os avisos obrigatórios, e o autor não tem como saber.
- **Solução:**
  1. BS §4.5: `licenses.txt` (ou o arquivo do X-05) ganha um bloco **sempre presente**, montado pelo Build System a partir do runtime: a licença do runtime, o texto de `Engine.get_license_text()`, as entradas de `Engine.get_copyright_info()` e as licenças das fontes do preset que entram no jogo. O runtime pode gerar esse bloco ele mesmo na hora de mostrar, já que as APIs existem no motor.
  2. UI §3.1: `licenses_list.include` ganha `engine`. Ele entra sempre, mesmo quando o autor lista outros valores; o validador avisa (U009) se o autor tentar tirar.
  3. U009 passa a ser **erro** na exportação quando a tela `credits` não tem `licenses_list` (sem ela, o jogo não cumpre a licença do motor). Alternativa mais branda: o runtime acrescenta um botão "Licenças" automático no fim da tela de créditos quando ela não tem o elemento.
  4. Release do runtime: o pacote de licenças do Godot e das fontes do preset é gerado na mesma release e conferido pela CI de release (spec 09 §1.2).

#### X-02. O bundle do Preview com caminhos relativos tem outro `content_hash`, contra uma regra DEVE

- **Onde:** BS §5.1 ("Ele independe da codificação final, então o mesmo conteúdo tem o mesmo hash no Preview e no jogo"; "O compilador do Studio DEVE gerar o mesmo `bundle.json`, byte a byte"); PP §1.3 ("É a única diferença entre ele e o do build"); RT §2; `bundle.schema.json → assets.*.path`.
- **Problema:**
  - Desde o PR #10, o bundle do Preview grava `backgrounds/x.png` e o do build grava `res://vn_content/assets/backgrounds/x.png`. Como o `content_hash` é o SHA-256 do `bundle.json` inteiro, os dois hashes sempre diferem. A frase do BS §5.1 ficou falsa.
  - Os vetores de compilação e a "equivalência incremental" da CI do Studio só valem para o bundle do build; o do Preview, que é o que o autor vê o tempo todo, fica sem vetor.
  - O schema teve de afrouxar de novo (aceitar relativo em qualquer bundle) e a defesa passou para o runtime e o selfcheck (B018), que é o que o V-04 queria evitar.
- **Solução recomendada (D24-A):** o bundle do Preview volta a ser **idêntico** ao do build, com `res://vn_content/assets/<caminho>`. Em modo preview, o carregador `VNAssets` troca o prefixo `res://vn_content/assets/` por `assets_base` antes de ler os bytes.
  - O hash fica igual nos dois, a frase do BS §5.1 volta a ser verdade e os vetores de compilação passam a valer para o Preview.
  - `bundle.schema.json` volta a exigir `^res://`, e o B018 fica só para algo que não deveria acontecer (um `res://` que não existe no staging).
  - PP §1.3 e RT §2: trocar "caminho relativo" por "o runtime em modo preview resolve o prefixo `res://vn_content/assets/` pela `assets_base`".
- **Alternativa (D24-B):** manter os relativos e corrigir o texto: BS §5.1 diz que o hash do Preview é outro, os vetores ganham um caso "forma do Preview", e a PP §1.3 tira "É a única diferença".

### 2.2. MÉDIO

#### X-03. "Manter saves do Preview": quatro documentos dizem `.vnstudio/preview/user/`, mas no painel os saves vão para a IndexedDB do webview

- **Onde:** README (D21, linha da tabela de 2026-11-17); RT §11 ("por projeto, em `.vnstudio/preview/user/`"); spec 09 §3.4; PP §1.4 (primeira frase do item) × PP §1.4 (resto do item) e RT §8.5 (tabela do `VNStorage`: "no painel, `user://preview/<project.id>/`").
- **Problema:**
  - No painel, `user://` é o sistema de arquivos do Godot Web guardado na IndexedDB da origem `vnpreview`. Os saves ficam no perfil do webview do Studio, não na pasta do projeto: não aparecem em `.vnstudio/`, não somem quando o autor apaga o projeto, e não vão junto se ele copiar o projeto para outra máquina.
  - Duas cópias do mesmo projeto (mesmo `project.id`, por exemplo um clone para testar uma branch) dividem os mesmos saves.
  - Painel e janela do mesmo projeto não veem os mesmos saves: o autor que troca de modo "perde" o progresso.
  - Não foi conferido se o WebView2, a WKWebView e o WebKitGTK guardam IndexedDB de forma persistente numa origem de protocolo próprio. O WebKit trata alguns esquemas próprios como origem opaca.
  - A PP §1.2 não lista `--vn-user-dir` entre os argumentos com que o Studio abre a janela.
- **Solução recomendada (D25-A):** no painel, o `VNStorage` "pasta" grava pelo Studio.
  - O runtime manda as notificações `storage.write { path, data }` (base64) e `storage.delete { path }`. O Studio grava em `.vnstudio/preview/user/` e responde nada (continua valendo "o runtime nunca faz requisições ao Studio").
  - `preview.load` com `user_data: "project"` traz `user_files: { caminho → base64 }` com o conteúdo atual da pasta, que o runtime põe no `VNStorage` em memória ao abrir.
  - Painel e janela usam a mesma pasta, e as quatro menções a `.vnstudio/preview/user/` ficam certas.
  - PP §1.2 passa a listar `--vn-user-dir <pasta>`.
- **Alternativa (D25-B):** manter a IndexedDB e corrigir os quatro documentos, com a pasta prefixada pelo caminho do projeto (hash do caminho absoluto) em vez do `project.id`, e um item novo em "A conferir": IndexedDB persistente em `vnpreview` nos três webviews.

#### X-04. O protocolo `vnpreview` serve qualquer arquivo, e plugins no painel podem usar o `JavaScriptBridge`

- **Onde:** PP §1.1 e §1.3 (`convertFileSrc`, `vnpreview://localhost/assets/`); SDK §12.2 (W009).
- **Problema:**
  1. **O exemplo da URL não bate com `convertFileSrc`.** A função do Tauri devolve o caminho **absoluto** codificado (`vnpreview://localhost/C%3A%5CUsers%5C…`), e não `…/assets/`. Para funcionar assim, o handler do protocolo precisa servir qualquer caminho do disco que lhe pedirem.
  2. **Plugins rodam na mesma página.** O GDScript de um plugin pode chamar `JavaScriptBridge.eval` e, de lá, `fetch` qualquer arquivo do usuário pelo `vnpreview`, ou chamar `vnPreview.onmessage` e se passar pelo runtime. W009 não lista `JavaScriptBridge` nem `JavaScriptObject`. No jogo exportado para Web, o mesmo plugin roda JavaScript livre na página do jogo.
  3. **Codificação no painel.** A PP diz que, na janela, acentos e espaços não precisam de codificação; no painel não diz nada. `assets_base` + `backgrounds/Praia à noite.png` precisa de codificação por segmento numa URL.
- **Solução:**
  - O handler do `vnpreview` serve só o projeto aberto, por um mapa fixo: `/project/assets/…`, `/project/preview/…` (bundle e `.pck` dos plugins) e `/runtime/…` (export Web). Qualquer outro caminho dá 404. O Studio troca o mapa ao trocar de projeto. A URL base sai de `convertFileSrc("project/assets", "vnpreview")` ou da regra do Tauri por sistema, mas nunca leva um caminho absoluto.
  - PP §1.3: no painel, o runtime codifica cada segmento do caminho (RFC 3986) antes de juntar com `assets_base`.
  - W009 ganha `JavaScriptBridge` e `JavaScriptObject`. A revisão do catálogo (SDK §13.4) recusa plugin que os use.
  - O Studio trata o que chega pelo `vnPreview.onmessage` como vindo de código não confiável: nada que chegue por ali grava fora de `.vnstudio/preview/` (vale também para o `storage.write` do X-03, que confere o caminho).

#### X-05. `licenses.txt` não tem formato, não existe no Preview, e o texto do crédito não se traduz

- **Onde:** BS §4.5; BS §7.1 (`exclude_filter`: `*.md, *.txt, tests/*, docs/*` "(exceto `vn_content/licenses.txt`)"); UI §3.1 (`licenses_list.include`); Req §11.3 ("o Menu Editor mostra a `licenses_list` com os créditos dos assets usados"); DM §10.1 (`credit`); auditoria de 14/11, B-20 (licença das fontes), ainda aberto.
- **Problema:**
  1. **Formato.** `licenses_list` filtra por tipo (`plugins`, `fonts`, `assets`), mas `licenses.txt` é "um texto". Nada diz como o runtime separa as partes, nem como mostra as entradas agrupadas (um pacote com 20 cenários vira uma linha).
  2. **Exportação.** O Godot não tem exceção no `exclude_filter`, e o filtro de exclusão vale depois do de inclusão. Com `*.txt` excluído, `licenses.txt` não entra no PCK. Arquivos que não são recurso (como `.txt`) também só entram por `include_filter`.
  3. **Preview.** O `licenses.txt` sai do staging do build. O bundle do Preview não tem nada parecido, então o Menu Editor e o Preview não têm de onde tirar a lista que o Req §11.3 promete.
  4. **Fontes (B-20).** "As licenças das fontes do tema" continuam sem fonte de dados. Com o `credit`, dá para resolver, mas falta onde ficar o texto da OFL, que precisa ir inteiro.
  5. **Idioma.** `credit.license` e `credit.notice` são texto livre e não têm tradução. Na demo, a licença dos cenários está em português ("Termos do Noraneko Background Pack 1 (ReadMe.txt do pacote)") e aparece assim para um jogador em inglês ou japonês.
- **Solução:**
  - Trocar `licenses.txt` por `vn_content/licenses.json`, com schema (`licenses.schema.json`): uma lista de entradas `{ kind: engine|plugin|font|asset, title, author?, license?, url?, notice?, text?, assets?: [ids] }`. O compilador agrupa os `credit` iguais numa entrada com a lista de assets. Ele entra no bundle como arquivo à parte, fora do `content_hash` do `bundle.json`, mas com hash em `build_config.CONTENT_HASHES` como os outros.
  - BS §7.1: `include_filter` com `vn_content/licenses.json`, e tirar o "exceto" do `exclude_filter`.
  - O Studio grava o mesmo arquivo para o Preview em `.vnstudio/preview/narrative/`, e `preview.reload` aceita `/licenses` como troca.
  - DM §10.1: `credit` ganha `license_file` (caminho relativo a `assets/`, por exemplo `fonts/OFL-Nunito.txt`). O texto vai inteiro para a entrada. As fontes passam a usar `credit` como qualquer asset, e `include: fonts` vira "assets do tipo `font`". Isso fecha o B-20.
  - DM §10.1: `license` e `notice` ficam no idioma original da licença e não são traduzidos; o Studio sugere escrever em inglês. Na demo, trocar o `license` dos cenários para "Noraneko Background Pack 1 terms (see ReadMe.txt)".

#### X-06. A "base" de personagem e de canal está descrita de um jeito e implementada de outro

- **Onde:** RT §5.5 ("a expressão e a posição do último `show` sem `censor`"; "o som que tocava no canal antes (último `audio` `play` sem `censor`)"); `save.schema.json → Stage.characters[].base`, `audio.*.base`; `tools/conformance.py` (`put_on_stage`, `base_of`); `flow.json`.
- **Problema:**
  1. **`hide` e `stop` no meio.** Na sequência `show alice neutral` → `hide alice` → `show alice lingerie` com `censor: skip`, a regra escrita ("último `show` sem `censor`") daria a base `neutral`, e a Alice reapareceria no modo stream, num momento em que não estava na cena. A referência faz o certo (o `hide` apaga o item e a base vai junto), mas o texto e o schema dizem outra coisa. O mesmo vale para `play` → `stop` → `play` censurado no canal.
  2. **Posição.** O texto e o schema guardam `position` na base; a referência só guarda `expression`, e o traço `stage` dos vetores não tem posição. Um runtime que esqueça a posição passa nos vetores.
  3. **Set no palco.** O `Stage` tem `background` (asset) e `set` separados, mas `background_censor` "cobre os dois", e o traço dos vetores põe o id do set em `background`. Não está escrito qual campo fica preenchido quando o cenário atual é um set.
  4. **Nenhum vetor** tem `hide` ou `stop` entre o passo sem `censor` e o censurado.
- **Solução:**
  - RT §5.5 e os `description` do schema: "a base é o estado do item **imediatamente antes** do passo censurado. Um `hide` da personagem ou um `stop` do canal sem `censor` tiram o item do palco, e com ele a base."
  - `conformance.py`: guardar `position` na base, e o traço `stage` passa a trazer `position` das personagens.
  - `save.schema.json → Stage`: quando o cenário atual é um set, `background` é `null` e `set`/`set_states` ficam preenchidos; `background_censor` vale para o que estiver preenchido. O traço dos vetores usa `{ "set": id }` para não misturar ids de asset e de set.
  - Dois vetores novos em `flow.json`: `modo_stream_base_apos_hide` e `modo_stream_base_apos_stop`.

#### X-07. A regra de mídia no repositório do produto não está na CI e contradiz os plugins oficiais e o instalador

- **Onde:** spec 09 §1.1 ("A CI recusa arquivos de imagem, áudio ou vídeo fora dessas pastas"), §1.1 "Plugins oficiais", §1.2 (tabela e "Nunca entra… `docs/`"); `.github/workflows/specs.yml`.
- **Problema:**
  1. **Não existe a verificação.** `specs.yml` só roda com mudanças em `docs/specs/**` e não procura arquivos de mídia. Uma imagem em `runtime/` ou `studio/` passa sem aviso.
  2. **"Dessas pastas" é só `runtime/tests/fixtures/`.** Mas a linha seguinte diz que os plugins oficiais em `plugins/` têm assets originais. Uma CI que siga o texto recusaria os sprites do minijogo de pesca oficial.
  3. **`docs/` "nunca entra"**, mas a tabela do §1.2 põe "os schemas e os presets" no instalador do Studio, e eles moram em `docs/specs/schemas/` e `docs/specs/presets/`.
  4. **"Os `.md` de desenvolvimento"** não diz quais. O `.vnplugin` oficial leva `README.md` e `CHANGELOG.md` (SDK §2.1).
- **Solução:**
  - Spec 09 §1.1: lista fechada de pastas onde mídia pode existir: `runtime/tests/fixtures/`, `plugins/*/vn_plugins/*/runtime/` e `plugins/*/sandbox/`, e fontes em `runtime/vn_runtime/presets/fonts/` (se forem versionadas).
  - Uma workflow `repo-hygiene.yml`, sem filtro de caminho, que lista os arquivos versionados com extensão de imagem, áudio, vídeo e `.psd` e falha fora dessa lista.
  - Spec 09 §1.2: trocar "`docs/`" por "`docs/`, salvo os schemas e presets, que o build do Studio e do runtime **copia** de `docs/specs/schemas/` e `docs/specs/presets/`"; e "`.md` de desenvolvimento" por "`.md` fora do que o Plugin SDK §2.1 manda pôr no `.vnplugin`".

#### X-08. `sync_demo_example.py` e a CI usam regras diferentes para escolher os arquivos

- **Onde:** `tools/sync_demo_example.py` (`SKIP_DIRS`, comparação com `json.loads`); `specs.yml` (sparse-checkout); spec 09 §1.1 ("Tudo o mais é igual, byte a byte"; "A pasta da demo tem de estar no commit de `SOURCE.json`").
- **Problema:**
  1. **Lista negra × lista branca.** O script copia todo `*.json` fora de `assets/`, `tools/`, `source/`, `.git/` e `.github/`. A CI baixa só `/*.json`, `chapters/`, `characters/`, `locales/`, `scenes/`, `sets/` e `ui/`. Quando a demo ganhar `migrations/save/*.json` (RT §8.4) ou um plugin embutido em `plugins/<nome>/` (com `plugin.json`), o script local copia esses arquivos, a CI não os baixa e acusa divergência. Rodado numa cópia de trabalho, o script copia também `.vnstudio/preview/narrative/bundle.json` e afins.
  2. **"Byte a byte"** não é o que o `--check` confere: ele compara o JSON lido (`json.loads`), então diferenças de formatação passam.
  3. **Versão.** O script não confere se a pasta da demo está no commit de `SOURCE.json`; rodado sobre a `main` da demo, grava a versão errada sem avisar.
  4. **A `main` da demo fica sem conferência.** A CI só valida a demo no commit fixo, e só quando um PR mexe em `docs/specs/**`. Uma mudança nas specs que quebre a `main` da demo (ou o contrário) só aparece na próxima sincronização.
- **Solução:**
  - O script usa a mesma lista branca da CI, numa constante, e a workflow a lê do script (ou o script gera o `sparse-checkout`).
  - `--check` compara os bytes; o filtro de `credit` reescreve `assets.json` com a mesma formatação da demo (indentação de 2, `ensure_ascii=False`, `\n` final), e a demo passa a ser gravada sempre assim.
  - O script roda `git -C <demo> rev-parse HEAD` e para se não for o commit de `SOURCE.json` (com `--update-source` para gravar o commit novo de propósito).
  - Na demo, uma workflow agendada (diária) e em todo PR que baixa a `main` do produto e roda `validate.py` sobre a demo. O token fica no repositório da demo, com leitura do produto.

### 2.3. BAIXO

| # | Onde | Problema | Solução |
|---|---|---|---|
| X-09 | PP §2 e §3 (`preview.input`), §4 (`activity.*`); SDK §6.1 | `cancel_activity` não tem efeito definido em lugar nenhum. O modo livre roda sem partida (estado `LOADED`), mas `preview.input` só vale em `RUNNING`/`PAUSED`, e `activity.started` exige `scene` e `node`. O Preview não consegue testar nem automatizar o modo livre | Definir: na história, `cancel_activity` = pular (`accepted: false` se a atividade não é `skippable`); no modo livre, = sair com `cancelled`. Aceitar `preview.input` em `LOADED` enquanto uma atividade do modo livre roda; `activity.*` ganha `mode`, e `scene`/`node` ficam opcionais |
| X-10 | SDK §6.1 ("Sair antes do fim"); RT §10.1; auditoria M-21 | (a) Na história, o jogador não tem como abrir a pausa durante um minijogo com `input.capture`; no modo livre, tem. O mesmo plugin recebe Esc num modo e não no outro. (b) Pausar a árvore não pausa nós com `PROCESS_MODE_ALWAYS`. (c) No Web em tela cheia, o navegador usa Esc para sair da tela cheia e o jogo não recebe a tecla | (a) Decidir junto com M-21 (D26 abaixo). (b) W009 avisa `PROCESS_MODE_ALWAYS` em cenas e scripts de plugin. (c) SDK §6.1: no Web, Start/Options e um botão de pausa na tela, se o tema tiver `hud`, são o caminho garantido |
| X-11 | SDK §12.2 (W009); RT §8.5 ("Nada no runtime, nem os plugins, abre arquivos de `user://` direto") | A frase do W009 ficou com uma subordinada no meio da lista e é difícil de ler. A lista só cita `FileAccess`/`DirAccess`, mas `ConfigFile.save`, `ResourceSaver.save`, `Image.save_png` e `OS.get_user_data_dir()` também gravam em `user://`. E W009 é aviso, enquanto a RT usa uma proibição | Reescrever W009 como lista simples e acrescentar essas APIs. Dizer na RT §8.5 que a garantia é do catálogo (a revisão recusa) e do aviso W009, e que um plugin `local` que grava direto fura o isolamento do Preview por conta do autor |
| X-12 | RT §2 ("Fora do modo preview, o runtime DEVE recusar…"); BS §13, §13.1 | Diz que o runtime recusa um caminho que não é `res://`, mas não qual mensagem o jogador vê (o B018 é do selfcheck, no Studio) | "Erro fatal com `runtime/message/g001`", como bundle inválido. Some se D24-A for aceita |
| X-13 | DM §10.4 e R023; `validate.py` (U009) | R023 descreve os passos aceitos como "que põem algo na tela ou no som", mas lista `wait`, que não põe nada. O U009 do validador conta todo asset com `credit`, mesmo o que não entra no jogo (o texto fala de "assets que entram no jogo") | R023: "`line`, `background`, `show`, `audio` com `play` e `wait`; `hide` e `audio` com `stop` não aceitam". U009: contar só assets alcançados pelo conteúdo (o validador já calcula o uso para B008/`always_include`) ou dizer na UI §11 que o validador de referência conta todos |

## 3. O que foi conferido e está coerente

- **PR #11:** G001 e G002 estão iguais no RT §3.0, BS §8.2 e BS §13.1; o RT não cita mais `integrity` de plugins (§2.1, §3.0, §9); `theme.json → preset` só aceita `classic`, e não sobrou menção a `ui.preset`, `modern` ou `minimal` como presets existentes; `last_activity_outcome` tem a mesma lista no DM §4.3, UI §3.2, RT §5.3 e SDK §6.1; o schema do manifesto recusa `cancelled` e `failed` em `outcomes`; `runtime/confirm/quit_activity` existe nos 9 idiomas do preset.
- **PR #10:** R023 no validador cobre `audio` com `stop`; a guarda de `container` do R022 desce para os filhos; `credit` sai do bundle e do hash (caso `credito_fora_do_bundle`); o projeto congelado `conformance/compile/base/` valida sem erros; nenhum id antigo (`bg/beach_day`, `bg/pier_sunset`) sobrou fora do exemplo de formato do DM §3.
- **Demo:** `CREDITS.md`, o `credit` dos cenários (Noraneko Games) e da Alice (sutemo, "Assets by sutemo") e a tela de créditos com `licenses_list` combinam. A Alice ainda não tem o texto exato da licença registrado (`CREDITS.md` diz isso); fica como lembrete antes de tornar a demo pública.
- **CI:** o secret `DEMO_REPO_TOKEN` está configurado, e os passos "Exemplo igual à demo" e "Demo valida com as specs desta versão" rodaram no merge do PR #11.

## 4. Itens antigos que este relatório toca

| Item | Situação |
|---|---|
| B-20 (licença das fontes) | Continua aberto; a solução do X-05 (`credit.license_file`) o fecha |
| M-21 (ciclo de vida do modo livre e da história) | Continua aberto; o X-10 e a D26 tratam da parte de sair do minijogo |
| Demais itens da auditoria de 14/11 ainda abertos | Não reconferidos; nada nos PRs #10 e #11 mexe neles |

## 5. Decisões para o Luis

| # | Decisão | Opções | Recomendação |
|---|---|---|---|
| D24 | Caminhos de asset no bundle do Preview (X-02) | **A.** Voltar a `res://vn_content/assets/…` nos dois bundles; o runtime em modo preview troca o prefixo pela `assets_base`. **B.** Manter os caminhos relativos e corrigir o BS §5.1 e a PP §1.3 | **A.** O Preview fica igual ao build byte a byte, com o mesmo hash, e o schema volta a ser estrito |
| D25 | Onde ficam os saves mantidos do Preview no painel (X-03) | **A.** O runtime manda `storage.write`/`storage.delete` e o Studio grava em `.vnstudio/preview/user/`, igual à janela. **B.** Ficam na IndexedDB do webview, e as specs passam a dizer isso | **A.** Os saves ficam com o projeto, painel e janela veem os mesmos, e não depende de IndexedDB num esquema próprio |
| D26 | O jogador pode sair de um minijogo da história pela pausa? (X-10, M-21) | **A.** Sim: `vn_menu` é sempre do runtime, nos dois modos; na história abre a pausa (salvar, carregar, configurações, "Pular minijogo" se `skippable`). **B.** Não: só no modo livre, como hoje | **A.** O plugin se comporta igual nos dois modos, e o jogador nunca fica preso num minijogo sem poder sair do jogo |

## 6. Ordem sugerida

1. **Antes do Studio:** D24 (X-02) e X-04, porque mudam o formato do bundle do Preview e o handler do `vnpreview`; D25 (X-03).
2. **Antes do runtime:** X-06 (texto, schema, referência e 2 vetores) e X-11.
3. **Antes da primeira exportação de verdade:** X-01 e X-05 (avisos de licença e `licenses.json`), que fecham também o B-20.
4. **Infraestrutura:** X-07 e X-08 num PR só de CI e ferramentas.
5. **Junto com M-21:** D26 e X-09, X-10.
6. **Editorial:** X-12 e X-13.
