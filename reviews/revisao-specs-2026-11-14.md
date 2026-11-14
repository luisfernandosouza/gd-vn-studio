# Segunda revisão das especificações (depois das correções)

- **Data:** 2026-11-14
- **Escopo:** `specs/` inteiro: docs 00 a 05, README, os 13 schemas, `examples/` e `tools/` (`validate.py`, `test_validate.py`).
- **Base:** a revisão anterior ([`revisao-specs-2026-11-13.md`](revisao-specs-2026-11-13.md), 56 itens) já foi aplicada. Aqui entram só **problemas novos** e **problemas criados pelas correções**. A decisão de manter o RNG reproduzível **opcional e desligado por padrão** (`settings.reproducible_rng`) foi mantida; as sugestões abaixo partem dela.
- **Método:** leitura cruzada doc × schema × exemplo × validador. Rodei `validate.py` nos exemplos (`0 erro(s), 0 aviso(s)`, com e sem `--export`), `test_validate.py` (64/64), conferi a assinatura HMAC do `demo-save.json` (confere, chave de 32 bytes zero) e montei uma cópia quebrada do demo para testar o validador (detalhes em A5).
- **Aplicada em 2026-11-14:** Luis aceitou todas as sugestões, e o Godot fixado ficou na **4.7.2** (estável mais recente; não a 3.6). Backup anterior às mudanças: `backups/specs-antes-revisao2-2026-11-14.tgz`. Ficaram em aberto: D2 (teste do export Web), D5 (escopo da galeria), D11 (operação do catálogo), D13 (nome e domínio) e os documentos E1–E15.

## Como ler

| Gravidade | Critério |
|---|---|
| **Alta** | Comportamento indefinido num fluxo comum, contradição entre documentos, risco de segurança ou de perder dados do jogador. Decidir antes de implementar. |
| **Média** | Lacuna que vai aparecer na implementação ou no uso real, com solução local. |
| **Baixa** | Texto desatualizado, referência quebrada, exemplo incoerente. Correção rápida. |

Total: **5 altas, 19 médias, 18 baixas**. A última seção, **"O que falta para fechar a documentação"**, lista as decisões que só você pode tomar e os documentos que ainda precisam ser escritos.

### Situação das correções anteriores

As correções foram aplicadas com cuidado: conferi por amostragem A1, A4, A5, A8, M1, M2, M4, M10, M22, M23, M24, B12, B13, B15 e B16, e todas estão coerentes entre doc, schema, exemplo e validador. Os problemas criados pelas correções são poucos e pontuais: a ordem da tabela de validação de escrita (M1), resíduos de "RNG salvo" (B1), o endereçamento `@<id>` em arrays sem id (M7) e a impressão digital da chave de saves, que ficou só na máquina local (A1).

## Resumo: os 5 pontos que eu resolveria primeiro

1. **A1:** a proteção contra trocar a chave de saves (B017) só funciona na máquina que fez o primeiro build. Um colaborador ou a CI gera uma chave nova sem aviso, e todos os saves dos jogadores passam a aparecer como modificados.
2. **A2:** um Editor Plugin com `project.write` pode, pelo JSON Patch do documento lógico, conceder permissões a si mesmo em `/plugins` e abrir o `access` das variáveis.
3. **A3:** o RNG reproduzível (quando ligado) ainda não é reproduzível de verdade: o fluxo do plugin fora de atividades não vai para o save, a troca de fluxo dentro de `ctx.rng` é ambígua e a semente por atividade não tem codificação de bytes definida.
4. **A4:** inteiros acima de 2^53 são erro no TypeScript e válidos no Godot, então os dois interpretadores divergem justamente onde a spec exige traço idêntico.
5. **A5:** o validador de referência não confere interpolação de texto, tipos de expressões, aridade de funções, namespace do `emit` nem sorteio dentro de variável derivada. Testei: um projeto com tudo isso passa com 0 erros.

---

## Alta

### A1. Impressão digital da chave de saves só existe na máquina local
- **Onde:** BS §8.1 ("Impressão digital"), §9.3; Req §7.1 passo 4 e §8; `project.schema.json → build.protection`.
- **Problema:** o B017 dispara quando "o projeto já teve build de release (histórico, §9.3) e a chave do cofre falta ou tem outra impressão digital". Mas o histórico de versões fica em `.vnstudio/history/` e a impressão digital em `.vnstudio/`, ambos **fora do Git** (DM §2, Req §8). Um colaborador que clona o projeto, uma máquina nova ou a CI (`vnstudio build` sem `VNSTUDIO_SAVE_KEY`) não sabem que já houve release. O build gera uma `SAVE_KEY` nova sem parar, e na atualização seguinte todos os saves e perfis dos jogadores falham na assinatura: com `flag` ligam `sys.save_modified` (que pode bloquear finais secretos), e com `reject` deixam de carregar.
- **Sugestão:** gravar a impressão digital no próprio projeto, que vai para o Git: `project.json → build.protection.save_key_id` (8 hex, não é segredo). Regra: se `save_key_id` existe e a chave do cofre ou de `VNSTUDIO_SAVE_KEY` falta ou difere, B017. Na CLI, a ausência de chave com `save_key_id` presente é erro (código de saída 2), nunca geração silenciosa. O Studio grava o campo no primeiro build de release.

### A2. Editor Plugin pode conceder permissões a si mesmo pelo documento lógico
- **Onde:** SDK §10.4.1 (documento lógico inclui `"plugins": plugins.json → plugins` e `"variables"`), §4.1 (diálogo único de permissões), §10.1 (bridge "verifica a permissão efetiva").
- **Problema:** `project.write` permite `applyEdit` com JSON Patch sobre qualquer ponteiro do documento lógico. Nada impede um `add` em `/plugins/<meu id>/grants/capabilities/-` ou um `replace` em `/variables/global/…/access/plugins_write`. O diálogo de permissões (§4.1) e as três camadas (pedido ∩ concessão ∩ aceite) são contornados. O mesmo vale para `/project/build` (ícone, nome do executável, `protection.save_tamper`) e para o código do tema. O Studio "valida contra os schemas e as regras semânticas", mas a concessão continua válida para o validador porque o pedido existe no manifesto.
- **Sugestão:** lista de ponteiros **proibidos** a plugins em `applyEdit`: `/plugins/**`, `/variables/**/access`, `/project/build/**`, `/project/runtime`, `/project/format_version`. Concessões só pelo Plugin Manager. Uma linha no SDK §10.4.1 e um caso de teste no `@vnstudio/editor-sdk/testing` (patch proibido → `VNError { code: "FORBIDDEN_PATH" }`).

### A3. RNG reproduzível (quando ligado) ainda tem buracos
- **Onde:** RT §12.2 (fluxos por atividade e por namespace), SDK §5.2 (`var rng: VNRandom`), SDK §6 (última regra), `save.schema.json → state.rng`.
- **Problema:** a decisão de deixar o RNG opcional está mantida; o que falta é fechar o modo ligado, que hoje promete um traço reproduzível que não se sustenta:
  1. **Fluxo fora de atividades não é salvo.** O plugin recebe um PCG32 semeado com SHA-256(`seed` ‖ namespace), mas `state.rng` só guarda o RNG da narrativa. Depois de carregar um save, o fluxo do plugin recomeça do zero e diverge do traço sem save.
  2. **`ctx.rng` muda de identidade?** É um único campo do contexto, mas deve entregar um fluxo durante a atividade e outro fora dela. Um plugin que guarda `ctx.rng` em `_vn_init` (padrão comum em Godot) fica com o fluxo errado na atividade. O plugin de referência só funciona porque lê `_ctx.rng` dentro de `_vn_start_activity`.
  3. **Codificação da semente.** "SHA-256(`seed` ‖ `selection_count` ‖ id do nó)" não diz se `seed` entra como 8 bytes ou como os 16 caracteres hex, nem a largura e a ordem de bytes do `selection_count`, nem se o UUID entra como texto ou 16 bytes. Sem isso, Godot e TypeScript geram sementes diferentes.
  4. **Duas atividades no mesmo nó e na mesma seleção** (um `jump` de volta para o nó plugin) recebem a mesma semente.
- **Sugestão:** (1) acrescentar `rng.streams: { <namespace>: "<state hex>" }` ao save; (2) entregar o fluxo da atividade em `handle.rng` e deixar `ctx.rng` só para fora de atividades; (3) fixar a codificação: `seed` como 8 bytes big-endian ‖ `selection_count` uint64 big-endian ‖ UUID do nó como 16 bytes ‖ contador de atividades da cena (uint32); (4) um vetor de conformidade para cada item. Com o RNG desligado nada disso se aplica, o que continua coerente com a decisão.

### A4. Inteiros: o TypeScript erra onde o Godot aceita
- **Onde:** RT §12.1 ("No TypeScript, inteiros acima de 2^53 são erro de conteúdo"); DM §6.1.1.
- **Problema:** o Godot usa int64, então `9007199254740993` é um valor válido no runtime e erro no Preview. Isso contradiz a regra de traço idêntico do RT §1 e §12. Também falta dizer o que acontece no overflow de int64 (`mul` grande), na conversão de `number` enorme ou infinito para `integer` (truncamento, DM §6.2) e na comparação `integer` × `number` perto de 2^53.
- **Sugestão:** um único intervalo normativo para os dois: inteiros em ±(2^53 − 1). Resultado fora dele é erro de conteúdo **nos dois** interpretadores (transação abortada). `number` não finito também é erro. Um vetor de conformidade para cada borda.

### A5. O validador de referência deixa passar erros que chegam ao jogador
- **Onde:** `tools/validate.py`; DM §9 (interpolação segue R005), §6.1.1, §6.2 (aviso de truncamento), §8.2 (`emit` é `story.*`); RT §9 (em release, erro de conteúdo é só registrado).
- **Problema:** como o validador é a **referência de conformidade** (DM §11, Req §13) e o release só registra erros de conteúdo, o que ele não pega vira bug silencioso no jogo. Testei numa cópia do demo; tudo abaixo passou com **0 erros e 0 avisos**:

  | Caso | O que deveria acontecer |
  |---|---|
  | Fala com `{global.nao_existe}` e `{chapter.xyz}` | R005 (o jogador veria o texto cru ou vazio) |
  | `display_name` com `{global.nope}` | R005 |
  | `set global.player_money` (integer) com `{"var": "character.alice.met"}` (boolean) | T001 (o checador só olha literais) |
  | `set` integer com `{"fn": "div", …}` | Aviso de truncamento prometido no DM §6.2, que nem tem código |
  | `{"fn": "clamp", "args": [1]}` | Erro de aridade (DM §6.1.1 fixa 3 argumentos) |
  | `emit` de `fishing.completed` e de `sys.game_ended` por uma cena | Erro: a cena forja eventos de plugin e do runtime |
  | Derivada com `{"fn": "random_int", …}` | Erro: derivada é "recalculada sob demanda", então muda a cada leitura e quebra "avaliação pura e determinística" (DM §5.3) |
  | `default_expression: "angry"` inexistente | R011 |

- **Sugestão:** novos códigos e casos em `test_validate.py`: **R019** variável de interpolação inexistente ou fora de escopo (falas, opções, `prompt`, `display_name`, créditos, finais, traduções); **T006** tipo de uma expressão (`var`, `fn`, `if`, `{result}` contra `result_schema`) incompatível com o destino; **T007** aridade ou tipo de argumento de função; **R020** `emit` fora de `story.*`; **T008** `random_int` em `derived` ou em `visible_if`/`enabled_if`/condições; **W017** resultado `number` gravado em `integer` (o aviso do DM §6.2). Ampliar R011 para `default_expression`.

---

## Média

### M1. Tabela de validação de escrita fora de ordem
- **Onde:** RT §6.2.
- **Problema:** a linha `0 | WRONG_THREAD` foi inserida entre as linhas 4 e 5, e o texto diz "nesta ordem (primeira falha interrompe)". Lida em ordem, a thread só é checada depois de existir variável e escopo, o que contradiz a intenção (thread primeiro).
- **Sugestão:** mover a linha para o topo e renumerar 1–9; "Leituras verificam 2, 4 e permissão" passa a citar os novos números (inclusive a thread).

### M2. Ordem dos eventos e chamadas ao carregar um save
- **Onde:** RT §8.3 passos 5–7, §3.1, tabela do §7.1; SDK §5.1.
- **Problema:** no load, `_vn_game_started(false)` é chamado no passo 5, mas o evento `sys.game_started` só sai no passo 7, **depois** de o nó salvo ser reexecutado (passo 6) e depois de `sys.game_loaded`. No novo jogo, `sys.game_started` sai antes de qualquer cena. Um ouvinte que prepara estado em `sys.game_started` age tarde demais no load, e a fala reexecutada já foi exibida.
- **Sugestão:** no load: restaurar estado → plugins (`_vn_game_started(false)`, migração, `_vn_load`) → `sys.game_started {new_game: false}` → `sys.game_loaded {slot}` → drenagem de eventos → restaurar o Stage e reexecutar o nó. Atualizar a tabela do §7.1.

### M3. Perfil gravado "a cada mudança" e "com debounce"
- **Onde:** RT §6.5 (linha `profile`: "Em `profile.json`, a cada mudança") × §8.5 ("com *debounce*: em cada ponto de seleção, ao fim do jogo e ao sair").
- **Sugestão:** trocar a célula do §6.5 por "Em `profile.json`, com debounce (§8.5)". Dizer também se ver um final novo grava na hora (recomendo que sim, porque o jogador pode fechar o jogo na tela de créditos).

### M4. Onde é possível salvar × autosaves que salvam em outros lugares
- **Onde:** RT §8.1 (só pontos de seleção e nós `line`/`choice`), §5.3 passo 3 (autosave antes da atividade), `project.schema.json → settings.autosave: scene_start`.
- **Problema:** o autosave de segurança acontece num nó `plugin`, que não está na lista do §8.1, e não está dito o que `state.scene.node` guarda nem o que o load faz (reinicia a atividade?). `scene_start` também não é ponto permitido: é antes de instanciar `scene.*`, no primeiro nó, ou no ponto de seleção anterior? E com `autosave: off`, uma falha no minijogo perde tudo desde o último save manual.
- **Sugestão:** acrescentar ao §8.1 "nó `plugin`, antes de iniciar a atividade (só autosave); no load, a atividade recomeça". Definir `scene_start` como "depois de instanciar `scene.*`, antes do primeiro nó". Fazer o autosave antes de atividades independente de `settings.autosave` (só `off` desliga os outros).

### M5. Pedidos de cena que somem
- **Onde:** RT §4.3 (passo 1 checa `completion` antes do pedido), SDK §5.5, `save.schema.json`.
- **Problema:** (1) se a cena que termina com `then: {scene}` satisfaz `completion.conditions`, o capítulo acaba e o pedido é descartado em silêncio. No demo, "O mestre pescador" pede "Um dia tranquilo"; se `days_passed` já chegou a 3, a sequência roteirizada some. (2) Um pedido de plugin (`scenes.request`) feito no meio da cena não vai para o save; salvar numa fala e carregar perde o pedido.
- **Sugestão:** (1) decidir a precedência. Proponho: pedido do conteúdo vem **antes** de `completion` (é uma sequência explícita do autor), e pedido de plugin depois. No mínimo, registrar `reason: "request_dropped_by_completion"` em `scheduler.evaluated` e avisar no Studio. (2) Gravar `history.pending_request` no save.

### M6. Contador de laço da `fallback_scene` não vai para o save
- **Onde:** RT §4.3 (`fallback_streak`), `save.schema.json → history`.
- **Problema:** recarregar zera o contador, e a rede de segurança de 100 repetições recomeça. É pequeno, mas o traço com e sem save diverge.
- **Sugestão:** `history.fallback_streak` (inteiro, opcional).

### M7. Endereçamento `@<id>` em arrays que não têm `id`
- **Onde:** SDK §10.4.1 ("Arrays de entidades com id (`nodes`, `options`, `cases`, `variables`, `exclusive_groups`, `endings`)").
- **Problema:** `cases` do nó `branch` não têm `id` no schema, e definições de variável usam `key`, não `id`. O endereçamento estável, criado para evitar conflito entre editores simultâneos, não funciona exatamente nesses dois.
- **Sugestão:** dar `id` (UUID) a cada `case` no `scene.schema.json` (também melhora o merge no Git) e dizer que em `variables` o segmento é `@<key>`.

### M8. Namespaces de plugin que colidem com nomes reservados
- **Onde:** `common.schema.json → Namespace`; DM §3, §7.1; SDK §2.4 e §5.7.
- **Problema:** nada impede um plugin com namespace `story` (emitiria eventos `story.*` como se fosse o conteúdo), `sys` (eventos e variáveis do runtime), `vn` (ações de input `vn_*` do runtime e prefixo `VN` de classes) ou `global`, `chapter`, `scene`, `character`, `plugin`.
- **Sugestão:** lista de namespaces reservados no schema (`not: enum [...]`) e no catálogo.

### M9. Variáveis de plugin: acesso entre plugins e campos que não fazem sentido
- **Onde:** DM §4.6; `plugin.schema.json → variables` (usa `VariableDefinition` inteira) e `VariablePattern` (aceita `plugin.*`).
- **Problema:** não está dito se o plugin A pode ler `plugin.b.*`. O padrão de pedido aceita, mas quem concede? O campo `access` das variáveis de plugin não tem quem o edite (o autor do projeto não edita a definição). Além disso, uma variável de plugin com `derived` que lê `global.player_money` expõe uma variável do projeto sem passar por permissão nenhuma. `characters` e `renamed_from` também não fazem sentido ali.
- **Sugestão:** decidir que variáveis de outro plugin são legíveis só via `dependencies` (dependência declarada = leitura liberada) e nunca graváveis. Em `plugin.json`, proibir `access` e `characters`, e permitir `derived` só sobre variáveis do próprio namespace (novo erro).

### M10. `{result}` em release: tipo errado, caminho com ponto
- **Onde:** RT §5.3 passo 6, §7.2 (payload só é validado em debug); `common.schema.json → ValueExpr.result` (`pattern` aceita `.`).
- **Problema:** se o plugin devolver `score: "120"` (string) num jogo de release, o efeito `add` falha com `TYPE_MISMATCH`, que é erro de conteúdo: a transação inteira de `on_result.effects` é abortada e o jogador perde moedas sem nenhum aviso. Também não está definido o que `{"result": "a.b"}` significa (campo aninhado? o validador só olha o primeiro segmento).
- **Sugestão:** no runtime, campo com tipo diferente do esperado vale como ausente (usa `default` ou o padrão do tipo) e registra aviso, em vez de abortar tudo. Definir `a.b` como acesso aninhado e conferir o caminho inteiro contra o `result_schema` (T005).

### M11. Formatação numérica e JSON canônico ainda subespecificados
- **Onde:** DM §6.1.1 (`concat`), DM §9 (interpolação), RT §12.1, BS §5.1 e §8.3 (HMAC sobre JSON canônico), SDK §5.7 (`ctx.i18n.text` com `args`).
- **Problema:** (1) `concat` de `1/3` dá `0.3333333333333333` ou outra coisa? `2.0` vira `2` ou `2.0`? (2) Interpolação "até 2 casas decimais": arredonda como (meio-para-longe-do-zero, como `round`, ou meio-para-par)? (3) O HMAC do save é sobre JSON canônico RFC 8785, mas `JSON.stringify` do Godot não segue a formatação de números da RFC 8785; o runtime precisa de um serializador próprio, senão a assinatura do Preview, a do runtime e a das ferramentas divergem para qualquer `number`. (4) `args` de `ctx.i18n.text` seguem a tabela de formatação por idioma ou viram texto cru? Aceitam `{{`?
- **Sugestão:** (1) `concat` usa a menor representação que preserva o valor, como no JavaScript, e inteiros sem `.0`; (2) interpolação arredonda meio-para-longe-do-zero, igual a `round`; (3) dizer no BS §5.1 que runtime e Studio implementam o JCS próprio e incluir vetores de assinatura (o `demo-save.json` já serve de primeiro caso); (4) `args` seguem a mesma formatação e o mesmo escape da interpolação do projeto.

### M12. Valor de `enum` aparece cru para o jogador
- **Onde:** DM §9 ("enums pelo valor").
- **Problema:** interpolar `{scene.current_choice}` mostra `icecream` em qualquer idioma. Não há como traduzir.
- **Sugestão:** `constraints.labels` opcional (valor → texto), traduzível pelo caminho `variable/<id qualificado>/value/<valor>`; sem rótulo, mostra o valor.

### M13. Aliases de `renamed_from` não valem para o perfil
- **Onde:** RT §8.3 passo 3 e §8.4 (só saves); DM §12.
- **Problema:** renomear uma variável `profile` (ex.: `global.endings_seen`) depois do lançamento perde o valor no perfil, que é justamente o que sobrevive entre partidas.
- **Sugestão:** aplicar os aliases também ao ler `profile.json`, com a mesma tabela do §8.4.

### M14. Assets e cenas citados por plugins ficam fora da validação e do build
- **Onde:** BS §6.1 (`always_include` manual), SDK §4.4 (`format: vn-variable`), DM §10.1 (tipo `other`).
- **Problema:** um parâmetro de atividade ou campo de `config` que recebe um ID de asset não é validado (R004) nem entra automaticamente no build. O autor precisa lembrar de marcar `always_include`; se esquecer, o jogo quebra só em release (B008 avisa, mas como "não usado").
- **Sugestão:** estender o mecanismo do `vn-variable`: `format: "vn-asset"` (com `vn-asset-type`), `"vn-scene"` e `"vn-character"`. O Studio mostra seletor, o validador confere R004/R006/R010, e o build inclui o asset sem `always_include`.

### M15. Build: `version` opcional e `android` aceito
- **Onde:** `project.schema.json` (`version` não é obrigatório; `build.platforms` aceita `android`); BS §4.3, §7.1, §7.2, §9.1; Req §7.1 ("Android (futuro)").
- **Problema:** o build usa `version` no nome dos arquivos, na pasta de saída e em `application/config/version`, mas um projeto sem `version` passa no validador. `android` passa no schema, mas o BS não diz o que o build faz com ele.
- **Sugestão:** regra de exportação (como P013/W013): `version` obrigatório no `--export`. Para Android, erro B001 explícito no v1 ("ainda não suportado") ou retirar do enum até existir.

### M16. Falha de pré-requisito de uma plataforma interrompe todas?
- **Onde:** BS §3 ("etapas 1 a 7 são comuns e, se falharem, interrompem todas") × §3.1 passo 2 (B001 por plataforma).
- **Problema:** faltar o requisito do macOS impede gerar o Windows? Pela frase, sim; pela intenção de "uma falha interrompe o build daquela plataforma", não.
- **Sugestão:** B001 e B012 removem só a plataforma afetada; o relatório mostra as demais.

### M17. `compatibility` obrigatório, mas vazio é válido
- **Onde:** `plugin.schema.json → compatibility`; SDK §3 e §11.1.
- **Problema:** `"compatibility": {}` passa no schema. O Plugin Manager "recusa instalar fora das faixas", mas não diz o que faz com faixa ausente.
- **Sugestão:** `compatibility.runtime` obrigatório; `godot` derivado do runtime se ausente; `studio` e `data_model` opcionais com o significado "qualquer".

### M18. Builds de debug e a chave de saves
- **Onde:** BS §11.1 (`save_tamper` forçado para `flag`), §8.3 ("Saves de builds de debug também caem aqui"), §4.4.
- **Problema:** não está dito se o build de debug leva a `SAVE_KEY`. Se leva, um build de teste enviado a testadores vaza a chave sem tokens binários protegendo (logs detalhados, `.vnb` sem cifra). Se não leva, como ele assina e como o release trata os saves dos testadores?
- **Sugestão:** debug **não** leva a `SAVE_KEY` real; assina com uma chave fixa de debug; release trata essas assinaturas como inválidas (cai em `flag`). Uma linha no §11.1.

### M19. Acessibilidade não aparece em nenhum documento
- **Onde:** Req, `theme.schema.json`, `save.schema.json → PlayerSettings`.
- **Problema:** não há requisito de tamanho de fonte ajustável, alto contraste, legendas para voz, navegação só por teclado/gamepad nos menus, desligar animação de texto ou leitor de tela. Para VN são recursos esperados e alguns precisam de campos no tema e em `PlayerSettings`.
- **Sugestão:** decidir o mínimo do v1 (ver Decisão D6) e acrescentar os campos correspondentes.

---

## Baixa

| # | Onde | Problema | Sugestão |
|---|---|---|---|
| B1 | RT §4.5 ("com RNG salvo"); `chapter.schema.json → SchedulerSettings.tie_breaker` ("com RNG semeado e salvo no save") | Resíduos de antes do RNG opcional. | "Reproduzível só com `settings.reproducible_rng`". |
| B2 | RT §5.2 (`sys.choice_made { scene, node, option }`) × §7.1 (`{ scene, node, option, value }`) | Payload diferente nos dois lugares. | Usar a versão com `value` nos dois. |
| B3 | DM §5.1 (`contains` só em `string`) × Req §3.1 (frase "contém" para string/enum) | Enum com `contains` não faz sentido. | Tirar enum da coluna no Req. |
| B4 | DM §8.2 (`show`) | Primeira aparição sem `expression`: usa `default_expression`? Não está escrito. | "Ausente: expressão atual, ou `default_expression` na primeira vez". |
| B5 | `validate.py` | `character.voice.blip` não é conferido (R004); `project.chapters` não é conferido (ids inexistentes, capítulos faltando, `start_chapter` fora da lista). | Acrescentar as duas checagens. |
| B6 | `plugin.schema.json → plugin_locales`; exemplo do fishing | Não existe caminho `config/<prop>/description`, e o exemplo tem `description` em `rare_fish_chance` que não pode ser traduzida. | Acrescentar o caminho (e `activity/<id>/description`). |
| B7 | `demo-project/plugin-lock.json` e exemplo do BS §9.2 | O `integrity` de exemplo (`47DEQpj8…FU=`) é o SHA-256 de um arquivo **vazio**. | Marcar como valor ilustrativo, ou gerar o pacote do exemplo e usar o hash real. |
| B8 | `demo-save.json`; RT §8.4 | O save não tem `project.content_hash`, e a spec não diz o que fazer quando ele falta. | `content_hash` obrigatório em saves de release; ausente = tratar como "jogo atualizado". |
| B9 | BS §5.2 | Só a versão do formato diz little-endian; o tamanho (uint32) não. | "Todos os inteiros do cabeçalho são little-endian". |
| B10 | BS §5.2 ("B-runtime") | Código inexistente. As mensagens que o **jogador** vê (conteúdo corrompido, save modificado, save incompatível) não têm catálogo. | Criar a série de mensagens do runtime (ex.: `G001`…) com texto por idioma do jogo. |
| B11 | BS §8.2 | Só `narrative.vnb` é conferido contra `CONTENT_HASH`; `locales/*.vnb` e `plugins.vnb` só contra o próprio cabeçalho. Trocar uma tradução inteira é possível sem mexer no jogo. | `build_config.gd` com o hash de cada `.vnb`. |
| B12 | DM §9.1; `validate.py` | Parâmetros das marcas não são validados (`[color=azul]`, `[pause=abc]` passam), e não está dito se `display_name`, `prompt` e descrições de final aceitam marcação. | Validar o formato do parâmetro em R018 e listar onde a marcação vale. |
| B13 | DM §3 (asset `^[a-z][a-z0-9_./-]*$`) × `common.schema.json → AssetRef` (`{0,127}`) | Limite de tamanho só no schema. | Igualar. |
| B14 | `locale.schema.json → source_hash` | Sem `pattern`, embora o DM §9 defina 16 hex. | `^[0-9a-f]{16}$`. |
| B15 | Req §9 (coluna `status`) × `locale.schema.json → status` (`draft`/`reviewed`) | A planilha mostra "desatualizada", que não existe no schema. | Dizer que "desatualizada" é calculada pelo `source_hash`, não gravada. |
| B16 | RT §11 (`preview.start({…, seed?})`) | Com `reproducible_rng` desligado, o que `seed` faz? | "Ignorado sem `reproducible_rng`" ou "semeia o RNG comum" (útil para reproduzir bugs no Preview). |
| B17 | `fishing_game.gd` / `.tscn` | Posições fixas para 1080p (`540.0`, `offset_left = 948`), contra a recomendação do SDK §5.7 de usar âncoras e a resolução do projeto. | Usar âncoras; é o plugin de referência. |
| B18 | DM §6.2 × RT §5.2 | Na escolha, `record` faz parte da mesma transação dos `effects` da opção? Se `record` falhar por `max_length`, o que acontece? | `record` entra na mesma transação; falha por restrição desfaz tudo e segue o `goto`. |

---

## O que falta para fechar a documentação

### Decisões que só você pode tomar

Cada linha traz minha recomendação; nenhuma bloqueia as outras.

| # | Decisão | Por que importa | Recomendação |
|---|---|---|---|
| D1 | **Versão exata do Godot** que o runtime v1 fixa | As specs citam 4.3 em todo lugar (presets, `script_export_mode`, exemplos), e já existem versões mais novas. Os nomes de opções do export mudam entre versões (BS §15 item 2). | Fixar a estável mais recente no momento do congelamento e revisar BS §7 contra ela. |
| D2 | **Dois interpretadores ou um** (Preview em TypeScript × export Web do runtime) | A3, A4 e M11 mostram o custo de manter o TypeScript idêntico ao GDScript: aritmética, formatação, JCS, RNG, vetores. | Fazer um teste rápido do export Web dentro do Studio; se o tempo de recarga for aceitável, eliminar o interpretador TS. |
| D3 | **Impressão digital da chave de saves no projeto** (A1) | Sem isso, colaboração e CI quebram saves de jogadores. | Sim, `build.protection.save_key_id`. |
| D4 | **Precedência entre pedido de cena e fim de capítulo** (M5) | Muda o comportamento de sequências roteirizadas. | Pedido do conteúdo antes de `completion`. |
| D5 | **Escopo da galeria** | O tema tem "galeria", mas o modelo só registra finais. CGs, músicas e cenas para rever exigem campos novos (perfil e projeto). | Decidir se o v1 tem só finais ou também imagens desbloqueáveis. |
| D6 | **Acessibilidade no v1** (M19) | Precisa de campos no tema e nas preferências. | Mínimo: tamanho de texto, velocidade, desligar animação, legendas de voz, menus por teclado/gamepad. |
| D7 | **Android no v1** (M15) | O schema aceita, o BS diz "futuro". | Fora do v1, retirar do enum. |
| D8 | **Bibliotecas do Studio** (README: React Flow, Zustand + Immer, Ajv, CodeMirror/Monaco) | Afeta o Editor SDK (tipos expostos) e o validador TS. | Aceitar a proposta do README. |
| D9 | **Assinatura de pacotes** no v1 ou v2 | Hoje só hash + HTTPS. | Manter no v2, mas reservar o campo `signature` no catálogo agora. |
| D10 | **Produto (ADD §13.7)**: distribuição do Studio (instalador, atualização automática, assinatura do próprio Studio), plataformas do Studio, **licença do runtime embutido nos jogos exportados** e do SDK, licença dos plugins oficiais, propriedade dos projetos, idiomas do Studio | Sem a licença do runtime, nenhum jogo pode ser distribuído com segurança jurídica. | Runtime e SDK sob licença permissiva (MIT, como o Godot); Studio em Windows, macOS e Linux; Studio em pt-BR e en no v1. |
| D11 | **Quem opera o catálogo** e com que prazo de revisão | SDK §13.5 promete 5 e 2 dias úteis. | Confirmar a equipe e o repositório antes de abrir para externos. |
| D12 | **Telemetria e relatório de travamentos** (Studio e jogos) | Não aparece em nenhum documento; tem impacto de privacidade. | Nenhuma no v1, ou só opt-in no Studio. |
| D13 | **Nome e domínio** (`schemas.vnstudio.dev` é provisório, publisher `vnstudio`) | Os `$id` dos schemas ficam congelados no `format_version` 1.0.0. | Definir antes do congelamento. |

### Documentos e artefatos que ainda precisam ser escritos

| # | Documento | Hoje | Conteúdo mínimo |
|---|---|---|---|
| E1 | `build-manifest.schema.json` | Pendência do BS §15 | Schema do exemplo do BS §9.2 |
| E2 | **Protocolo do Preview** (JSON-RPC) | RT §11 só lista nomes | Parâmetros, resultados, erros e payload de cada método e notificação, com schema |
| E3 | **Vetores de conformidade** | Citados no RT §12, não existem | Formato do caso (`bundle`, estado, entradas, seed → traço) e um conjunto inicial cobrindo DM §6.1.1, RT §4, §12.1 e, com RNG ligado, §12.2 |
| E4 | **Tipos do Editor SDK** (`.d.ts`) | SDK §10.3 cita tipos não definidos | `ProjectEdit`, `Scene`, `SceneSummary`, `VariableInfo`, `AssetInfo`, `NodeInspector`, `ValidationIssue`, payload de cada `StudioEventName`, códigos de `VNError` |
| E5 | **Referência do Runtime SDK** | SDK §5 em trechos | Todas as classes `VN*`, lista fechada de códigos de erro (`StringName`), `VNPluginTest`, `VNSandbox` |
| E6 | **Catálogo de mensagens** | Req §6 tem 17 exemplos | Todas as mensagens R/T/P/W/B em pt-BR e en, mais as mensagens que o jogador vê (B10) |
| E7 | **Schema do catálogo** e de `publishers/<publisher>.json`; formato `.vnkey` | Descritos em prosa (SDK §13.2, BS §8.1) | Schemas e o algoritmo de derivação de chave do `.vnkey` (ex.: Argon2id + AES-GCM) |
| E8 | **Presets de tema e valores padrão** | `classic`, `modern`, `minimal` só nomeados | Os valores de cada preset; padrões de `settings` (resolução, `text_speed`, `autosave`) e de `PlayerSettings` |
| E9 | **Especificação de interface do Studio** | Req não desenha telas, de propósito | Fluxos e wireframes das telas principais (editor de cena, Condition Editor, Plugin Manager, assistente de exportação, Theme Editor) |
| E10 | **Guia de templates com criptografia** | Pendência do BS §15 | Passo a passo por sistema operacional |
| E11 | **Workflow de CI de exemplo** | Prometido no BS §11 | `.github/workflows` com `vnstudio build` e a chave de saves como segredo |
| E12 | **Política de revisão de plugins** | Checklist no SDK §13.4 | Checklist formal, critérios de recusa, processo de revogação e contato de segurança |
| E13 | **ADD v0.2** | O ADD v0.1 continua desatualizado; os desvios vivem no README | Incorporar os 6 desvios e as decisões de 2026-11-12 a 14, para que exista um documento de arquitetura vigente |
| E14 | **Glossário** | Termos variam ("nó" nas specs, "passo" no Studio; "atividade", "minijogo", "minigame") | Termo técnico × termo exibido ao autor, em pt-BR e en |
| E15 | **Plano de testes** | Só vetores e testes de plugin | Testes do Studio, do runtime por plataforma e do build (incluindo Web), com a matriz de plataformas |

### Perguntas abertas menores

Estas eu resolveria com o padrão sugerido nos itens acima, sem precisar de reunião: M3 (gravar final na hora), M6, M7, M8, M10, M11, M12, M13, M16, M17, M18 e todas as Baixas. Se você concordar, uma próxima rodada pode aplicar tudo de uma vez, como foi feito com a revisão anterior.
