# Revisão das especificações — 2026-11-22

- **Tipo:** busca de lacunas, inconsistências e ambiguidades, com uma solução concreta para cada achado.
- **Situação:** achados V-01 a V-14 e decisões D22 (opção A) e D23 (opção A) aceitos pelo Luis em 2026-11-22 e aplicados nas specs (README das specs, "Decisões de 2026-11-22") e na demo. A imagem do final "Noite de festival" continua sem asset próprio. A Alice é de sutemo.
- **Material:**
  - `luisfernandosouza/gd-vn-studio`:
    - `main` em `36fb618`;
    - PR #9 (`claude/project-thread-3j5qn0`, `1bb3479`), ainda aberto, que aplica a revisão de 2026-11-17. É a versão que está em `/mnt/project-files/specs/`, e foi ela a revisada;
    - `claude/cenarios-noraneko` (`5835435`).
  - `luisfernandosouza/gd-vn-studio-demo`:
    - `main` em `4b01087`;
    - PR #5 (`claude/project-thread-3j5qn0`, `b45e1ad`), aberto;
    - `claude/cenarios-noraneko` (`25cca98`).
- **Ferramentas, sobre o PR #9:**
  - `test_validate.py`: 133/133.
  - `test_schemas.py`: 30/30.
  - `conformance.py`: 138/138.
  - `test_compile.py`: 7/7.
  - `validate.py` sobre o exemplo com o plugin: 0 erros e 0 avisos.
  - Referências cruzadas entre specs (`DM §x`, `RT §x`, `spec 0x §x`…): 636 conferidas, nenhuma quebrada.
- **Teste de mescla:**
  - PR #9 mais a branch Noraneko, no produto: mescla sem conflito, mas `test_compile.py` cai para **0/7** (V-01).
  - PR #5 mais a branch Noraneko, na demo: 3 conflitos e um erro silencioso em `assets.json` (V-01).
- **O que não se repete aqui:**
  - os achados N-01 a N-20 da revisão de 2026-11-17, já aplicados no PR #9;
  - os itens da auditoria de 2026-11-14 que continuam abertos, que estão só listados na seção 4.

## 1. Resumo

O texto das specs está coerente: nenhuma referência cruzada está quebrada, e todas as ferramentas passam. Os problemas novos estão em três lugares:

1. **Branches abertas que não combinam.** O PR #9 e o PR #5 ainda não entraram, e as branches do Noraneko foram feitas sobre a `main` antiga.
   - No produto, a mescla não dá conflito, mas quebra os 7 vetores de compilação.
   - Na demo, a mescla dá conflito em 3 arquivos. Pior: o Git põe sozinho a versão censurada no cenário errado, sem avisar (V-01).
2. **Demo, créditos e assets de teste.** A regra nova do Luis tem duas partes: créditos só na demo, e assets de teste internos, fora do produto. Ela esbarra em três pontos das specs:
   - a spec 09 manda o exemplo das specs ser uma cópia exata da demo (V-02);
   - não existe um lugar nos dados para o crédito de um asset de terceiros (V-07);
   - nada diz o que fica fora do instalador do Studio e do runtime do Preview (V-08).
3. **Decisões de 17/11 com bordas abertas.**
   - D19 (o palco lembra o `censor`) não cobre `hide`, troca de expressão nem cenário composto (V-03).
   - D18 grava no bundle um endereço que no Windows não é o que o Tauri usa (V-04).
   - D21 pressupõe um `user://` em memória, que o Godot não tem (V-05).

**Contagem:** 14 achados novos.

| Gravidade | Achados |
|---|---|
| ALTO | 3 |
| MÉDIO | 7 |
| BAIXO | 4 |

Há também 2 decisões para o Luis (seção 5).

## 2. Achados novos

### 2.1. ALTO

#### V-01. As branches abertas quebram umas às outras na mescla

- **Onde:**
  - produto: PR #9 e `claude/cenarios-noraneko`;
  - demo: PR #5 e `claude/cenarios-noraneko`.
- **Evidência (mescla feita localmente, sem enviar nada):**
  - **Produto.** A mescla não tem conflito, mas `test_compile.py` dá **0/7**. Os vetores de `conformance/compile/cases.json` esperam o `content_hash` do exemplo antigo e procuram `/assets/bg~1beach_day/gallery` e `/assets/bg~1pier_sunset`, que a branch Noraneko apagou. `test_schemas.py` também cita `bg/beach_day`, mas passa, porque só confere o formato.
  - **Demo.** A mescla tem conflito em `CREDITS.md`, `assets/README.md` e `tools/generate_assets.py`. O `assets.json` mescla sem conflito, e é aí que está o erro: o bloco `"censored": {"replace_with": "bg/pier_sunset_safe"}` do PR #5 vai parar em **`bg/onsen_night`**. Com o modo stream ligado, o festival e a imagem do final passariam a mostrar o píer desfocado.
  - O `pier_sunset_safe.png` é gerado desfocando o `pier_sunset.png`, que a branch Noraneko tirou do gerador.
  - O `README.md` do PR #5 cita `bg/beach_day` e `bg/pier_sunset` como itens da galeria.
- **Impacto:** quem fizer o merge nessa ordem fica com a CI do produto vermelha e com uma demo que valida sem erros, mas censura o cenário errado.
- **Solução:**
  1. Fazer primeiro o merge do PR #9 e do PR #5.
  2. Refazer as duas branches Noraneko sobre a `main` nova, em vez de mesclar.
  3. Na demo, escolher qual cenário Noraneko tem versão censurada. A recomendação é o mesmo do exemplo das specs, `bg/train_evening`. A substituta `bg/train_evening_safe` seria gerada por `generate_assets.py`, desfocando `Train_Evening.png`. A licença do pacote permite modificar (ver V-13).
  4. Regerar os hashes com `python3 tools/test_compile.py --print` no mesmo PR, e trocar `bg~1beach_day` e `bg~1pier_sunset` nos casos pelos ids novos.
  5. Atualizar `test_schemas.py`, a spec 09 §1.1 (V-12) e o README da demo.

#### V-02. A regra "uma fonte para a demo" não tem guarda e já não combina com "créditos só na demo"

- **Onde:** spec 09 §1.1 ("a CI do produto confere que as duas não divergem"); `.github/workflows/`; as branches Noraneko.
- **Evidência:**
  - A única workflow do produto é `preview-web-spike.yml`. Nenhuma CI compara a demo com o exemplo, nem roda as ferramentas das specs.
  - As duas branches Noraneko já divergem entre si:
    - o exemplo das specs tem `bg/train_evening` com `censored` e o asset `bg/train_evening_safe` (`Train_Transparent.png`); a demo não tem nenhum dos dois;
    - a demo tem o rótulo `bg_credit` ("Cenários: Noraneko Games") em `ui/credits.json`, e o exemplo não tem, como o Luis pediu.
  - Nenhum arquivo registra qual commit da demo é a "versão fixa" copiada.
- **Problema:** a regra diz "cópia só com os JSON" e "não divergem". O pedido do Luis (créditos só na demo) cria uma diferença de propósito, que a regra proíbe. Sem uma verificação automática, a divergência volta a cada mudança, como já aconteceu no achado N-12 de 17/11.
- **Solução:**
  1. Criar `docs/specs/examples/demo-project/SOURCE.json`, com o commit da demo de onde a cópia veio.
  2. Criar `docs/specs/tools/sync_demo_example.py`, que copia os JSON da demo naquele commit e aplica um filtro escrito na spec 09 §1.1. O filtro:
     - tira o campo `credit` dos assets (V-07);
     - mantém o `ui/credits.json` próprio do exemplo;
     - não copia `CREDITS.md` nem arquivos `.txt`.
  3. Criar uma workflow `specs.yml` que, em todo PR:
     - roda as quatro ferramentas (`test_validate`, `test_schemas`, `conformance`, `test_compile`);
     - roda o `sync_demo_example.py` e falha se o resultado for diferente do que está no repositório.
  4. Escrever na spec 09 §1.1: "Diferenças permitidas: créditos e licenças de assets de terceiros. Todo o resto é igual."

#### V-03. A decisão D19 (o palco lembra o `censor`) só cobre os passos que põem algo no palco

- **Onde:** RT §5.5 ("Palco"); DM §10.4; `save.schema.json → Stage`; vetor `modo_stream_ligado_no_meio`.
- **Problema:** a regra é "esconder o item cujo passo não valeria no modo atual". Ela só funciona quando um passo **põe** um item no palco. Três casos ficam de fora:
  1. **Passos que tiram itens.** `hide` aceita `censor` (R023). Um exemplo:
     - a cena roda `show alice` e depois `hide alice` com `censor: only`, com o modo desligado. O `hide` é pulado e a Alice fica na tela;
     - o streamer liga o modo. Como o `hide` nunca rodou, nada no palco guarda a marca dele, e a Alice continua visível;
     - o mesmo vale para `audio` com `action: stop`.
  2. **Troca de expressão.** O personagem guarda um `censor` só. Um `show alice` com `expression: lingerie` e `censor: skip`, feito sobre uma Alice que já estava na tela, marca a personagem inteira. Ao ligar o modo, **a Alice some da cena**, em vez de voltar à expressão anterior. O cenário tem `background_base` para voltar ao anterior; personagem e áudio não têm nada parecido.
  3. **Cenário composto.** O nó `background` aceita `set` (DM §8.2), mas:
     - `background_base` só aceita um id de asset;
     - `set` e `set_states` não têm marca.
     
     Um set mostrado antes de um cenário censurado não tem como voltar.
- **Solução** (mantém a ideia de D19):
  - **Base por item.** Cada personagem e cada canal de áudio ganha um `base` com o último estado posto por um passo sem `censor`:
    - no personagem: `expression` e `position`;
    - no canal: `asset`, `loop` e `volume`.
    
    Ao esconder, o item volta ao `base`. Se não houver `base`, aí sim some.
  - **Passos que tiram.** Duas saídas:
    - a mais simples: tirar `hide` da lista de R023 e proibir `censor` em `audio` com `stop`. O autor censura a entrada do item, não a saída;
    - a completa: guardar a remoção como marca (`removed_by_censor`) e reverter do mesmo jeito.
    
    A recomendação é a mais simples.
  - **Set.** `background_base` passa a aceitar `{ asset }` ou `{ set, set_states }`, e o palco ganha `set_censor`.
  - **Vetores.** Três casos novos em `flow.json`: troca de expressão censurada, `hide` com `censor` (ou o erro R023, se ele sair da lista) e set como base.

### 2.2. MÉDIO

#### V-04. O bundle do Preview grava `vnpreview://localhost/…` e libera `file://` para qualquer bundle

- **Onde:** PP §1.3 ("Caminhos"); RT §2; `bundle.schema.json → assets.*.path` (padrão `^(res|vnpreview|file)://`); BS §12 (`--vn-selfcheck`).
- **Problema:**
  1. **O endereço muda conforme o sistema.** No Tauri 2, um protocolo próprio não tem a mesma URL em todo lugar: no Windows (WebView2), ele é servido como `http://vnpreview.localhost/…`, e não como `vnpreview://localhost/…`. Um caminho absoluto gravado no bundle prende o bundle a um sistema, e o Windows é o sistema do Luis. O README já põe "servir por `vnpreview://`" em "A conferir". Mas o formato do bundle depende da resposta.
  2. **`file://` na janela.** O Godot não abre URLs `file://`: ele usa caminhos do sistema. O runtime teria de converter a URL, e a spec não diz como tratar acentos e espaços (codificação `%xx`).
  3. **O schema afrouxou para todos.** O padrão novo vale para qualquer bundle. Um jogo exportado aceitaria um bundle com `file://` apontando para fora do pacote, e o `--vn-selfcheck` só confere os caminhos `res://`.
- **Solução:**
  - No bundle do Preview, `path` vira **relativo** à pasta de assets do projeto (`backgrounds/x.png`). `preview.load` ganha `assets_base`: no painel, a URL que o Tauri dá para o protocolo naquele sistema (`convertFileSrc`); na janela, a pasta absoluta do projeto. O runtime junta os dois.
  - O bundle do Preview passa a ser igual nos três sistemas, e só ele muda em relação ao do build.
  - `bundle.schema.json` volta a exigir `^res://`, e o Preview usa uma variante (`$defs/PreviewAssets`) ou um campo `preview: true` no bundle.
  - Fora do modo preview, o runtime recusa qualquer caminho que não seja `res://`. O selfcheck ganha um código B0xx para isso.

#### V-05. "`user://` em memória" (D21) não existe no Godot, e plugins podem gravar direto em `user://`

- **Onde:** PP §1.4; RT §8.5 ("Todos os arquivos ficam em `user://`"); SDK §12.2 (W009 permite `FileAccess` em `user://`).
- **Problema:**
  - **O Godot não tem `user://` em memória.** No Web, `user://` é um sistema de arquivos guardado inteiro na IndexedDB. Então "prefixar as chaves com o `project.id`" não se aplica: o que dá para fazer é uma subpasta.
  - **A janela mistura projetos.** Na janela, `user://` é a pasta de dados do aplicativo do runtime do Preview, a mesma para todos os projetos.
  - **Plugins escapam do isolamento.** Um plugin que grava direto em `user://`, o que W009 permite, fura o isolamento por projeto e o modo "em memória".
- **Solução:**
  1. RT §8.5: o Save Manager grava por uma interface `VNStorage`, com três implementações:
     - `user://`, no jogo;
     - memória (um dicionário), no Preview padrão;
     - pasta, com `--vn-user-dir` na janela, ou `user://preview/<project.id>/` no painel.
  2. SDK: dados de plugin só pela API do runtime, que já usa o `VNStorage`. W009 passa a recusar `FileAccess`/`DirAccess` em `user://`, ou o SDK dá um `ctx.storage_dir` que o runtime aponta para o lugar certo.
  3. PP §1.4: trocar "prefixa as chaves" por "usa a subpasta `user://preview/<project.id>/`".

#### V-06. Os vetores de compilação dependem do exemplo, que muda

- **Onde:** spec 08 ("Um caso muda de hash só junto com uma mudança no compilador justificada pela spec"); BS §5.1; `conformance/compile/cases.json`.
- **Problema:** cada caso é "uma variação do exemplo das specs". Qualquer mudança no exemplo muda os 7 hashes, mesmo sem mexer no compilador; foi o que a troca de cenários fez (V-01). A frase da spec 08 está errada, e a regra de V-02 (o exemplo segue a demo) faria isso acontecer a cada atualização da demo.
- **Solução** (recomendada): os vetores passam a usar um projeto **congelado** só deles, `conformance/compile/base/`. É uma cópia do exemplo num dado momento, que não segue a demo.
  - O exemplo fica livre para acompanhar a demo.
  - Os hashes só mudam quando o compilador muda, e aí a frase da spec 08 fica verdadeira.
  
  Se o Luis preferir manter o exemplo vivo, a alternativa é mudar a frase para: "mudou o exemplo ou o compilador: o PR regera os hashes com `--print` e diz por quê".

#### V-07. Não há onde registrar o crédito de um asset de terceiros

- **Onde:** UI §3.1 (`licenses_list`, que lista só `plugins` e `fonts`); BS §4.5 (`vn_content/licenses.txt`); `assets.schema.json`, que não tem campo de autor nem de licença; Req (Asset Manager).
- **Evidência:** o crédito do Noraneko entrou na demo como um rótulo digitado à mão em `ui/credits.json`. Ele não segue o asset: se o cenário sair do jogo, o crédito fica; se outro projeto copiar o cenário, o crédito não vai junto.
- **Problema:**
  - Pacotes gratuitos de arte quase sempre pedem crédito, e o Studio é feito para quem usa esses pacotes. As specs só tratam licenças de plugins e de fontes.
  - O pedido do Luis ("créditos só no que chega ao jogador") sairia de graça se o crédito ficasse no asset, porque o build só leva os assets usados.
- **Solução:**
  - Em `assets.json`, um campo opcional `credit` em cada asset: `{ "author", "license", "url"?, "notice"? }`. Para um pacote inteiro, o mesmo `credit` em vários assets; o compilador agrupa os iguais.
  - BS §4.5: `licenses.txt` reúne também os `credit` **dos assets que entram no staging**. Um asset que não entra no jogo não aparece nos créditos.
  - UI §3.1: `licenses_list.include` ganha `assets`. U009 também avisa quando algum asset do build tem `credit` e a tela de créditos não tem a lista.
  - Req: o Asset Manager pergunta "De onde veio?" ao importar e grava o `credit`. Ao importar uma pasta com `ReadMe.txt`/`LICENSE`, sugere o texto do arquivo.
  - Na demo, o rótulo `bg_credit` sai e o `credit` vai nos quatro cenários. O filtro de V-02 tira o campo do exemplo das specs.

#### V-08. Nada diz o que fica fora do instalador do Studio e do runtime do Preview

- **Onde:** spec 09 §1 ("Runtime do Preview… embutidos no instalador") e §1.1 (`runtime/tests/fixtures/`); BS §7.1 (`exclude_filter`, só para jogos).
- **Problema:**
  - `runtime/tests/fixtures/` fica dentro do projeto Godot do runtime (`runtime/`). A release do runtime exporta desse projeto o export Web, o `runtime-preview.pck` e os templates. Nenhuma regra de exclusão é dada para essas exportações; o `exclude_filter` do BS §7.1 só vale para o jogo do autor.
  - Por padrão, o Godot exporta todos os recursos. Os assets de teste entrariam no instalador do Studio, o contrário do que o Luis pediu.
  - A spec 09 também não lista o que vai em cada artefato: instalador, templates, `.vnplugin` oficial e pacote npm.
- **Solução:**
  - Uma seção nova na spec 09, "Conteúdo dos artefatos", com uma tabela. Para cada artefato: o que entra e o que nunca entra (`tests/`, `docs/`, `spikes/`, `examples/`, `conformance/`, `*.md`).
  - Os presets de exportação do runtime (Web, `runtime-preview.pck` e templates) ganham `exclude_filter` com `tests/*`, `*/tests/*` e `docs/*`.
  - Um passo na CI de release lista o conteúdo de cada `.pck` e do instalador, e falha se aparecer um desses caminhos ou um arquivo de imagem ou áudio fora de `presets/`.

#### V-09. "Usar os cenários nos testes" esbarra na spec 09 §1.1 e na licença do pacote (decisão D22)

- **Onde:** spec 09 §1.1 ("Assets de teste… gerados por script… ou placeholders feitos à mão"); `assets/backgrounds/noraneko/ReadMe.txt`; pedido do Luis de 22/11.
- **Problema:**
  - Hoje os testes do produto só usam os **ids** dos cenários, sem imagens. Então "usar nos testes" foi cumprido só no nome.
  - Quando o runtime tiver testes com imagem, a spec 09 §1.1 proíbe arte de terceiros no repositório do produto.
  - Pôr o pacote lá também seria redistribuir. A licença pede o `ReadMe.txt` junto e crédito, o que vai contra "assets de teste sem créditos".
- **Solução (D22):** ver as opções na seção 5. A recomendação é a A: arte de verdade só nos testes de ponta a ponta. Eles clonam a demo numa versão fixa, como a spec 09 §1.1 já permite. Assim a arte e o crédito ficam só na demo, e o produto não tem arte nenhuma, nem nos testes. Escrever isso na spec 09 §1.1: "Arte de terceiros, mesmo para teste, só entra pela demo".

#### V-10. A Alice da demo continua sem autor e sem licença

- **Onde:** `gd-vn-studio-demo`: `source/alice.psd` (11 MB), `assets/characters/alice/*.png` e `CREDITS.md` ("A confirmar" nas três colunas); `ui/credits.json` ("Roteiro e arte: Seaside Team").
- **Problema:**
  - Um arquivo de origem desconhecida está no Git da demo e nos sprites do jogo. Se a licença proibir redistribuição, o arquivo precisa sair também do histórico.
  - A tela de créditos atribui a arte a um time que não fez nem os cenários nem a personagem.
- **Solução:**
  - Confirmar de onde veio o PSD antes de qualquer release da demo, ou antes de tornar o repositório público, se ainda não for.
  - Preencher `credit` nos três sprites (V-07).
  - Trocar o texto da tela para "Roteiro: …". A arte de terceiros passa a sair da lista de créditos dos assets.

### 2.3. BAIXO

| # | Onde | Problema | Solução |
|---|---|---|---|
| V-11 | `tools/validate.py → check_cf_guard`; UI §11 (R022) | O R022 das telas só olha o `visible_if`/`enabled_if` do **próprio** elemento. Um `container` com `visible_if: sys.ui.content_filter` que contém um botão com `effects` passa sem erro (testado: 0 erros) | Passar a guarda dos containers para os filhos (`ui_elements` com o estado do pai). Escrever "ou de um container que o contém" na UI §11 e acrescentar um caso em `test_validate.py` |
| V-12 | spec 09 §1.1 ("`backgrounds/beach_day.png`…"); `test_schemas.py`; `compile/cases.json` | Citam os ids e caminhos antigos, que a branch Noraneko não atualizou | Trocar no mesmo PR de V-01. O exemplo de id `bg/beach_day` na tabela de identificadores do DM §3 pode ficar, porque é só um exemplo de formato |
| V-13 | Exemplo das specs (branch Noraneko): `bg/train_evening_safe` → `Train_Transparent.png` | É o trem com as janelas vazadas, uma camada para compor. Como substituta de um `background`, mostra a cor de fundo do tema pelas janelas. E o arquivo não existe na demo | Usar a mesma substituta da demo: `Train_Evening.png` desfocado, gerado por script (V-01, passo 3) |
| V-14 | Demo (branch Noraneko) | Textos que não combinam com os cenários novos: capítulo "A praia"; o mestre pescador "do outro lado do vagão", seguido do minijogo de pesca; o festival no onsen à noite | Ajustar duas ou três falas, ou escolher para o pescador um dos 24 cenários do pacote que fique perto da água, se houver |

## 3. O que foi conferido e está coerente

- **Referências cruzadas:** as 636 citações entre specs (`DM §x`, `RT §x`, `SDK §x`, `UI §x`, `BS §x`, `PP §x`, `Req §x` e `spec 0x §x`) apontam para seções que existem.
- **Revisão de 17/11 aplicada:** W025, R022 nas telas (inclusive `on_open`, `on_close` e `back`), `censored_caption` e `censored_label`, `preview.set_setting` e os campos novos de `simulate`, `user_data`, o vetor `modo_stream_ligado_no_meio`, os 7 vetores de compilação, a gravação sempre da resposta da primeira abertura e `seen_assets` gravado com ou sem galeria. Tudo está no texto, nos schemas e nas ferramentas, e os números do README (133, 138 e 7) batem com o que as ferramentas imprimem.
- **Modo stream e eventos:** um evento `sys.content_filter_changed` não pode mudar a história pelo conteúdo, porque `event_since_last_selection` ignora `sys.*` (W019). Os hotspots de set só aceitam ações cosméticas (U004), então não precisam do R022.
- **Créditos e licença do Noraneko:** `CREDITS.md` da demo descreve certo os termos do pacote: crédito a "Noraneko Games", modificação permitida, venda avulsa proibida, uso comercial em jogo permitido com prova de crédito. O `ReadMe.txt` original está junto dos arquivos. O exemplo das specs não tem mais o crédito, como pedido.

## 4. Itens antigos que continuam abertos

Não são repetidos aqui; a análise está na auditoria de 2026-11-14 e na seção 4 da revisão de 2026-11-17. Conferi de novo no PR #9:

| Item | Situação em 2026-11-22 |
|---|---|
| M-01 | RT §3.0 passo 2 continua com `g001` para hash diferente; BS §13.1 tem `G002` |
| M-04 | `bundle-plugins.schema.json` continua sem `integrity`; RT §3.0 passo 5 continua "conferindo `integrity`" |
| M-05, B-03 | RT §2 cita `project.json → ui.preset`, que o schema não tem; DM §10.3 e UI §1 ainda citam `modern` e `minimal` como se já existissem |
| M-06 | DM §4.3 e UI §3.2 continuam dando listas diferentes de valores para `sys.ui.last_activity_outcome` |
| M-10 | `PlayerSettings.resolution` continua sem padrão |
| A-07, M-03, M-07 a M-09, M-11 a M-21, B-02, B-04, B-05, B-09, B-12, B-23, B-24 | Não reconferidos nesta rodada; nada no PR #9 mexe neles |

## 5. Decisões para o Luis

| # | Decisão | Opções | Recomendação |
|---|---|---|---|
| D22 | Onde entram os assets de terceiros usados em testes (V-09) | **A.** Só pela demo: testes de ponta a ponta clonam a demo numa versão fixa; o produto continua sem arte. **B.** Uma pasta `runtime/tests/fixtures/third_party/` com o `ReadMe.txt` de cada pacote, fora de todos os artefatos (V-08) | **A.** É o que a spec 09 já permite, a licença fica cumprida na demo e o produto não precisa de créditos |
| D23 | Como o exemplo das specs acompanha a demo (V-02, V-06) | **A.** Cópia filtrada por script, com CI, e vetores de compilação num projeto congelado à parte. **B.** O exemplo fica independente da demo, e a regra "uma fonte" sai da spec 09 | **A.** Mantém uma fonte só e tira os hashes do caminho |

## 6. Ordem sugerida

1. **Já, antes de qualquer merge:** V-01. Primeiro o merge do PR #9 e do PR #5; depois refazer as branches Noraneko sobre a `main` nova; regerar os hashes; fazer o mesmo cenário censurado na demo e no exemplo (V-13); e V-12.
2. **Junto, num PR de infraestrutura:** V-02 e V-06 (D23), com a workflow `specs.yml`, e V-11.
3. **Antes do runtime:** V-03 (palco), V-05 (`VNStorage`) e os itens antigos M-01, M-04, M-05 e M-06.
4. **Antes do Studio:** V-04 (caminhos do Preview) e V-07 (`credit` nos assets e no Asset Manager).
5. **Antes da primeira release:** V-08 (conteúdo dos artefatos), D22 e V-10 (origem da Alice).
6. **Editorial, na demo:** V-14.
