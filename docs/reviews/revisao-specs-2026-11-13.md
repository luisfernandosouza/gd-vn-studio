# Revisão das especificações: lacunas, inconsistências e ambiguidades

- **Data:** 2026-11-13
- **Escopo:** `specs/` inteiro: docs 00 a 05, README, os 13 schemas, `examples/` (demo-project, demo-save, fishing-plugin) e `tools/validate.py`.
- **Método:** leitura cruzada de documento × schema × exemplo × validador. Rodei o validador sobre os exemplos (`0 erro(s), 0 aviso(s)`, com e sem `--export`) e testei alguns casos-limite direto nos schemas.
- **Fora da revisão:** a decisão de embutir o Godot no Studio (já tomada) e o que o próprio README já marca como "em aberto" (assinatura v2, DLC, sandbox de plugins não confiáveis). Só cito esses pontos quando eles causam outro problema.
- **Nenhum arquivo das specs foi alterado.**

## Como ler

| Gravidade | Critério |
|---|---|
| **Alta** | Comportamento indefinido num fluxo comum, contradição que obriga a escolher entre dois documentos, ou risco de segurança. Precisa de decisão antes de implementar. |
| **Média** | Lacuna que vai aparecer na implementação ou no uso real, mas tem solução local e não muda a arquitetura. |
| **Baixa** | Inconsistência de texto, referência quebrada, exemplo incoerente ou detalhe que confunde quem lê. Correção rápida. |

Cada item traz **onde**, **problema** e **sugestão**. Total: 8 altas, 26 médias, 22 baixas.

## Resumo: os 8 pontos que eu resolveria primeiro

1. **A1:** o que `{"result": "campo"}` vale quando a atividade é pulada (payload vazio). O próprio demo quebra nesse caso.
2. **A2:** o determinismo entre o runtime Godot e o Preview em TypeScript não tem base especificada (algoritmo de RNG, aritmética, formatação).
3. **A3:** o RNG compartilhado entre plugins e narrativa torna o traço não reprodutível depois de qualquer minijogo.
4. **A4:** o nó `choice` sem opções visíveis: o Data Model diz "segue `next`", o schema diz "`next` é ignorado".
5. **A5:** pedidos de cena (`then.scene`, `fallback_scene`, `entry_scene`, `grants.scenes`) podem apontar para cena de outro capítulo, sem regra.
6. **A6:** o "documento lógico do projeto" sobre o qual o JSON Patch do Editor SDK opera não está definido.
7. **A7:** a "atualização expressa" publica código GDScript novo sem revisão humana, embora runtime plugins não sejam isolados.
8. **A8:** o save omite valores iguais ao padrão, o que muda silenciosamente o estado do jogador quando um default muda numa atualização.

---

## Alta

### A1. Resultado de atividade pulada, ou com payload incompleto
- **Onde:** RT §5.3 passos 6–7; SDK §6; `scene_beach.json` (nó plugin); `test_fishing.gd` (`test_pular_usa_default_outcome_e_nao_emite_evento`).
- **Problema:** quando o jogador pula a atividade, o runtime completa com `default_outcome` e **payload vazio** e depois aplica `on_result.effects`. No demo, esses efeitos leem `{"result": "won"}`, `{"result": "score"}` e `{"result": "fish_count"}`. Nenhum documento diz o que um campo ausente vale. Pode ser erro de conteúdo (a transação aborta e, em debug, aparece o overlay), `null` (e aí T001 em `set` de um booleano) ou o default do tipo. O mesmo acontece em release, onde o `payload` não é validado contra `result_schema`.
- **Sugestão:** escolher uma destas regras e escrevê-la no RT §5.3 e no DM §6.1:
  - (a) **recomendada:** no pulo, `on_result.effects` **não** é aplicado, só o desvio por outcome;
  - (b) `{"result": x}` aceita um `"default"` (`{"result": "score", "default": 0}`) e, sem ele, um campo ausente vale o default do tipo da variável de destino;
  - (c) o manifesto declara um `skip_payload` junto com o `default_outcome`.
  Em qualquer caso, o validador deveria checar os campos `{result}` contra o `result_schema` da atividade (hoje não checa).

### A2. A conformidade entre os dois interpretadores não tem base especificada
- **Onde:** RT §1 e §12 ("os dois interpretadores DEVEM produzir o mesmo resultado"); DM §5.1, §6.1, §9; `save.schema.json → rng`.
- **Problema:** o traço idêntico depende de coisas que nenhum documento fixa:
  - **RNG:** algoritmo, como `seed`/`state` evoluem, como `random_int(min, max)` mapeia (limites inclusivos?) e como `weighted_pick` escolhe. O `RandomNumberGenerator` do Godot usa PCG32 com estado de 64 bits. Em `JSON.parse` do TypeScript, inteiros acima de 2^53 perdem precisão, então `rng.state` gravado como inteiro JSON pode ser corrompido pelo Preview.
  - **Aritmética:** se `div` entre inteiros devolve inteiro ou real; qual o tipo do resultado de `floor`, `round` e `ceil` (o demo faz `floor(div(score, 100))` e soma numa `integer`); o modo de arredondamento de `round` (meio para longe do zero ou meio para o par?); o sinal de `mod` com negativos; e o que "`1` ≠ `1.0`" significa, já que o JS não distingue os dois.
  - **Formatação:** "números são formatados conforme o idioma" (DM §9) sem regra. O GDScript não tem ICU; o TS tem `Intl`. O texto interpolado vai divergir.
- **Sugestão:** acrescentar ao RT um **§12.1 "Semântica de referência"** que fixe: PCG32 (ou xoshiro128**, que cabe em 32 bits e é trivial nas duas linguagens), com `state` serializado como **string hexadecimal**; `weighted_pick` por soma cumulativa sobre a lista ordenada por `id`; uma tabela de assinatura e tipo de cada função; e uma formatação numérica própria e mínima (separadores por locale numa tabela do runtime), sem depender de ICU. Os vetores de conformidade deveriam incluir casos para cada linha dessa tabela.

### A3. O RNG compartilhado entre plugin e narrativa quebra o determinismo
- **Onde:** SDK §5.2 (`ctx.rng`: "RNG determinístico do State Manager"); RT §12; `fishing_game.gd` (`_rng.randf()` a cada peixe).
- **Problema:** o minijogo consome o mesmo RNG da narrativa num número de vezes que depende de input em tempo real. Depois de qualquer atividade, o estado do RNG narrativo difere entre duas partidas, e também entre o Preview no Studio (onde o mock não consome nada) e o Preview no Runtime. Um `random_int` ou um `weighted_random` posterior diverge, e os vetores de conformidade não conseguem cobrir cenas que vêm depois de minijogos.
- **Sugestão:** dar a cada atividade um **fluxo de RNG derivado** (`seed` da atividade = hash(seed do jogo, `selection_count`, id do nó)), sem tocar no RNG narrativo. O `ctx.rng` fora de atividades pode seguir a mesma regra, derivando de `(seed, namespace)`.

### A4. Nó `choice` sem opções visíveis: `next` vale ou não?
- **Onde:** DM §8.2 ("Se nenhuma opção estiver visível, o runtime segue `next` do nó de escolha"); `scene.schema.json → ChoiceNode.description` ("'next' do nó é ignorado"); `validate.py → succ()` (para `choice`, só considera os `goto` das opções).
- **Problema:** contradição direta. Além disso, o validador não conta `next` como sucessor do `choice`, então um nó alcançável só por esse caminho recebe W001 falso.
- **Sugestão:** manter a regra do DM (é a rede de segurança que o W006 pressupõe), corrigir a descrição do schema para "`next` é usado só quando nenhuma opção está visível" e incluir `next` (ou o nó seguinte do array) em `succ()` para `choice`.

### A5. Pedido de cena para outro capítulo
- **Onde:** RT §4.3 passo 2 (`s.mode == "manual" or eligible(s, n)`); DM §7–8.2; SDK §5.5; `plugins.schema.json → grants.scenes`; validador (R006 só confere se a cena existe).
- **Problema:** `end.then.scene`, `grants.scenes`, `entry_scene` e `fallback_scene` podem apontar para uma cena de **outro capítulo**. Para cenas `manual`, o RT aceita o pedido sem conferir o capítulo. A cena roda com `sys.chapter.id` do capítulo atual, e as variáveis `chapter.*` dela (validadas contra o capítulo dela) passam a falhar com `SCOPE_INACTIVE` ou a ler o capítulo errado.
- **Sugestão:** criar uma regra de validação nova (ex.: **R014**): o destino de `then.scene`, `entry_scene`, `fallback_scene` e `grants.scenes` DEVE ser do mesmo capítulo ou global (`chapter: null`). Escrever no RT §4.3 que um pedido para cena de outro capítulo é recusado. Se a intenção for permitir pular de capítulo, usar um `then: {"chapter": …}` explícito, que passa por `CHAPTER_EXIT`/`CHAPTER_ENTER`.

### A6. O "documento lógico do projeto" do Editor SDK não está definido
- **Onde:** SDK §10.4 (`applyEdit` recebe JSON Patch "sobre o documento lógico do projeto"); Req §2 e §8 (o próprio Studio usa o mesmo mecanismo no undo/redo).
- **Problema:** JSON Patch precisa de caminhos (`/scenes/<uuid>/nodes/3/text`), mas a estrutura do documento lógico não aparece em lugar nenhum. Faltam: a raiz (um objeto com `scenes` e `chapters` indexados por UUID?); se `nodes` é endereçado por índice (frágil quando dois editores inserem passos) ou por id; como um plugin cria uma entidade nova (não há API para gerar UUIDv7); e como o Studio resolve concorrência quando dois patches tocam o mesmo array. Como esse é o contrato central do Editor SDK e do undo/redo, sem ele não dá para implementar nenhuma das duas coisas.
- **Sugestão:** um §10.4.1 com o schema do documento lógico. A raiz seria `{project, variables, assets, theme, plugins, characters: {uuid: …}, chapters: {uuid: …}, scenes: {uuid: …}}`. Coleções de entidades indexadas por id, e `nodes` endereçável também por id via um ponteiro estendido (ex.: `/scenes/<id>/nodes/@<node-id>/text`). Acrescentar `ctx.ids.newEntityId()` à API e a regra de que `test` (RFC 6902) é obrigatório antes de `replace`/`remove` para detectar conflito.

### A7. Atualização expressa sem revisão humana publica código não isolado
- **Onde:** SDK §13.5 passo 7; SDK §4.3; ADD §8.2 ("externos com revisão obrigatória antes do catálogo oficial").
- **Problema:** depois do primeiro `published`, uma versão PATCH ou MINOR "sem permissão nova, sem W009 e com CI verde" entra sem revisão humana. Só que runtime plugins rodam no processo do Godot **sem isolamento**, e o próprio SDK diz que as permissões protegem contra erro, não contra código malicioso. Uma conta de publisher comprometida consegue distribuir código arbitrário para todos os projetos que aceitam atualizações. Isso contradiz o ADD §8.2, e o W009 é uma busca por regex, fácil de contornar (ex.: `ClassDB.instantiate("HTTP" + "Request")`).
- **Sugestão:** limitar a via expressa a mudanças **sem diff em `runtime/`** (só docs, `editor/` ou `plugin_locales`), ou só a plugins `official`. Para os demais, manter a revisão humana com o diff de código. Acrescentar uma **janela de quarentena** (ex.: 72 h em `review` público) antes de o Studio oferecer a atualização, e fazer o Studio nunca atualizar o lock sozinho (o SDK §11.3 já diz isso; vale repetir no §13).

### A8. Save que omite valores iguais ao padrão, e `is_default`
- **Onde:** `save.schema.json → state.variables` ("Somente variáveis com persistence=save e valor diferente do padrão"); RT §8.2 e §8.4; DM §5.1 (`is_default`: "verdadeiro se a variável nunca saiu do padrão").
- **Problema:**
  1. Se uma atualização do jogo muda o `default` de uma variável, todo save em que o jogador tinha o valor antigo (igual ao default antigo e por isso omitido) carrega com o **novo** default. Isso muda o estado da história sem aviso, e o RT §8.4 não cobre o caso.
  2. "Nunca saiu do padrão" exige guardar um histórico, que o save não tem. O Req §3.1 traduz o operador como "ainda não mudou". Uma variável que foi a 5 e voltou a 0 é `is_default` ou não?
  3. Para variáveis de personagem, não se diz se "padrão" é o `default` do modelo ou o `initial_values` do personagem.
- **Sugestão:** gravar **todas** as variáveis `persistence: save` (o custo é pequeno), ou gravar junto o mapa de defaults vigentes, e redefinir `is_default` como "valor atual igual ao padrão efetivo (`initial_values` > `default`)", ajustando o texto do Req para "está no valor inicial".

---

## Média

### M1. `activity_timeout_seconds` não existe no schema
- **Onde:** RT §5.3 passo 8; `project.schema.json → settings`.
- **Problema:** o RT cita um timeout "por projeto" que não tem campo no schema (`settings` tem `additionalProperties: false`).
- **Sugestão:** acrescentar `settings.activity_timeout_seconds` (inteiro ≥ 1, ausente = desligado), ou mover o timeout para o nó `plugin` ou para a declaração da atividade, onde faz mais sentido.

### M2. Eventos `sys.*`: lista, momento, payload e efeito em `events_since_selection`
- **Onde:** RT §7.1 (lista de 11 eventos); RT §3, §5 e §8 (passos do ciclo de vida); RT §7.2; `demo-save.json`.
- **Problema:**
  - `sys.game_started`, `sys.activity_started`, `sys.activity_completed` e `sys.game_saved` estão na lista, mas não aparecem em nenhum passo do ciclo de vida, então não se sabe quando são emitidos.
  - Nenhum evento `sys.*` tem payload definido (só `{ scene }` em dois casos).
  - O RT §7.2 diz que **todo** evento entregue entra em `events_since_selection`. Depois de uma cena com escolha e minijogo, a lista teria `sys.scene_started`, `sys.choice_made`, `sys.activity_*`, `fishing.completed` e `sys.scene_ended`, mas o `demo-save.json` mostra só `fishing.completed`.
- **Sugestão:** uma tabela no RT §7.1 com evento, momento exato (passo do ciclo) e schema do payload. Definir se `sys.*` entra em `events_since_selection` (recomendo que não, para manter o save enxuto) e ajustar o exemplo.

### M3. `on_overflow: reject` é controle de fluxo, mas é tratado como erro
- **Onde:** DM §4.2 e §6.2; RT §5.2 (`effects`: "se falhar, registra erro e segue mesmo assim"); RT §9 (debug pausa com overlay); demo `variables.json` (`player_money` com `reject`).
- **Problema:** "não tem dinheiro suficiente" é lógica de jogo normal, mas a falha da transação é tratada como erro de conteúdo: em debug pausa com overlay, e o autor não tem como desviar quando a compra falha. Também não está definido o que acontece quando os `effects` de uma **opção de escolha** falham: segue para `goto` mesmo assim?
- **Sugestão:** separar `CONSTRAINT_VIOLATION` dos erros de conteúdo (sem overlay, só log). Dar ao nó `effects` um `on_fail` opcional (destino) e dizer, no RT §5.2, que nas escolhas a falha não impede o `goto`. O Studio deveria sugerir `enabled_if` sempre que um efeito pode violar `reject` (o demo já faz isso com o sorvete).

### M4. Laço infinito de `fallback_scene` sem aviso nem proteção
- **Onde:** RT §4.3 (texto após o algoritmo: "o validador avisa se ela não altera nada que faça o capítulo progredir"); DM §11.
- **Problema:** esse aviso não tem código (o W005 é outra coisa) e não está no validador. Uma `fallback_scene` que não aproxima `completion.conditions` roda para sempre. O mesmo vale para `on_exhausted: scene` sem `completion`.
- **Sugestão:** criar o **W010** "fallback não altera nenhuma variável usada em `completion.conditions`" e, no runtime, um limite (ex.: 100 seleções seguidas da `fallback_scene` → erro de conteúdo → `advance`).

### M5. Chaves de tradução para textos fora das cenas
- **Onde:** DM §3 e §9; `locale.schema.json`; `chapter`, `project.endings`, `character.display_name`, `theme.screens.credits.text`, `project.title`.
- **Problema:** só existem caminhos para fala (`<cena>/<nó>`), opção (`<cena>/<nó>/<opção>`) e `character/alice/name`. Faltam caminhos para o título de capítulo, o título e a descrição de final, `display_name`, os créditos e o título do jogo (que é `string`, não `LocalizedText`). Também não está claro se `character/<x>/name` usa a `key` ou o UUID (os exemplos usam a key; o DM §3 diz que entidades usam UUID). Por fim, não se diz em qual arquivo de `locales/<lang>/` cada chave fica, se o nome do arquivo é derivado do título e muda quando o título muda.
- **Sugestão:** uma tabela de caminhos no DM §9: `chapter/<uuid>/title`, `ending/<id>/title|description`, `character/<uuid>/name|display_name`, `theme/credits/text`, `project/title`. O arquivo de locale deveria ser escolhido **pelo id** (`locales/<lang>/scenes/<uuid>.json`, `locales/<lang>/project.json`), não pelo título.

### M6. Marcação de texto (rich text) não especificada
- **Onde:** DM §9; `common.schema.json → LocalizedText`.
- **Problema:** autores de VN usam negrito, cor, pausas no meio da fala, velocidade e quebras. Nada disso está definido, nem como interage com a interpolação, com o escape `{{`, com a tradução e com `seen_text`. Cada implementação (Godot `RichTextLabel` com BBCode, Preview em HTML) vai inventar a sua.
- **Sugestão:** definir um subconjunto pequeno (ex.: `[b]`, `[i]`, `[color=#hex]`, `[pause=0.5]`, `[speed=2]`) com a semântica escrita no DM §9, convertido por cada interpretador. Se ficar para depois, declarar no DM §13 que o v1 é texto puro.

### M7. Backlog guardado como texto renderizado
- **Onde:** `save.schema.json → state.backlog` (array de strings); RT §8.2.
- **Problema:** se o jogador troca de idioma, o backlog continua no idioma antigo. Uma atualização do jogo não corrige erros de digitação no backlog salvo, e o tamanho cresce com o texto completo.
- **Sugestão:** guardar entradas `{ path, speaker, vars }` (caminho de texto e os valores interpolados no momento) e renderizar ao exibir.

### M8. Modelo de saves e configurações do jogador
- **Onde:** RT §8; `save.schema.json → Profile`; `theme.schema.json → screens.title.buttons` (`continue`, `load`, `settings`).
- **Problema:** não está definido:
  - quantos slots existem, se há quicksave, qual save o "Continuar" abre, o nome e o local dos arquivos e o formato da miniatura;
  - onde ficam as configurações do jogador (volumes, velocidade do texto, auto, "pular só lido", tela cheia, idioma), que não estão nem no save nem no `Profile`;
  - o crescimento de `seen_text` (cresce sem limite);
  - se é aceitável gravar o `profile.json` "a cada mudança" (RT §6.5), ou seja, a cada fala lida (`seen_text`). No Web isso é IndexedDB.
- **Sugestão:** um RT §8.5 "Slots e arquivos" e um `settings.json` separado do perfil, sem assinatura. Guardar `seen_text` como conjunto compacto (ex.: hash de 64 bits por caminho) e gravar o perfil com *debounce* (ex.: a cada ponto de seleção e ao sair).

### M9. `SAVE_KEY` presa ao cofre de uma máquina
- **Onde:** BS §8.1.
- **Problema:** a chave é criada na primeira exportação e fica no cofre do SO daquela máquina. Em equipe, ou depois de trocar de computador, outra pessoa exporta com outra chave, e todos os saves dos jogadores passam a aparecer como modificados (com `reject`, deixam de carregar). Hoje isso é só um aviso.
- **Sugestão:** um comando "Exportar/importar chave de saves" (arquivo protegido por senha) e um aviso **bloqueante** no assistente quando o projeto já tem builds publicados (dá para saber pelo histórico do §9.3) e a chave não está no cofre. Opcionalmente, gravar no projeto uma impressão digital da chave (hash), para detectar a troca.

### M10. Versão do Godot como SemVer com `-stable`
- **Onde:** BS §9.2 (`"godot": "4.3.0-stable"`); BS §2.1 e B014; demo `project.json → runtime.godot` (`">=4.3.0 <5.0.0"`); `compatibility.godot` no plugin.
- **Problema:** em node-semver, `4.3.0-stable` é *pré-release* e **não** satisfaz `>=4.3.0 <5.0.0`, o que dispararia B014 falso. Além disso, o Godot numera `4.3` (sem patch) e `4.3.1`.
- **Sugestão:** normalizar a versão do Godot para SemVer puro (`4.3.0`) em toda comparação e guardar o rótulo original (`4.3-stable`) só para exibição. Escrever essa regra no BS §2.1.

### M11. Representação de hashes inconsistente
- **Onde:** `common.schema.json → Hash` (`sha256-<base64>`); BS §4.1 (`build_id` usa "8 primeiros hex do `content_hash`"); BS §5.2 (32 bytes crus no cabeçalho do `.vnb`); BS §9.2 (`"content_hash": "sha256-..."`).
- **Problema:** o mesmo hash aparece em base64 SRI, em hex e em bytes, e não existe regra de conversão. Ferramentas e pessoas vão comparar strings diferentes.
- **Sugestão:** escrever no BS §5.1 a forma canônica (SRI base64 em JSON, bytes crus em binário) e definir `build_id` com "8 primeiros caracteres hex do SHA-256", explicitando a conversão.

### M12. IDs de asset "trocados por caminhos" no bundle
- **Onde:** BS §5.1 ("IDs de assets trocados por caminhos `res://`"); RT §2 ("assets (IDs→caminhos res://)"); SDK §5.6 (`load_asset(asset_id)`); `save.schema.json → Stage` (guarda `AssetRef`).
- **Problema:** se os IDs forem **substituídos** no conteúdo compilado, o runtime não consegue resolver IDs vindos de plugins (`load_asset`, `audio.play`), nem do Stage salvo, nem de saves de versões anteriores. O RT descreve um mapa, o BS descreve uma substituição.
- **Sugestão:** manter IDs no conteúdo e um mapa `assets: {id → res://…}` no bundle. Corrigir o BS §5.1.

### M13. Idioma-base do plugin não declarado
- **Onde:** SDK §5.7 e §6; `plugin.schema.json → plugin_locales`; `fishing-plugin/plugin.json`; Req §9.
- **Problema:** no Fishing, os textos para o autor estão em pt-BR (`"name": "Sessão de pesca"`), os fallbacks do jogador no GDScript estão em inglês (`"Fish: {count}"`) e `plugin_locales` tem `en` e `pt-BR`. Não há campo que diga qual é o idioma-base. Além disso, a planilha de tradução (Req §9) precisa do **texto-fonte** das chaves `runtime/…`, mas o fallback vive dentro do código GDScript, que o Studio não lê.
- **Sugestão:** acrescentar `default_locale` ao manifesto e exigir que toda chave `runtime/…` usada exista em `plugin_locales[default_locale]` (o validador pode extrair as chaves das chamadas `i18n.text(...)`, como já faz com P011 e P012).

### M14. Renomear chave de variável depois de lançar o jogo
- **Onde:** Req §2 ("Renomear em todo o projeto"); RT §8.4 ("Variável do save não existe mais → descartada").
- **Problema:** renomear `player_money` depois de publicado faz os saves dos jogadores perderem o valor. O mesmo vale para a `key` de personagem e para IDs de asset no Stage salvo.
- **Sugestão:** o comando de renomear grava um alias (`variables.json → renamed_from: ["player_money"]`) que o compilador leva para o bundle, e o Save Manager aplica na carga. O assistente avisa quando a renomeação acontece depois do primeiro build de release.

### M15. Sequência de chamadas aos plugins ao carregar um save
- **Onde:** SDK §5.1 ("Ao carregar save: `_vn_game_started(false)` → `_vn_migrate_save_data` → `_vn_load`"); RT §8.3 passo 4 (só migração e load); `fishing_plugin.gd`.
- **Problema:**
  1. O RT §8.3 não chama `_vn_game_started(false)`.
  2. Carregar no meio de um jogo (sem voltar ao título) não diz se `_vn_game_ended` é chamado antes.
  3. Se o save não tem dados do plugin (save anterior à instalação), `_vn_load` não é chamado e o plugin fica com o estado da partida anterior. No Fishing, `_rod_level` "vaza" entre partidas.
- **Sugestão:** fixar a ordem no RT §8.3: `_vn_game_ended` (se havia jogo) → `_vn_game_started(false)` → migração → `_vn_load(data)`, com `_vn_load(null)` quando não houver dados, para o plugin reiniciar o estado.

### M16. "Toda chamada retorna `PERMISSION_DENIED`" não cabe nas assinaturas
- **Onde:** SDK §5.2; SDK §5.6 (`play()` → `void`, `push_overlay()` → `Node`, `load_asset()` → `Resource`, `get_value()` → `Variant`).
- **Problema:** métodos que não retornam `VNResult` não têm como devolver `PERMISSION_DENIED`. Não se sabe se `get_value` sem permissão devolve `fallback`, `null` ou dispara erro.
- **Sugestão:** dizer explicitamente: métodos sem `VNResult` retornam `null` ou não fazem nada, registram no log e emitem `plugin.permission_denied` (RT §11). `get_value` sem permissão devolve `fallback`. Ou então padronizar tudo para `VNResult`.

### M17. Plugins só de runtime não conseguem migrar `config`
- **Onde:** SDK §8 ("Mudança incompatível no schema exige `migrate_config` no Editor SDK"); SDK §10.5.
- **Problema:** `migrateConfig` é exportado pelo entrypoint de editor. Uma Runtime Extension (`targets: ["runtime"]`) não tem entrypoint de editor e, portanto, não consegue migrar a própria configuração.
- **Sugestão:** permitir migrações declarativas no manifesto (`config_migrations: [{from: "1", ops: [JSON Patch]}]`), ou aceitar um entrypoint `migrations` mínimo sem `targets: editor`.

### M18. Lacunas do validador de referência
- **Onde:** `tools/validate.py`; DM §11.
- **Problema:** além do que o DM já declara pendente (T004, W005, W006), o validador não confere:
  - expressões `derived` em `variables.json` (nem R005 nem T001);
  - `next[].conditions` dos capítulos (só `completion`);
  - se `entry_scene`/`fallback_scene` pertencem ao capítulo;
  - referências `sys.*` (aceita qualquer coisa, como `sys.scenes.<uuid inexistente>.plays`);
  - o tipo da variável de `record` (precisa ser `string`/`enum`, e no caso de `enum` os valores precisam ser os IDs das opções, que são UUIDs; o demo usa `"fish"`/`"talk"`, ver B12);
  - `{result}` fora de `on_result.effects`;
  - T001 para `{"var": …}` com tipos diferentes;
  - `persistence: profile` fora de global/plugin (DM §4.4);
  - coerência entre `plugin-lock.json` e `plugins.json` (versão dentro da faixa, namespace igual ao manifesto, `enabled`);
  - `ending` com `then` diferente de `end_game`;
  - leitura concedida em variável com `plugins_read: none` (nem existe código para isso: o P008 cobre só escrita);
  - colisão de UUID entre entidades de tipos diferentes;
  - nó `start` inexistente (vira W001 em todos os nós em vez de R009).
- **Sugestão:** criar códigos para o que falta (ex.: P014 para leitura com `plugins_read: none`) e implementar a lista acima. Os vetores de teste do validador deveriam ter um projeto "quebrado" de propósito, com um erro de cada código; hoje só existe o caso feliz.

### M19. Mesmo id de grupo de exclusividade no projeto e no capítulo
- **Onde:** DM §7; `project.exclusive_groups` e `chapter.exclusive_groups`; `save.schema.json → history.groups` (indexado só pelo id).
- **Problema:** se o mesmo `id` existe nos dois níveis, não se sabe qual vale, qual `max_plays` se aplica e qual histórico zera ao sair do capítulo.
- **Sugestão:** proibir a colisão (erro novo, ou estender o R008) ou indexar o histórico por `chapter:<uuid>:<id>` / `game:<id>`.

### M20. `entry_scene` e reentrada em capítulo
- **Onde:** RT §3.2 passo 5; DM §7 (`next`); `history.chapters.entries`.
- **Problema:** `entries` sugere que um capítulo pode ser reentrado (via `next` apontando para trás), mas isso não está dito. Não se sabe se a `entry_scene` respeita `max_plays` e `conditions` na segunda entrada; o padrão `max_plays: 1` impediria a reexecução, mas o RT diz "inicia-a diretamente". Também não se diz se `completion.conditions` é avaliada logo depois da `entry_scene`.
- **Sugestão:** declarar no DM §7 se ciclos entre capítulos são permitidos. Se forem, dizer que `entry_scene` ignora `max_plays` (como a `fallback_scene`) e que as cenas do capítulo mantêm o `plays` anterior.

### M21. `next[].conditions` do capítulo e variáveis `chapter.*`
- **Onde:** RT §3.3 (passo 2 descarta `chapter.*`, passo 3 avalia `next[].conditions`).
- **Problema:** pela ordem dos passos, `next[].conditions` não pode usar `chapter.*`, mas isso não está escrito em lugar nenhum e o validador não confere (M18). Um autor naturalmente escreveria "se `chapter.days_passed` ≥ 5, vá para o capítulo secreto".
- **Sugestão:** inverter os passos 2 e 3 (avaliar `next` antes de descartar), que é o comportamento mais intuitivo, e escrever a regra.

### M22. A importação de roteiro gera cena inválida
- **Onde:** Req §10 ("os destinos ficam vazios"; "nó marcado 'a resolver'"); `scene.schema.json` (`options[].goto` obrigatório; sem campo para "a resolver").
- **Problema:** o resultado da importação não passa no schema, e o marcador "a resolver" não tem representação.
- **Sugestão:** tornar `goto` opcional (ausente = segue `next` do nó de escolha, coerente com A4) e acrescentar ao `NodeBase` um `unresolved: { reason }` que o validador transforma em aviso (e em erro com `--export`).

### M23. `--vn-selfcheck` não passa de nós bloqueantes
- **Onde:** BS §12 passo 4 ("roda até o primeiro ponto de seleção").
- **Problema:** com uma `entry_scene` que tem falas e escolhas, o modo headless precisa de alguém avançando o texto e escolhendo opções, e isso não está definido. A verificação vai travar ou expirar.
- **Sugestão:** o selfcheck roda com auto-avanço e escolhe sempre a primeira opção habilitada; atividades completam com `default_outcome` (ou com o mock declarado). Fixar também um timeout.

### M24. AES-CTR sobre ECB em GDScript
- **Onde:** BS §5.2.
- **Problema:** implementar CTR em GDScript chama `AESContext.update` bloco a bloco (16 bytes) e faz o XOR num laço interpretado. Para bundles de vários MB, isso pode levar segundos no boot, principalmente no Web.
- **Sugestão:** usar **AES-256-CBC**, que o `AESContext` faz nativamente em uma chamada só (IV no lugar do nonce, padding PKCS#7 feito no runtime). Como o princípio 6 já diz que é ofuscação, CBC não perde nada. Ou medir antes de decidir (vale acrescentar à lista de pendências do BS §15).

### M25. Escrita a partir de outra thread × `VNResult` síncrono
- **Onde:** RT §6.1 ("Chamadas de outras threads DEVEM ser reenviadas com `call_deferred`; o SDK faz isso automaticamente"); SDK §5.3 (métodos retornam `VNResult`).
- **Problema:** se a chamada é adiada, o `VNResult` não pode ser devolvido na hora. O texto não diz o que a chamada retorna (sucesso otimista? erro?).
- **Sugestão:** fora da thread principal, a chamada retorna `VNResult` com erro `WRONG_THREAD` em debug e em release (sem reenvio automático), ou o SDK oferece variantes `*_async()` que devolvem um sinal. É mais simples e mais previsível que o reenvio silencioso.

### M26. `audio.play` sem `stop`, e o que `input.capture` faz
- **Onde:** SDK §4.2 e §5.6; `fishing_game.gd` (usa `_unhandled_input`).
- **Problema:** um plugin pode tocar um loop no canal `ambient` e não tem como parar. Já `input.capture` não diz o mecanismo: um overlay recebe `_unhandled_input` de qualquer jeito, então o que a capacidade de fato libera ou bloqueia?
- **Sugestão:** `play()` devolve um handle com `stop(fade)`, e o runtime para os sons do plugin ao fim da atividade. Especificar que, sem `input.capture`, a `CanvasLayer` do plugin tem `process_mode`/`mouse_filter` que ignoram input e a UI narrativa continua com o foco; com a capacidade, a UI narrativa deixa de processar input durante a atividade.

---

## Baixa

| # | Onde | Problema | Sugestão |
|---|---|---|---|
| B1 | `plugin-lock.schema.json → link.description` | Diz que o build recusa o vínculo com **B003** (que é "versão revogada"). | Trocar por **P013**. |
| B2 | `plugin.schema.json → plugin_locales.description` | Cita `ctx.tr()`; o SDK §5.7 renomeou de propósito para `ctx.i18n.text`. | Corrigir o texto. |
| B3 | `plugin.schema.json → save.data_version.description` | Cita `migrate_save_data()`; o nome real é `_vn_migrate_save_data`. | Corrigir o texto. |
| B4 | BS §5.3 | "validação do schema e regra R0xx": o schema não consegue checar que `build.locales` contém `default_locale`, e a regra já existe (R013). | "Regra R013 do validador". |
| B5 | BS §8.3 (última frase) e BS §15 item 4 | Pedem para acrescentar `sys.save_modified` ao DM §4.3, mas ela já está lá. | Remover a pendência. |
| B6 | RT §6.2 linha 5 | "plugins: §6.4 do Data Model" não existe; o certo é DM §4.6. | Corrigir a referência. |
| B7 | `variables.schema.json → character.description` | Diz `character.<id>.<key>`; o certo é a `key` do personagem. | `character.<key do personagem>.<key>`. |
| B8 | `scene.schema.json → order`; DM §8.1; RT §4.3 | O schema diz "Padrão: ordem alfabética do id"; o RT usa `order ?? +inf` (cenas sem `order` vêm **depois** de todas com `order`, e só então por id). | Escrever a regra do RT nos três lugares. |
| B9 | `scene.schema.json → mode.description` | Lista os links que executam cena `manual`, mas esquece `scenes.request` de plugins. | Acrescentar. |
| B10 | `plugins.schema.json → source`; demo `plugins.json` | `catalog:<nome>` é ambíguo (nome do catálogo ou do plugin?). O demo usa `catalog:official`, e o padrão não aceita ponto (`catalog:vnstudio.fishing` falha no schema; testei). | Definir `catalog:<nome-do-catálogo>`, já que o plugin é a chave do mapa, e documentar. |
| B11 | `fishing-plugin/plugin.json` | `events.subscribes: ["story.*"]` sem a capacidade `events.subscribe` e sem uso no código. O plugin de referência ensina o contrário do que o SDK pede. | Remover `subscribes`, ou pedir a capacidade e usar. Validador: aviso quando há `subscribes` sem a capacidade. |
| B12 | `examples/demo-save.json` | Incoerente com o demo: `fishing_won: true` exige o caminho da pescaria, que **não** soma `days_passed`, mas o save tem `days_passed: 1`; `player_money: 30`, quando chegada (+100) mais 3 peixes (+30) dariam 130; não tem `integrity` (com a política padrão `flag`, carregaria marcado como modificado); `events_since_selection` não segue o RT §7.2 (ver M2). Além disso, `scene.current_choice` é `enum` com valores `fish`/`talk`, mas `record` grava o **id da opção** (UUID), então o `set` falharia. | Regerar o save a partir de um traço real do demo e corrigir o enum de `current_choice` (ou fazer `record` gravar um valor declarado na opção). |
| B13 | Req §3.2 | A prioridade é exibida como Baixa/Normal/Alta/Muito alta (10/100/500/900), mas a predefinição "Pode repetir" usa 50, que não é nenhum dos rótulos. | Usar 10 ou 100, ou dizer como 50 é exibido. |
| B14 | RT §2 × BS §4.2 | `narrative/bundle.json`, `locales/<lang>.json` e `plugins.json` (RT) viram `vn_content/narrative.vnb`, `locales/<lang>.vnb` e `plugins.vnb` (BS) sem tabela de correspondência. | Uma linha no RT §2 com o mapa de nomes. |
| B15 | BS §3 × §4.1 | `build_id` usa o `content_hash`, mas a pasta `<build_id>/staging` é criada na etapa 3, antes da compilação (etapa 4). | Calcular o `content_hash` na etapa 1, ou nomear a pasta depois. |
| B16 | BS §11 | Os códigos de saída não cobrem B002, B003, B005, B006, B007 e B013. | Completar o mapa (ex.: B002/B003 → 2; B005 → 1; B006/B007 → 3; B013 → 2). |
| B17 | `plugin.schema.json` | `sdk.runtime` e `sdk.editor` não são obrigatórios conforme `targets`; `default_outcome` não é obrigatório com `skippable: true` nem é conferido contra `outcomes`; a capacidade `network` ("só oficiais no v1") não é verificada. | `if/then` no schema para os dois primeiros; regra no validador para o terceiro. |
| B18 | `assets.schema.json`; DM §10.1 | O tipo `other` não aparece na tabela do DM, e nada confere o tipo contra o uso (uma `font` usada como `background` passa). | Documentar `other` e criar um aviso de tipo incompatível. |
| B19 | `project.schema.json → events`; demo | Não está dito se eventos `story.*` precisam ser declarados. O demo emite `story.met_master` sem declarar, e o validador não reclama. | Declarar como opcional, com aviso, ou exigir. |
| B20 | DM §4.3 | `sys.chapters.<cap>.completed` diz "alguma vez", mas vem do save (`history`), não do perfil. Lê-se como "em qualquer partida", como `sys.endings`. | "Já concluído nesta partida". |
| B21 | Req §8 | O histórico de versões sem Git não diz onde fica (dentro de `.vnstudio/`, que está fora do Git?), quanto espaço ocupa nem como é podado. | Uma linha com local e política de retenção. |
| B22 | Req §9; DM §9 | O algoritmo do `source_hash` não está definido (qual hash, sobre o texto bruto ou normalizado?). | `sha256` (8 primeiros bytes em hex) do texto-fonte com NFC e sem espaços nas pontas. |

---

## Pontos que não são lacunas, mas merecem uma linha nas specs

- **Dois interpretadores.** O README já lista como em aberto a troca do Preview em TypeScript pelo export Web do runtime. Os itens A2 e A3 mostram o custo concreto de manter os dois: cada função, regra de formatação e algoritmo de RNG precisa ser escrito duas vezes e coberto por vetores. Vale registrar isso como insumo para essa decisão.
- **`validate.py` é protótipo.** O BS §3.1 cita `validate.py --export` como etapa do build, mas o Studio é Tauri/TS. Uma frase dizendo que o validador do produto implementa as mesmas regras e que o `validate.py` é a referência de conformidade evita confusão.
- **`path:` com `vnplugin link` no Git.** O `plugins.json` com `source: "path:<pasta fora do projeto>"` e o lock com `link: true` vão para o Git e quebram para colaboradores. Vale sugerir que o Studio grave vínculos num arquivo local (`.vnstudio/links.json`) em vez do `plugins.json`.
- **Rollback (voltar falas) e skip/auto** não aparecem nem dentro nem fora do escopo. São recursos esperados em VN. Basta declarar no DM §13 ou no RT.
