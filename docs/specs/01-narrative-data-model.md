# Narrative Data Model — Especificação v1.0.0-draft

- **Status:** rascunho para revisão (proposto para congelamento como `format_version` 1.0.0)
- **Base:** Architecture Design Document v0.1, seções 4, 6.4–6.5, 13.1–13.2 e 16
- **Schemas:** [`schemas/`](schemas/) (JSON Schema draft 2020-12)
- **Exemplo completo:** [`examples/demo-project/`](examples/demo-project/)
- **Validador de referência:** [`tools/validate.py`](tools/validate.py)

Este documento define **como o conteúdo narrativo é armazenado**: projeto, capítulos, cenas, nós de diálogo, escolhas, variáveis, condições, efeitos, prioridades e textos traduzíveis. Ele não define como o conteúdo é executado (isso é a Narrative Runtime Specification) nem os contratos de plugins (Plugin SDK Specification), mas reserva os pontos de contato com ambos.

As palavras **DEVE**, **NÃO DEVE**, **DEVERIA** e **PODE** seguem o sentido da RFC 2119.

---

## 1. Princípios de modelagem

1. **Dados, não código.** Todo conteúdo narrativo é JSON declarativo. Não existe linguagem de script embutida nas cenas; condições e expressões são árvores JSON que o Studio edita visualmente e o runtime interpreta.
2. **Um arquivo por entidade.** Cada cena, capítulo e personagem fica em seu próprio arquivo, para que roteiristas diferentes editem em paralelo com poucos conflitos no Git.
3. **IDs estáveis.** Todo objeto referenciável tem um `id` escrito uma vez e nunca regenerado. Traduções, saves e histórico dependem disso.
4. **Referências totalmente qualificadas.** Toda referência a variável usa o ID completo (`global.player_money`, nunca `player_money`). O Studio PODE exibir nomes curtos, mas grava o ID completo. Isso remove ambiguidade entre escopos e entre projeto e plugins.
5. **Validação em duas camadas.** O JSON Schema garante a forma; o Content Validator garante o significado (seção 11). Um projeto só é exportável sem erros nas duas.

## 2. Estrutura do projeto em disco

```text
meu-projeto/
├── project.json            # raiz: metadados, idiomas, capítulo inicial
├── variables.json          # variáveis globais e modelos de variáveis de personagem
├── assets.json             # registro de assets (ID → arquivo)
├── plugins.json            # plugins usados, permissões concedidas, configuração
├── plugin-lock.json        # gerado: versões e hashes fixados
├── plugins/                # minijogos embutidos neste jogo (opcional; spec 09 §3.2)
├── vendor/plugins/         # pacotes .vnplugin guardados no repositório (opcional; spec 09 §3.3)
├── theme.json              # estilos: fontes, cores, caixa de diálogo, botões
├── ui/                     # telas: título, pausa, configurações… (UI Spec)
│   └── title.json
├── sets/                   # cenários compostos com objetos clicáveis (UI Spec §5)
│   └── beach_title.json
├── characters/
│   └── alice.json
├── chapters/
│   ├── ch01.json
│   └── ch02.json
├── scenes/
│   ├── ch01/
│   │   ├── scene_beach.json
│   │   └── scene_fishing_master.json
│   └── _global/            # cenas com chapter: null
├── locales/
│   └── en/
│       └── scene_beach.json
├── assets/                 # arquivos binários (imagens, áudio…)
└── .vnstudio/              # cache e estado do editor; fora do Git
```

| Arquivo | Schema | Quem escreve |
|---|---|---|
| `project.json` | `project.schema.json` | Studio (Project Manager) |
| `variables.json` | `variables.schema.json` | Studio (Variable Manager) |
| `assets.json` | `assets.schema.json` | Studio (Asset Manager) |
| `characters/*.json` | `character.schema.json` | Studio (Character Manager) |
| `chapters/*.json` | `chapter.schema.json` | Studio (Narrative Editor) |
| `scenes/**/*.json` | `scene.schema.json` | Studio (Scene/Dialogue Editor) |
| `locales/<lang>/*.json` | `locale.schema.json` | Studio ou ferramenta de tradução |
| `plugins.json` | `plugins.schema.json` | Studio (Plugin Manager) |
| `plugin-lock.json` | `plugin-lock.schema.json` | Dependency Resolver (gerado) |
| `theme.json` | `theme.schema.json` | Studio (Menu Editor → Estilos) |
| `ui/*.json` | `ui-screen.schema.json` | Studio (Menu Editor) |
| `sets/*.json` | `set.schema.json` | Studio (Menu Editor / Scene Editor) |

A pasta de uma cena dentro de `scenes/` é só organização; o vínculo real é o campo `chapter`. Arquivos JSON DEVEM ser gravados em UTF-8, com indentação de 2 espaços e chaves em ordem estável, para diffs legíveis.

## 3. Identificadores

O formato é **misto** (decidido em 2026-11-12): entidades que o autor cria e renomeia no Studio usam UUID, e nomes que outras pessoas escrevem ou leem (autores de plugin, tradutores, quem lê um save ou um erro) continuam legíveis.

| Tipo | Formato | Exemplo |
|---|---|---|
| **Entidade** (`EntityId`): cena, capítulo, personagem, nó, opção de escolha, caso de `branch` | UUID em minúsculas; o Studio gera UUIDv7 | `019a7a00-1388-7f6b-b667-94bbd1305982` |
| **Nome legível** (`Id`): `key` de variável, `key` de personagem, expressão, grupo de exclusividade, final, outcome, ID do projeto | `^[a-z][a-z0-9_]{0,63}$` | `player_money`, `alice`, `happy`, `evening_event` |
| Namespace de plugin | `^[a-z][a-z0-9_]{1,31}$`, exceto os reservados abaixo | `fishing` |
| ID de plugin | `<publisher>.<nome>` | `vnstudio.fishing` |
| Asset | `^[a-z][a-z0-9_./-]{0,127}$` | `bg/beach_day` |
| Evento | `<namespace>.<nome>` | `fishing.completed`, `story.met_master` |

Por que misto:

- **Entidades em UUID.** O autor só vê e edita o `title` (ou `name`); o ID nunca aparece. Renomear, usar acento ou repetir um título não quebra nada. Como cada nó e cada opção nasce com um UUID, dois roteiristas que inserem passos na mesma cena ao mesmo tempo não colidem no merge. UUIDv7 é ordenado pelo momento da criação, então o desempate final do Scheduler por `id` equivale a "criada primeiro".
- **Nomes legíveis onde há contrato com terceiros.** Manifestos de plugin pedem acesso a `global.player_money` sem conhecer o projeto; condições, saves, interpolação (`{character.alice.affection}`) e mensagens de erro precisam ser legíveis.
- **Personagem tem os dois.** `id` (UUID) identifica o personagem nas cenas (`speaker`, `show`); `key` (legível, gerada do nome na criação e estável) forma as variáveis `character.<key>.<variável>`.

**Namespaces reservados.** Nenhum plugin pode usar `sys`, `story`, `vn`, `global`, `character`, `chapter`, `scene` nem `plugin` como namespace: eles colidiriam com eventos do runtime e do conteúdo, com escopos de variável, com as ações de input `vn_*` e com o prefixo `VN` do SDK. O schema do manifesto recusa, e o catálogo também.

Unicidade: UUIDs são únicos no projeto inteiro; `key` de personagem é única no projeto. Opções de escolha e hotspots de `interact` também têm UUID e seguem a mesma regra. O nome do arquivo de uma cena, capítulo ou personagem é derivado do título e é só organização: o Studio PODE renomeá-lo, e o vínculo é sempre o `id` interno.

O **caminho de texto** de uma fala é `<cena>/<nó>` e o de uma opção é `<cena>/<nó>/<opção>`, com os UUIDs. É a chave usada em traduções e em "texto já lido". Ferramentas de tradução exibem o título da cena e o texto-fonte ao lado da chave.

> **Nota sobre os exemplos.** Para facilitar a leitura, os trechos deste documento e das outras specs escrevem entidades com nomes legíveis (`scene_beach`, `ch01`, `n4`). Nos arquivos reais, e em `examples/demo-project/`, esses campos são UUIDs.

## 4. Variáveis

### 4.1. Escopos

| Escopo | ID qualificado | Onde é declarada | Tempo de vida |
|---|---|---|---|
| Global | `global.<key>` | `variables.json → global` | Jogo inteiro |
| Personagem | `character.<key do personagem>.<key>` | `variables.json → character` (modelo instanciado por personagem) | Jogo inteiro |
| Capítulo | `chapter.<key>` | `chapters/<id>.json → variables` | Do início ao fim do capítulo ativo; reiniciada a cada entrada |
| Cena | `scene.<key>` | `scenes/…/<id>.json → variables` | Uma execução da cena; reiniciada a cada início |
| Plugin | `plugin.<namespace>.<key>` | `plugin.json → variables` | Jogo inteiro |
| Sistema | `sys.…` | Runtime (fixas) | Somente leitura |

`chapter.<key>` sempre se refere ao capítulo **ativo**. Referenciá-la num lugar avaliado fora daquele capítulo é erro de validação. Se um valor do capítulo precisa sobreviver a ele, o autor grava numa variável global.

`scene.<key>` só existe enquanto a cena roda. Por isso **não pode** aparecer nas condições de agendamento da própria cena (elas são avaliadas antes de a cena começar).

### 4.2. Definição

```json
{
  "key": "player_money",
  "name": "Dinheiro",
  "type": "integer",
  "default": 0,
  "persistence": "save",
  "constraints": { "min": 0, "max": 99999, "on_overflow": "reject" },
  "access": { "plugins_read": "granted", "plugins_write": "granted" }
}
```

| Campo | Obrigatório | Significado |
|---|---|---|
| `key` | sim | Nome local; o ID qualificado vem do escopo |
| `name`, `description`, `tags` | não | Exibição no Studio |
| `type` | sim | `boolean`, `integer`, `number`, `string`, `enum` |
| `default` | não | Padrão do tipo: `false`, `0`, `0.0`, `""`, primeiro valor do enum |
| `persistence` | não | `save` (padrão), `profile`, `session` (seção 4.4) |
| `constraints` | `enum` exige `values` | `min`, `max`, `on_overflow` (`clamp` padrão / `reject`), `max_length`, `values`, `labels` (só `enum`: valor → texto exibido ao jogador, seção 9) |
| `derived` | não | Expressão de valor; torna a variável somente leitura (seção 4.5) |
| `access` | não | O que o **projeto** aceita expor a plugins (seção 4.6) |
| `characters` | não | Só para modelos de personagem: restringe a quais personagens se aplica |
| `renamed_from` | não | Chaves anteriores, gravadas pelo comando "Renomear em todo o projeto" (seção 12) |

Personagens PODEM sobrescrever o `default` de uma variável de personagem com `initial_values` no próprio arquivo (`"initial_values": { "affection": 10 }`).

Tipos de coleção (listas, conjuntos, inventário) **ficam fora do v1** de propósito. Inventário é responsabilidade de plugin (ADD §6.2, serviço Inventory), e flags múltiplas podem ser modeladas como booleanas. Isso mantém o Condition Editor simples. Reavaliar no v1.1.

### 4.3. Variáveis de sistema (`sys.`)

Somente leitura, mantidas pelo runtime. Lista mínima do v1:

| Variável | Tipo | Significado |
|---|---|---|
| `sys.chapter.id` | string | Capítulo ativo |
| `sys.scene.id` | string | Cena ativa (vazia em ponto de seleção) |
| `sys.selection_count` | integer | Pontos de seleção desde o início do jogo |
| `sys.scenes.<cena>.plays` | integer | Vezes que a cena foi **concluída** (`<cena>` = UUID; o Condition Editor escolhe a cena pelo título) |
| `sys.scenes.<cena>.last_selection` | integer | `selection_count` da última seleção (-1 se nunca) |
| `sys.chapters.<cap>.completed` | boolean | Capítulo já concluído nesta partida (vem do save, não do perfil) |
| `sys.endings.<final>` | boolean | Final já visto (vem do perfil) |
| `sys.locale` | string | Idioma atual |
| `sys.ui.has_save`, `sys.ui.in_game`, `sys.ui.activity` | boolean | Estado da interface: existe save, há partida em andamento, minijogo rodando (UI Spec §3.2) |
| `sys.ui.platform` | string | `windows`, `linux`, `macos` ou `web` |
| `sys.ui.has_minigames` | boolean | Existe ao menos uma atividade de plugin com `free_play` (UI Spec §3.2) |
| `sys.ui.last_activity_outcome` | string | Resultado da última atividade jogada no modo livre: o `outcome` declarado, `failed`, `cancelled` ou vazio (Plugin SDK §6.1) |
| `sys.ui.last_record_rank` | integer | Posição do último recorde enviado no modo livre (0 se não entrou no quadro) |
| `sys.ui.content_filter` | boolean | Modo stream ligado (§10.4). Só em telas e sets: cenas, capítulos e derivadas não podem ler (R022) |
| `sys.ui.has_gallery` | boolean | O projeto tem galeria (`project.json → gallery`, §10.5) |
| `sys.ui.gallery_endings`, `sys.ui.gallery_images`, `sys.ui.gallery_music` | boolean | A seção está em `project.json → gallery.sections` (§10.5) |
| `sys.ui.content_filter_available` | boolean | O jogador pode ligar e desligar o modo stream: o projeto tem conteúdo marcado e o build não é a edição censurada (§10.4) |
| `sys.save_modified` | boolean | O save ou o perfil carregado tem assinatura inválida e a política é `flag` (Build System §8.3); `persistence: session` |

Isso responde à necessidade de "cena X já aconteceu?" sem criar variáveis manuais: `{"variable": "sys.scenes.scene_beach.plays", "operator": "greater_than", "value": 0}`.

### 4.4. Persistência

| Valor | Vai para o save? | Sobrevive a novo jogo? | Uso típico |
|---|---|---|---|
| `save` (padrão) | sim | não | Estado da história |
| `profile` | não (vai para `profile.json`) | sim | Galeria, finais vistos, NG+ |
| `session` | não | não | Valores temporários; voltam ao padrão ao carregar |

Variáveis de cena e de capítulo com `persistence: save` são salvas junto com o snapshot quando o save acontece no meio da cena/capítulo (ver Runtime Spec §8). `profile` só é permitido em variáveis globais e de plugin (R017).

### 4.5. Variáveis derivadas

Uma variável com `derived` é calculada a partir de outras e não pode ser escrita:

```json
{ "key": "is_rich", "type": "boolean",
  "derived": { "if": [{ "variable": "global.player_money", "operator": "greater_than_or_equal", "value": 1000 }],
               "then": true, "else": false } }
```

Regras: o grafo de dependência entre derivadas DEVE ser acíclico (erro de validação); o runtime recalcula sob demanda; derivadas nunca entram no save; o tipo resultante DEVE bater com `type`.

### 4.6. Acesso por plugins

O campo `access` diz o que o **projeto** está disposto a expor:

- `plugins_read`: `none` (padrão) / `granted` (só plugins com concessão explícita em `plugins.json`) / `all` (qualquer plugin habilitado pode ler).
- `plugins_write`: `none` (padrão) / `granted`.

A permissão efetiva de um plugin sobre uma variável do projeto é a interseção de três coisas: o que o plugin **pede** (`plugin.json`), o que o projeto **concede** (`plugins.json`) e o que a variável **aceita** (`access`). O manifesto sozinho nunca concede nada (ADD §6.4).

Variáveis do próprio namespace do plugin (`plugin.<ns>.*`) são sempre legíveis e graváveis pelo dono e **somente legíveis** pelo projeto: o autor as usa em condições e textos, mas um efeito de cena que as altere é erro T002. O Studio as mostra como "do plugin *{nome}*" (Requisitos de autoria §5).

**Entre plugins.** Um plugin lê as variáveis de outro plugin só se o declarar em `dependencies` (ou `optional_dependencies`) e pedir a leitura em `variable_permissions.read`; a dependência declarada vale como concessão, sem diálogo. Variáveis de outro plugin nunca são graváveis (P017).

**Definição de variáveis de plugin.** No `plugin.json`, as definições não aceitam `access` nem `characters` (não há quem os edite), e `derived` só pode ler variáveis do próprio namespace, para não expor variáveis do projeto sem permissão (P017).

## 5. Condições

Uma condição é uma árvore JSON. Folhas são comparações; nós internos são `all`, `any`, `not`. Em qualquer campo `conditions`, uma **lista** significa "todas verdadeiras" (lista vazia é verdadeira), o que mantém o formato do exemplo do ADD.

```json
{
  "all": [
    { "variable": "global.fishing_won", "operator": "equals", "value": true },
    { "any": [
      { "variable": "character.alice.affection", "operator": "greater_than", "value": 20 },
      { "variable": "global.is_rich", "operator": "equals", "value": true }
    ] },
    { "not": { "variable": "sys.scenes.scene_fishing_master.plays", "operator": "greater_than", "value": 0 } }
  ]
}
```

### 5.1. Operadores

| Operador | Tipos aceitos | Observação |
|---|---|---|
| `equals`, `not_equals` | todos | Mesmo tipo; `integer` e `number` se comparam pelo valor numérico (`1` = `1.0`). Literal não inteiro contra variável `integer` é T001 |
| `greater_than`, `greater_than_or_equal`, `less_than`, `less_than_or_equal` | integer, number | |
| `in`, `not_in` | string, enum, integer | `value` é lista |
| `contains` | string | Substring |
| `is_default` | todos | Sem `value`; verdadeiro se o valor **atual** é igual ao padrão efetivo (`initial_values` do personagem, senão `default`). Uma variável que mudou e voltou ao padrão é `is_default` |

`value` PODE ser `{ "var": "global.outra" }` para comparar duas variáveis. As duas DEVEM ser do mesmo tipo (`integer` e `number` contam como o mesmo); senão, T001.

### 5.2. Condição de evento

`{ "event_since_last_selection": "fishing.completed" }` é verdadeira se o evento foi emitido desde o último ponto de seleção. Vale para eventos `story.*` e de plugins; eventos `sys.*` não são registrados (Runtime Spec §7.2), e para eles use as variáveis `sys.*`. É a forma de uma cena reagir a um minigame ou a um evento de plugin sem que o plugin controle a história (ADD §6.8).

### 5.3. Semântica de avaliação

- Avaliação é pura (sem efeitos colaterais) e determinística.
- `all` e `any` fazem curto-circuito da esquerda para a direita.
- Variável inexistente em tempo de execução é erro de conteúdo: a condição vale `false` e o runtime registra o erro (o validador já deveria ter barrado).

## 6. Expressões de valor e efeitos

### 6.1. Expressões de valor

Usadas em `effects[].value`, em `derived` e em payloads de eventos:

| Forma | Exemplo |
|---|---|
| Literal | `100`, `true`, `"night"` |
| Variável | `{ "var": "global.fishing_skill" }` |
| Função | `{ "fn": "add", "args": [{ "var": "global.player_money" }, 10] }` |
| Condicional | `{ "if": [cond...], "then": 1, "else": 0 }` |
| Resultado de plugin | `{ "result": "score" }` ou `{ "result": "score", "default": 0 }` (só em `on_result.effects`, T005) |

Se o campo pedido em `{"result": …}` não existe no payload, ou tem tipo diferente do esperado, vale `default`; sem `default`, vale o padrão do tipo da variável de destino (`false`, `0`, `0.0`, `""`). `{"result": "a.b"}` lê o campo `b` do objeto `a`. O validador confere o caminho inteiro contra o `result_schema` da atividade (T005) e o tipo do campo contra o da variável de destino (T006).

### 6.1.1. Funções

A semântica é a mesma no runtime e na implementação de referência (Runtime Spec §12.1). "Inteiro" é um `integer`; "número" é `integer` ou `number`.

| Função | Argumentos | Resultado |
|---|---|---|
| `add`, `sub`, `mul` | 2 números | `integer` se os dois forem inteiros; senão `number` |
| `div` | 2 números | Sempre `number` (`7 / 2 = 3.5`). Divisor zero: erro de conteúdo, a transação é abortada |
| `mod` | 2 inteiros | `integer`, com o sinal do divisor (`-7 mod 3 = 2`). Divisor zero: erro de conteúdo |
| `min`, `max` | 2 a 8 números | Mesmo tipo da regra de `add` |
| `clamp` | `(v, min, max)` | Mesmo tipo da regra de `add` |
| `round` | 1 número | `integer`; metade arredonda para longe do zero (`2.5 → 3`, `-2.5 → -3`) |
| `floor`, `ceil` | 1 número | `integer` |
| `abs` | 1 número | Mesmo tipo do argumento |
| `concat` | 1 a 8 valores | `string`; números são convertidos com ponto decimal e sem separador de milhar (`3.5`, `1000`, `2.0` → `2`; regra completa no Runtime Spec §12.1), booleanos como `true`/`false` |
| `random_int` | `(min, max)` inteiros | `integer` entre `min` e `max`, **inclusivos**. Usa o RNG do jogo (Runtime Spec §12.2). Só vale em efeitos e em payloads de `emit`: em `derived` (recalculada a cada leitura) e em condições (avaliação pura) é erro T008 |

Número e tipo de argumentos errados são erro T007. `clamp` com `min > max` devolve `min`. Inteiros valem no intervalo ±(2^53 − 1) (Runtime Spec §12.1).

Os sorteios (a função `random_int` e o desempate `weighted_random` do capítulo) só são reproduzíveis quando o projeto liga `settings.reproducible_rng`, que é **opcional** e vem desligado. Desligado, eles funcionam normalmente com o RNG comum do motor.

### 6.2. Efeitos

```json
{ "op": "add", "variable": "global.player_money", "value": 100 }
```

| `op` | Tipos | `value` |
|---|---|---|
| `set` | todos | obrigatório |
| `add`, `subtract`, `multiply` | integer, number | obrigatório |
| `toggle` | boolean | proibido |
| `reset` | todos | proibido (volta ao padrão) |

Uma **lista de efeitos é sempre uma transação**: todos são validados (tipo, restrições, permissões) e só então aplicados. Se um falhar (por exemplo `on_overflow: reject`), nenhum é aplicado. Dentro da lista, os efeitos são aplicados em ordem, e cada um enxerga o resultado dos anteriores.

Falha por restrição (`on_overflow: reject`, `max_length`, valor fora de `values`) **não é erro de conteúdo**: é lógica de jogo ("não tem dinheiro"). O nó `effects` desvia para `on_fail`, se houver; nos `effects` de uma opção de escolha, a transação é desfeita e a cena segue para o `goto` da opção mesmo assim. Para não oferecer uma opção que vai falhar, use `enabled_if` (o Studio sugere isso quando um efeito pode violar `reject`).

`max_length` com `on_overflow: clamp` corta a string no limite. Resultado `number` gravado numa variável `integer` (ex.: `add` com `div`) é truncado em direção a zero; o validador emite W017 quando detecta isso estaticamente (use `round`, `floor` ou `ceil` para deixar a intenção explícita).

Na escolha, os `effects` da opção e o `record` formam **uma única** transação.

## 7. Capítulos

```json
{
  "id": "ch01",
  "title": "A praia",
  "variables": [{ "key": "days_passed", "type": "integer", "default": 0 }],
  "entry_scene": "scene_arrival",
  "scheduler": { "tie_breaker": "deterministic" },
  "exclusive_groups": [{ "id": "evening_event" }],
  "completion": {
    "conditions": [{ "variable": "chapter.days_passed", "operator": "greater_than_or_equal", "value": 3 }],
    "on_exhausted": "scene",
    "fallback_scene": "scene_quiet_day"
  },
  "next": [{ "chapter": "ch02", "priority": 100 }]
}
```

- `entry_scene`: cena executada a cada entrada no capítulo, sem passar pelo Scheduler e sem checar `max_plays` nem `conditions`.
- `completion.conditions`: verificada em cada ponto de seleção, inclusive o que vem logo depois da `entry_scene`; se verdadeira, o capítulo termina.
- `completion.on_exhausted`: o que fazer quando nenhuma cena é elegível — `advance` (padrão, termina o capítulo), `scene` (roda `fallback_scene`) ou `end_game`. A `fallback_scene` DEVERIA alterar alguma variável usada em `completion.conditions` (W010); o runtime também limita repetições seguidas (Runtime Spec §4.3).
- `next`: capítulos candidatos, escolhidos pelo mesmo algoritmo de prioridade; nenhum elegível = fim de jogo. As condições de `next` podem usar `chapter.*`, porque são avaliadas antes de as variáveis do capítulo serem descartadas.
- **Reentrada.** `next` pode apontar para um capítulo já visitado. Na nova entrada, `chapter.*` e os grupos do capítulo voltam ao início, mas o `plays` das cenas é mantido: uma cena com `max_plays: 1` não se repete.
- `exclusive_groups`: grupos cujo tempo de vida é o capítulo (o histórico do grupo zera ao sair). Grupos em `project.json` duram o jogo inteiro. Um id de grupo não pode existir nos dois níveis (R015).
- **Mesmo capítulo.** `entry_scene`, `fallback_scene` e `then.scene` DEVEM apontar para cena deste capítulo ou global (`chapter: null`) (R014); uma cena global só pode pedir outra cena global. Pedidos de plugins (`grants.scenes`) passam pela mesma regra no runtime: pedido para cena de outro capítulo é recusado. Mudar de capítulo é sempre `end_chapter` + `next`.

## 8. Cenas

### 8.1. Metadados de agendamento

```json
"scheduling": {
  "mode": "scheduled",
  "priority": 80,
  "conditions": [ ... ],
  "max_plays": 1,
  "cooldown": 0,
  "exclusive_groups": ["evening_event"],
  "weight": 1,
  "order": 10
}
```

| Campo | Padrão | Significado |
|---|---|---|
| `mode` | `scheduled` | `manual` = nunca escolhida pelo Scheduler; só por link direto |
| `priority` | 100 | 0–1000; maior vence |
| `conditions` | `[]` | Elegibilidade (não pode usar `scene.*`) |
| `max_plays` | 1 | Vezes que pode ser **concluída**; `null` = ilimitado |
| `cooldown` | 0 | Pontos de seleção que precisam passar antes de repetir |
| `exclusive_groups` | `[]` | Ao concluir uma cena do grupo, as outras do grupo ficam inelegíveis (até `max_plays` do grupo) |
| `weight` | 1 | Peso no sorteio, se o capítulo usar `weighted_random` |
| `order` | — | Ordem de autoria para desempate. Cenas sem `order` vêm depois das que têm, e entre si pela ordem do ID |

Estes campos respondem às pendências "cenas podem ser repetidas?" (`max_plays`/`cooldown`, padrão: não) e "exclusividade entre cenas" (`exclusive_groups`). O algoritmo que os usa está na Runtime Spec §4.

### 8.2. Grafo de nós

O corpo da cena é uma **lista plana de nós**. O fluxo padrão é sequencial (cada nó segue para o próximo do array); `next`, `goto` e `else` criam desvios. O último nó sem destino termina a cena com `then: "schedule"`. Esse formato é simples de diffar, simples de editar como roteiro linear e ainda permite grafo arbitrário no editor visual.

Campos comuns a todos os nós: `id`, `type`, `next`, `note` (comentário do autor), `editor` (posição no grafo e outros dados do Studio, ignorados pelo runtime), `unresolved` (passo incompleto, ex.: vindo da importação de roteiro; aviso W013 e bloqueio na exportação) e `censor` (modo stream, §10.4).

| `type` | Função | Campos principais |
|---|---|---|
| `line` | Fala ou narração | `speaker` (null = narrador), `text`, `censored_text` (§10.4), `expression`, `voice` |
| `choice` | Menu de escolhas | `prompt`, `censored_prompt`, `speaker`, `options[]` (`id`, `text`, `censored_text`, `value`, `visible_if`, `enabled_if`, `effects`, `goto`), `record` |
| `effects` | Altera variáveis (transação) | `effects[]`, `on_fail` |
| `branch` | Desvio condicional | `cases[]` (`id`, `conditions`, `goto`), `else` |
| `jump` | Desvio incondicional | `goto` |
| `background` | Troca o cenário | `asset` ou `set` (cenário composto, UI Spec §5), `transition` |
| `interact` | Escolha espacial: o jogador clica em áreas da cena | `prompt`, `censored_prompt`, `hotspots[]` (`id`, `label`, `value`, `area`, `cursor`, `highlight`, `visible_if`, `enabled_if`, `once`, `effects`, `goto`), `exit`, `record` (UI Spec §6) |
| `show` / `hide` | Mostra/esconde personagem | `character`, `expression`, `position`, `transition` |
| `audio` | Música, ambiente, efeitos, voz | `action`, `channel`, `asset`, `loop`, `volume`, `fade`, `caption` (legenda, Req §12) |
| `wait` | Pausa | `seconds`, `skippable` |
| `emit` | Emite evento `story.*` (outro namespace é erro R020) | `event`, `payload` |
| `plugin` | Executa atividade de plugin | `activity`, `params`, `on_result` (`effects`, `outcomes`), `on_error` |
| `end` | Termina a cena | `then` (`schedule` / `{scene}` / `end_chapter` / `end_game`), `ending` (só com `end_game`; W011) |

**Escolhas.** `visible_if` falso esconde a opção; `enabled_if` falso a mostra desabilitada. Se nenhuma opção estiver visível, o runtime segue `next` do nó de escolha (ou o nó seguinte do array), e o validador avisa quando isso é possível (W006). Opção sem `goto` também segue `next`. O nó `interact` segue as mesmas regras, com hotspots no lugar das opções (UI Spec §6). `record` grava o `value` da opção escolhida (ou, sem `value`, o ID da opção) numa variável `string`/`enum`; num `enum`, todo `value` DEVE estar em `constraints.values` (R016).

**Apresentação no palco.** `show` de um personagem que já está no palco troca a expressão e move para a nova `position`, com a `transition` dada; ausente, `position` vale `center` (na primeira vez) ou a posição atual, e `expression` vale `default_expression` do personagem (na primeira vez) ou a expressão atual. Personagens mostrados depois ficam na frente. `line.expression` troca a expressão do `speaker` se ele estiver no palco; senão é ignorada. Uma nova `line` interrompe a `voice` da anterior. `audio` com `loop` ausente: `true` em `music` e `ambient`, `false` em `sfx` e `voice`; `fade` em `stop` é a duração do fade-out. `wait.skippable` vale `true` por padrão.

**Nó de plugin.** É o único ponto onde gameplay de plugin entra numa cena. A cena fica suspensa até a atividade terminar. O resultado tem um `outcome` (declarado no manifesto) e um payload. `on_result.effects` permite que **o autor** copie dados do resultado para variáveis do projeto (`{"result": "score"}`) sem dar ao plugin permissão de escrita. `outcomes` mapeia cada resultado para um nó; outcome sem mapeamento segue `next`. Se o plugin faltar ou falhar, segue `on_error` (padrão `next`).

**Finais.** Todo final é declarado em `project.json → endings` (`id`, `title`, `description`, `image`). O nó `end` aponta para ele com `ending`, junto com `then: "end_game"`; final não declarado é erro (R012) e `ending` com outro `then` é ignorado com aviso (W011). A lista alimenta a galeria de finais e `sys.endings.<id>`.

**Fim de cena.** `then: {"scene": "x"}` é um **pedido**, não uma ordem: o Scheduler o aceita se `x` for do capítulo ativo ou global e estiver elegível ou for `manual`; senão faz a seleção normal. Isso preserva o princípio "o Scene Scheduler é a autoridade sobre a seleção" (ADD §15) e ainda dá ao roteirista sequências encadeadas.

## 9. Textos e internacionalização

- O texto é escrito **inline** no idioma `default_locale` do projeto. Roteiristas não manipulam chaves de tradução.
- Um projeto tem de 1 a *n* idiomas: `default_locale` mais uma pasta `locales/<lang>/` por tradução, com qualquer tag BCP 47. Os idiomas do jogo são independentes dos idiomas da interface do Studio (Req §9.1). `build.locales` escolhe quais entram num build.
- Traduções ficam em `locales/<lang>/`, indexadas pelo caminho de texto. O arquivo é escolhido **pelo id**, não pelo título, para não mudar quando o título muda.
- `source_hash` em cada tradução permite ao Studio marcar traduções desatualizadas quando o texto-fonte muda. É o SHA-256 do texto-fonte normalizado em NFC e sem espaços nas pontas, nos 16 primeiros caracteres hex.
- Interpolação: `{global.player_money}`, `{character.alice.affection}`. Chaves literais: `{{` e `}}`. Interpoláveis: qualquer variável que o texto possa ler naquele ponto (mesma regra de escopo das condições), inclusive `sys.*` e derivadas; variável inexistente ou fora de escopo é erro R019. Vale em falas, opções, `prompt`, `display_name`, títulos e descrições de finais, textos de telas (UI Spec §3.3) e traduções. Números usam o separador decimal e de milhar do idioma, numa tabela própria do runtime (Runtime Spec §12.1); booleanos aparecem como `true`/`false`. Enums aparecem pelo rótulo de `constraints.labels`, traduzível, ou pelo valor se não houver rótulo.
- Texto ausente na tradução cai no idioma-fonte.

| Texto | Caminho | Arquivo em `locales/<lang>/` |
|---|---|---|
| Fala, `prompt` de escolha, `caption` de áudio | `<cena>/<nó>` | `scenes/<cena>.json` |
| Opção de escolha | `<cena>/<nó>/<opção>` | `scenes/<cena>.json` |
| Versão censurada (modo stream, §10.4): `censored_text` de fala, `censored_prompt`, `censored_text` de opção | `<cena>/<nó>/censored`, `<cena>/<nó>/<opção>/censored` | `scenes/<cena>.json` |
| Título de capítulo | `chapter/<capítulo>/title` | `project.json` |
| Nome e `display_name` de personagem | `character/<personagem>/name`, `character/<personagem>/display_name` | `project.json` |
| Título e descrição de final | `ending/<final>/title`, `ending/<final>/description` | `project.json` |
| Título do jogo | `project/title` | `project.json` |
| Textos de telas e sets (menus, botões, créditos) | `ui/<tela>/<elemento>…`, `sets/<set>/<hotspot>` (UI Spec §3.3) | `ui/<tela>.json`, `sets/<set>.json` |
| `prompt` e rótulos do nó `interact` | `<cena>/<nó>`, `<cena>/<nó>/<hotspot>`, `<cena>/<nó>/exit` | `scenes/<cena>.json` |
| Rótulo de valor de enum | `variable/<id qualificado>/value/<valor>` | `project.json` |
| Mensagens e textos prontos do runtime | `runtime/message/<código em minúsculas>` (Build System §13.1), `runtime/confirm/…`, `runtime/settings/…` (preset, UI Spec §2) | `project.json` |
| Textos de plugin | `plugin/<namespace>/…` (Plugin SDK §5.7) | `plugins/<namespace>.json` |

`<cena>`, `<nó>`, `<opção>`, `<capítulo>` e `<personagem>` são os UUIDs; `<final>` é o id legível. O nome do arquivo de uma cena em `locales/<lang>/scenes/` é o UUID da cena, que não muda quando o título muda; o tradutor trabalha pela planilha (Req §9), não por esses arquivos. Um texto num arquivo diferente do da tabela gera o aviso W023.

### 9.1. Marcação de texto

Falas, opções, `prompt` e textos de telas (`label` e botões) aceitam um subconjunto pequeno de marcação, igual no runtime e na implementação de referência. Nomes de personagem, títulos e descrições de finais **não** aceitam marcação (aparecem em menus e na galeria):

| Marca | Efeito |
|---|---|
| `[b]…[/b]`, `[i]…[/i]` | Negrito, itálico |
| `[color=#rrggbb]…[/color]` | Cor |
| `[pause=0.5]` | Pausa na digitação, em segundos |
| `[speed=2]…[/speed]` | Multiplica a velocidade de digitação |
| `[[` e `]]` | Colchetes literais |

Marcas desconhecidas, desequilibradas ou com parâmetro inválido (`[color=azul]`, `[pause=abc]`; `pause` aceita de 0 a 10 s e `speed` de 0,1 a 10) são erro de validação (R018). A interpolação acontece antes da marcação, e o valor interpolado é escapado (um `[` vindo de variável aparece como texto). Tradutores veem as marcas na planilha e DEVEM mantê-las equilibradas; o Studio confere na importação.

## 10. Assets

Todo conteúdo referencia assets por **ID** registrado em `assets.json`, nunca por caminho. Renomear ou mover um arquivo altera só o registro. O Asset Manager calcula `hash` para detectar mudanças e repassa `import` ao Godot no build.

### 10.1. Importação

O Asset Manager aceita arrastar arquivos ou pastas. Ele copia o arquivo para `assets/`, propõe o `type` pela pasta e extensão, gera o ID a partir do nome do arquivo e pede confirmação só quando há ambiguidade.

| Tipo | Formatos aceitos | Recomendação |
|---|---|---|
| `background` | PNG, JPG, WebP | Na resolução do projeto (`settings.resolution`) |
| `sprite` | PNG, WebP (com transparência) | Todas as expressões de um personagem com o mesmo tamanho de tela |
| `image` | PNG, JPG, WebP, SVG | Interface e galeria |
| `audio_music`, `audio_sfx`, `audio_voice` | OGG, WAV, MP3 | OGG para música (loop sem falha) |
| `video` | OGV (WebM convertido pelo Studio) | — |
| `font` | TTF, OTF | — |
| `other` | Qualquer | Arquivo usado só por plugins; o runtime não o interpreta. Referenciado num campo `format: "vn-asset"` do plugin (Plugin SDK §4.4), entra no build sozinho; senão, precisa de `always_include` |

Fora dessa lista, o Studio converte quando pode (ex.: GIF → sequência) ou recusa com mensagem clara. Imagens maiores que 4096 px em qualquer lado geram aviso.

**Crédito de terceiros** (decisão de 2026-11-22). Um asset feito por outra pessoa, como os de pacotes gratuitos de arte, leva o campo opcional `credit`: `{ "author", "license"?, "url"?, "notice"? }`. `author` é quem deve ser creditado; `notice` é o texto exato que a licença pede para mostrar, quando houver. O crédito acompanha o asset: o Build System reúne em `vn_content/licenses.txt` o `credit` de cada asset que **entra no jogo** (Build System §4.5), e a tela de créditos o mostra com `licenses_list` (UI Spec §3.1). Um asset que não entra no build não aparece nos créditos, e o autor não digita créditos de arte à mão. `credit` não entra no `bundle.json` nem no `content_hash`.

```json
"bg/forest": {
  "path": "backgrounds/pack/forest.png", "type": "background",
  "credit": { "author": "Estúdio Exemplo", "license": "CC BY 4.0", "url": "https://example.com/pack" }
}
```

### 10.2. Palco: posição, âncora e escala

- `show.position` aceita os nomes `far_left` (0.1), `left` (0.25), `center` (0.5), `right` (0.75), `far_right` (0.9) ou uma fração da largura da tela.
- Cada sprite tem `anchor` (padrão `[0.5, 1.0]`, centro dos pés) e `scale` (padrão 1.0). A âncora fica na posição horizontal escolhida e na base da tela. `scale: 1.0` desenha o sprite com o tamanho em pixels da imagem na resolução base (`settings.resolution`); a tela inteira é escalada junto (Runtime Spec §1.1).
- **Galeria.** `assets.json → gallery: true` põe um `image`/`background` na galeria de imagens e um `audio_music` na de músicas, se o projeto tiver essas seções (§10.5).
- O Character Manager mostra o sprite sobre um cenário de exemplo e permite arrastar a âncora e ajustar a escala, com os valores gravados em `assets.json`.

### 10.3. Aparência do jogo (tema)

`theme.json` (`theme.schema.json`) define **como** a interface é: fontes (com reservas por idioma), cores, caixa de diálogo (imagem com `nine_slice`, posição, altura, plaquinha de nome), botões de escolha, sons de interface e estilos de botão com nome. As telas (título, pausa, salvar/carregar, configurações, galeria, créditos, HUD e telas próprias) ficam em `ui/*.json` e dizem **onde** cada elemento fica e **o que** faz; cenários com objetos clicáveis ficam em `sets/*.json`. Tudo é opcional: o que falta vem do preset escolhido em `theme.json → preset` (no v1, só `classic`). O runtime monta a interface a partir desses arquivos; a artista nunca abre o Godot. Assets do tema, das telas e dos sets seguem a regra R004. Detalhes e regras U001–U008 na UI Spec ([06-ui-menus-and-interaction-specification.md](06-ui-menus-and-interaction-specification.md)).

### 10.4. Modo stream (versão censurada)

O jogador (ou quem transmite o jogo ao vivo) liga o **modo stream** nas configurações, e as partes impróprias para menores aparecem na **versão censurada da mesma cena**. A cena não é pulada: ela roda inteira, com outras imagens, outros sons e outras falas onde o autor pediu.

**Regra de ouro: só a apresentação muda, nunca a história** (decidido em 2026-11-15). Com o modo ligado ou desligado, a cena passa pelas mesmas escolhas, aplica os mesmos efeitos e chega ao mesmo fim. Por isso o modo pode ser ligado e desligado a qualquer momento, no meio de uma cena, e um save feito num modo carrega no outro sem diferença de progresso.

O autor marca o conteúdo em três níveis, do mais simples ao mais fino:

| Nível | Onde | O que faz |
|---|---|---|
| **Asset** | `assets.json → censored` | `{"replace_with": "<asset>"}` troca este asset por outro **em todo lugar** onde ele aparece: cenário, expressão de personagem, música, voz, imagem de tela e de set, galeria, imagem de final e assets que plugins carregam (Plugin SDK §5.6). `{"hide": true}` não desenha nem toca nada: o sprite some, o som fica mudo, e um cenário ou imagem dá lugar ao `content_filter.placeholder` do projeto (ou à cor de fundo do tema). É o caso mais comum: o autor marca uma vez e não mexe em nenhuma cena |
| **Texto** | `censored_text` em `line` e em opções; `censored_prompt` em `choice` e `interact` | Mostrado no lugar do original. Segue as mesmas regras de interpolação e marcação (§9, §9.1) e tem tradução própria (caminho `…/censored`). A voz da fala segue a troca do asset de voz, se ele tiver `censored` (fala com `censored_text` e voz sem `censored` gera o aviso W025). Também têm versão censurada a legenda de `audio` (`censored_caption`) e os rótulos de hotspot e de `exit` em `interact` (`censored_label`), com caminho `…/censored`. A legenda segue o asset: com `hide`, não aparece; com `replace_with`, mostra `censored_caption` (ou nada, se não houver) |
| **Passo** | `censor` num nó | `skip`: o passo só acontece com o modo desligado; `only`: só com o modo ligado. Quando o passo não vale, o runtime segue `next` (ou o nó seguinte) sem executá-lo. Vale **só** em passos de apresentação que põem algo na tela ou no som: `line`, `background`, `show`, `audio` com `action: play` e `wait` (R023). `hide` e `audio` que para um som não aceitam: o que muda com o modo é a entrada de um item, não a saída (decisão de 2026-11-22) |

```json
"assets": {
  "cg/quarto_noite":      { "path": "cg/quarto_noite.png", "type": "background", "gallery": true,
                            "censored": { "replace_with": "cg/quarto_noite_safe" } },
  "cg/quarto_noite_safe": { "path": "cg/quarto_noite_safe.png", "type": "background" },
  "sfx/gemido":           { "path": "sfx/gemido.ogg", "type": "audio_sfx", "censored": { "hide": true } }
}
```

```json
{ "id": "…", "type": "line", "speaker": "…", "text": "Fala original.", "censored_text": "Fala para todas as idades." },
{ "id": "…", "type": "line", "text": "Descrição explícita.", "censor": "skip" },
{ "id": "…", "type": "line", "text": "A noite passou.",       "censor": "only" }
```

O que garante a regra de ouro:

- `censor` é recusado em escolhas, `interact`, efeitos, desvios (`branch`, `jump`), `emit`, minijogos e `end` (R023): esses passos sempre rodam. Também é recusado em `hide` e em `audio` sem `play`, porque um item tirado do palco por um passo que não rodou não teria como voltar quando o modo muda.
- O estado do filtro (`sys.ui.content_filter`) só pode ser lido por telas e sets, por exemplo para mostrar um selo "modo stream" no HUD. Uma condição, efeito, derivada ou interpolação de cena ou capítulo que o leia é erro (R022).
- Numa tela, a leitura só serve para enfeites. Também é R022 ler `sys.ui.content_filter*` numa condição que decide uma ação `effects` ou `emit`: o `if` da própria ação ou de uma ação que a envolve, um valor de `effects` ou `payload`, ou o `visible_if`/`enabled_if` do elemento que dispara a lista ou de um `container` que o contém (UI Spec §11).
- O palco lembra o `censor` do passo que pôs cada item (cenário, personagem, canal de áudio) e o estado do item antes desse passo. Ao mudar o modo, e ao carregar um save, o runtime volta ao estado anterior os itens cujo passo não valeria no modo atual, como se ele não tivesse rodado: o cenário anterior (asset ou set), a expressão anterior da personagem, a música anterior do canal; sem estado anterior, o item sai (Runtime Spec §5.5, decisões D19 de 2026-11-17 e de 2026-11-22).
- Um minijogo NÃO DEVE devolver outro `outcome` ou `payload`, nem escrever variáveis ou emitir eventos diferentes, conforme o modo (Plugin SDK §5.6).
- Uma substituta de asset não pode ter `censored` (sem cadeias) nem ser o próprio asset (R024).
- Nomes de personagem (`display_name`), títulos de capítulo, títulos e descrições de finais e textos de telas não têm versão censurada: devem ser neutros. Uma tela pode trocar um texto pelo modo com `visible_if`, porque isso só muda a apresentação.
- Um projeto com conteúdo marcado sem nenhum jeito de o jogador ligar o modo (controle `content_filter` numa tela, `ask_on_first_launch` ou `default: true`) gera o aviso W024.

`project.json → content_filter` traz `default` (valor inicial da configuração, padrão `false`), `ask_on_first_launch` (pergunta antes do título na primeira vez que o jogo abre, Runtime Spec §3.0) e `placeholder` (imagem neutra para cenários escondidos e miniaturas de save sensíveis). `build.edition: censored` gera a **edição censurada**, com o filtro sempre ligado e sem os originais no pacote (Build System §5.4). Como o modo liga, e o que acontece com saves, galeria e minijogos, está na Runtime Spec §3.0, §5.5 e §8, na UI Spec §8 e no Plugin SDK §5.6.

### 10.5. Galeria (opcional)

Decisão de 2026-11-16: a galeria é **opcional por projeto**. O autor decide se o jogo tem galeria e o que entra nela. Um projeto novo começa **sem galeria**.

**Ativar.** `project.json → gallery` liga a galeria e diz quais seções ela tem:

```json
"gallery": { "sections": ["endings", "images", "music"] }
```

| Seção | O que entra | De onde vem |
|---|---|---|
| `endings` | Finais | Todos os de `project.json → endings` (§9), com `title`, `description` e `image` |
| `images` | Imagens e cenários (CGs) | Assets `image` e `background` com `gallery: true` em `assets.json` |
| `music` | Músicas | Assets `audio_music` com `gallery: true` |

`sections` tem de 1 a 3 itens, sem repetir. A ordem da lista não importa: o preset mostra as abas sempre na ordem finais, imagens, músicas. Ausente `gallery`, o jogo não tem galeria.

**Escolher o que entra.** Finais entram todos. Imagens e músicas entram uma a uma: o autor marca `gallery: true` no asset e, se quiser, `gallery_order` (inteiro; os sem ordem vêm depois, pelo id). Assim um cenário comum fica fora e a CG de um momento importante entra. Outros tipos de asset (sprites, sons, vozes, fontes) não entram. Novas seções (por exemplo, replay de cenas) ficam para depois do v1.

**O que muda sem galeria ou sem uma seção.**

- Sem `gallery`: o compilador não inclui a tela `gallery` do preset (UI Spec §2.1), `sys.ui.has_gallery` é falso e o botão "Galeria" do título some. Uma tela `ui/gallery.json` do projeto também fica fora do jogo (aviso U014).
- Seção fora de `sections`: a aba dela some da tela do preset, e o compilador tira `gallery` e `gallery_order` dos assets daquele tipo no bundle (aviso U013 no validador), para o runtime não marcar nada.
- Os **finais vistos continuam sendo gravados** no perfil mesmo sem galeria, porque `sys.endings.<id>` serve também para NG+ e condições do título.
- As **imagens e músicas vistas também continuam sendo gravadas** (decisão D20 de 2026-11-17): o runtime registra em `profile.seen_assets` todo asset `image`, `background` e `audio_music` que aparece numa cena, com ou sem galeria e com ou sem `gallery: true`. A galeria filtra na hora de mostrar. Assim, um jogo que ganha galeria (ou marca uma CG com `gallery: true`) numa atualização mostra desbloqueado o que o jogador já viu.

**Como o jogo registra o que o jogador viu.** Tudo fica no perfil (`profile.json`, Runtime Spec §8.5), que vale para todos os saves e sobrevive a um jogo novo:

- **Finais:** `profile.endings`, no `end` com `ending` (Runtime Spec §3.4).
- **Imagens e músicas:** `profile.seen_assets`, a lista de ids dos assets `image`, `background` e `audio_music` já vistos numa cena, em ordem lexicográfica. A regra exata de quando um asset conta está na Runtime Spec §5.2.

Um item não visto aparece bloqueado (`locked_asset` e o texto `runtime/gallery/locked`, UI Spec §3.1). A ação `reset_profile` apaga tudo isso junto com o resto do perfil.

## 11. Regras de validação semântica

O JSON Schema garante a forma. O Content Validator (implementação de referência em `tools/validate.py`) aplica as regras abaixo. **Erros** bloqueiam build; **avisos** não.

| Código | Nível | Regra |
|---|---|---|
| S000 | erro | Arquivo não satisfaz o schema |
| R001 | erro | ID duplicado (UUID repetido em qualquer entidade do projeto; `key` de personagem repetida) |
| R002 | erro | Variável declarada duas vezes |
| R003 | erro | `initial_values` aponta variável de personagem inexistente |
| R004 | erro | Asset não registrado |
| R005 | erro | Variável inexistente ou fora de escopo no ponto de uso |
| R006 | erro | Cena referenciada não existe |
| R007 | erro | Capítulo referenciado não existe (inclusive em `project.chapters`) |
| R008 | erro | Grupo de exclusividade não definido |
| R009 | erro | Destino de `next`/`goto`/`else`/`on_error`/`on_fail`/`start` não existe na cena |
| R010 | erro | Personagem inexistente |
| R011 | erro | Expressão inexistente para o personagem (inclusive `default_expression`) |
| R012 | erro | `ending` não declarado em `project.json → endings` |
| R013 | erro | `build.locales` não contém `default_locale` ou cita idioma fora de `locales` (Build System §5.3) |
| R014 | erro | `entry_scene`, `fallback_scene` ou `then.scene` aponta para cena de outro capítulo (cena global só pode pedir cena global) |
| R015 | erro | Grupo de exclusividade com o mesmo id no projeto e num capítulo |
| R016 | erro | `record` numa variável que não é `string`/`enum`, ou `value` de opção ou hotspot fora dos valores do enum |
| R017 | erro | `persistence: profile` fora de variável global ou de plugin |
| R018 | erro | Marcação de texto desconhecida, desequilibrada ou com parâmetro inválido (seção 9.1) |
| R019 | erro | Variável interpolada inexistente ou fora de escopo (seção 9) |
| R020 | erro | Nó `emit` com evento fora do namespace `story` |
| R021 | erro | Só na exportação: `project.json` sem `version` |
| R022 | erro | `sys.ui.content_filter` ou `sys.ui.content_filter_available` lido numa cena, capítulo ou derivada, ou numa tela onde decide uma ação `effects` ou `emit` (o modo stream não muda a história, §10.4) |
| R023 | erro | `censor` num passo que não é de apresentação (só `line`, `background`, `show`, `audio` com `action: play` e `wait`, §10.4) |
| R024 | erro | `censored.replace_with` aponta para o próprio asset ou para um asset que também tem `censored`; `content_filter.placeholder` com `censored` |
| T001 | erro | Literal incompatível com o tipo da variável |
| T002 | erro | Escrita em variável derivada, `sys.` ou de plugin (`plugin.*`) |
| T003 | erro | Operação incompatível com o tipo (`add` em string, `toggle` em número) |
| T004 | erro | Ciclo entre variáveis derivadas |
| T005 | erro | `{"result": …}` fora de `on_result.effects`, ou caminho ausente do `result_schema` da atividade |
| T006 | erro | Tipo de uma expressão (`var`, `fn`, `if`, `{result}`) incompatível com a variável de destino |
| T007 | erro | Função com número ou tipo de argumentos errado (seção 6.1.1) |
| T008 | erro | `random_int` em variável derivada ou em condição |
| P001 | erro | Namespace de plugin duplicado no projeto |
| P002 | erro | Atividade não declarada por nenhum plugin |
| P003 | erro | Atividade de plugin não listado em `plugins.json` |
| P004 | erro | `params` ou `config` não satisfaz o schema do plugin |
| P005 | erro | Outcome não declarado pela atividade |
| P006 | erro | Capacidade concedida que o plugin não pediu |
| P007 | erro | Variável concedida que o plugin não pediu |
| P008 | erro | Variável concedida para escrita com `plugins_write: none` |
| P009 | erro | Evento declarado fora do namespace do plugin |
| P010 | erro | `outcome_labels` cita outcome não declarado |
| P011 | erro | `class_name`, grupo ou ação de input do plugin sem o prefixo do namespace |
| P012 | erro | Caminho `res://` do plugin fora de `res://vn_plugins/<namespace>/`, de uma dependência ou do SDK |
| P013 | erro | Exportação com plugin vinculado em desenvolvimento (`link: true` em `.vnstudio/plugin-lock.local.json`) |
| P014 | erro | Variável concedida para leitura com `plugins_read: none` |
| P015 | erro | `plugin-lock.json` incoerente com `plugins.json` ou com o manifesto (versão fora da faixa, namespace diferente, plugin ausente) |
| P016 | erro | Capacidade de editor `network` pedida por plugin que não é oficial |
| P017 | erro | Variável de plugin com `access`/`characters`, `derived` lendo fora do próprio namespace, ou pedido de variável de outro plugin sem dependência declarada (ou para escrita) |
| P018 | erro | Asset, cena ou personagem citado num campo `vn-asset`/`vn-scene`/`vn-character` da `config` ou dos `params` não existe |
| P019 | erro | Plugin declara `records` ou `profile` sem pedir a capacidade `profile.data` |
| P020 | erro | `play_activity` cita atividade inexistente ou sem `free_play` |
| P021 | erro | Fonte `path:` de `plugins.json` não existe, ou a pasta de um plugin embutido não tem exatamente um `vn_plugins/<namespace>/plugin.json` (spec 09 §3.2) |
| W001 | aviso | Nó inalcançável |
| W002 | aviso | Outcome de atividade sem destino explícito |
| W003 | aviso | Tradução órfã |
| W004 | aviso | Manifesto de plugin indisponível; permissões não verificadas |
| W005 | aviso | Capítulo pode não ter cena elegível e não tem `fallback_scene` |
| W006 | aviso | Escolha ou `interact` pode ficar sem opções ou hotspots visíveis |
| W007 | aviso | Parâmetro, outcome ou variável de plugin sem rótulo legível (`title`, `outcome_labels`, `name`) |
| W008 | aviso | O projeto exporta para uma plataforma fora de `compatibility.platforms` de um plugin |
| W009 | aviso | Plugin usa API do Godot vetada em plugins (Plugin SDK §12.2); bloqueia a publicação no catálogo |
| W010 | aviso | `fallback_scene` não altera nenhuma variável usada em `completion.conditions` |
| W011 | aviso | `ending` num nó `end` cujo `then` não é `end_game` (ignorado) |
| W012 | aviso | Plugin declara `events.subscribes` sem pedir `events.subscribe` |
| W013 | aviso | Passo marcado como incompleto (`unresolved`); vira erro na exportação |
| W014 | aviso | Asset de tipo incompatível com o uso (ex.: `font` como cenário) |
| W015 | aviso | Evento `story.*` emitido ou testado sem declaração em `project.json → events` |
| W016 | aviso | Chave `runtime/` usada pelo plugin sem texto em `plugin_locales[default_locale]` |
| W017 | aviso | Resultado `number` gravado em variável `integer` (será truncado) |
| W018 | aviso | Capítulo que não aparece em `project.chapters` |
| W019 | aviso | `event_since_last_selection` com evento `sys.*` (sempre falso, Runtime Spec §7.2) |
| W021 | aviso | Idioma do jogo fora dos idiomas do produto sem tradução dos textos prontos do runtime (`runtime/…`); caem no inglês (Req §9.1) |
| W022 | aviso | Plugin com quadros de recordes sem a concessão de `profile.data`: recordes e dados de perfil seriam recusados |
| W023 | aviso | Tradução num arquivo de `locales/<lang>/` diferente do que a tabela do §9 define |
| W024 | aviso | O projeto tem conteúdo marcado para o modo stream, mas o jogador não tem como ligá-lo: nenhuma tela (do projeto ou do preset) liga `content_filter`, e `content_filter.ask_on_first_launch` e `default` estão desligados (§10.4) |
| W025 | aviso | Fala com `censored_text` cuja voz (`voice`) não tem `censored`: com o modo ligado, a voz original toca sob o texto censurado (§10.4) |

Todo código tem uma mensagem em linguagem simples no idioma do Studio e leva ao ponto exato do problema (ver [Requisitos de autoria](04-studio-authoring-requirements.md) §6).

Telas, sets e estilos têm regras próprias (U001–U014, W020) na UI Spec §11. O validador de referência implementa todos os códigos acima e os da UI Spec, exceto W005, que exige análise de satisfatibilidade das condições, e W020, que exige ler os arquivos de fonte. W006 e W010 são aproximações: W006 avisa quando todas as opções têm `visible_if` (no `interact`, quando todos os hotspots têm `visible_if` e não há `exit`), e W010 quando a `fallback_scene` não escreve em nenhuma variável citada em `completion.conditions`. `tools/test_validate.py` contém um caso quebrado de propósito para cada código implementado.

O `tools/validate.py` é a **referência de conformidade**: o validador do Studio (TypeScript) implementa as mesmas regras e passa nos mesmos casos.

## 12. Versionamento e migração

- `project.json → format_version` é a versão deste modelo usada pelo projeto (SemVer).
- MINOR acrescenta campos opcionais; projetos antigos continuam válidos sem mudança.
- MAJOR exige migração. O Studio mantém migradores encadeados (`1.x → 2.0`, `2.x → 3.0`), faz backup do projeto antes, mostra o diff e pede confirmação explícita em migrações destrutivas (ADD §10).
- O runtime só carrega conteúdo compilado com um MAJOR que ele suporta.
- **Renomear depois de lançar.** O comando "Renomear em todo o projeto" (Req §2) grava a chave antiga em `renamed_from` da variável. O compilador leva os aliases para o bundle e o Save Manager os aplica ao carregar saves antigos e o perfil (Runtime Spec §8.3–8.4). O mesmo vale para a `key` de personagem (alias no próprio personagem) e para IDs de asset (alias em `assets.json`), com o mesmo campo.

## 13. Fora de escopo do v1

Listas e conjuntos como tipo de variável; nós de animação/câmera avançados (vêm por plugin); cenas paralelas ou interrupções no meio de uma cena; condições com funções definidas pelo autor; colaboração em tempo real; **voltar falas (rollback)**. Os modos automático e pular estão no v1 (Runtime Spec §5.2 e §8.5).
