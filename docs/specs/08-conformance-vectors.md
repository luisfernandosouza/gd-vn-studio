# Vetores de conformidade — v1.0.0-draft

- **Status:** rascunho para revisão
- **Base:** Runtime Spec §4 e §12; Data Model §5, §6 e §9
- **Schema:** [`schemas/conformance.schema.json`](schemas/conformance.schema.json)
- **Casos:** [`conformance/`](conformance/)
- **Referência:** [`tools/conformance.py`](tools/conformance.py)

O jogo roda em dois interpretadores: o Runtime em GDScript, dentro do Godot, e o interpretador do Preview no Studio, em TypeScript. Os dois DEVEM tomar exatamente as mesmas decisões. Senão o autor testa uma história no Studio e o jogador vê outra. Este documento define o formato dos casos que garantem isso, o conjunto inicial e como cada implementação os executa.

As palavras **DEVE**, **DEVERIA** e **PODE** seguem a RFC 2119.

## 1. O que é coberto

| Grupo | Arquivo | Cobre | Casos |
|---|---|---|---|
| Expressões e funções | `expressions.json` | DM §6.1, §6.1.1; RT §12.1 (intervalo de inteiros, `concat`) | 31 |
| Condições | `conditions.json` | DM §5, §5.1, §5.2 | 12 |
| Efeitos e transações | `effects.json` | DM §6.2; RT §6.2 (ordem das verificações, rollback, truncamento, restrições) | 11 |
| Texto | `text.json` | RT §12.1 (`concat`, formatação de números por idioma, `settings.number_formats`); exibição de recordes (SDK §9.1) | 25 |
| RNG | `rng.json` | RT §12.2 (PCG32, `random_int`, sementes de atividade e de plugin) | 8 |
| Seleção de cena | `selection.json` | RT §4.2–§4.4 (elegibilidade, prioridade, desempate, pedidos, fim de capítulo, fallback) | 26 |
| Recordes | `records.json` | SDK §9.1 (`submit_record`: ordem, `keep`, empate fica com a mais antiga, posição devolvida; exibição) | 6 |
| Fluxo de cena | `flow.json` | RT §5.1–§5.5, §7.2 (falas com interpolação, escolhas, `on_fail`, `branch`/`jump`, ordem dos eventos, atividade com resultado, pulada e sem opção visível, fim do grafo sem `end`, modo stream ligado e desligado) | 11 |

São 130 casos no total. Todos conferem com a implementação de referência:

```bash
python3 tools/conformance.py
# 130/130 vetores conferem com a referência.
```

Os casos de RNG só valem para projetos com `settings.reproducible_rng` ligado (RT §12.2). Uma implementação PODE pular `rng.json` e o caso `weighted` de `selection.json` enquanto não implementa o RNG reproduzível, mas DEVE passar em todos os outros.

**Ainda fora do conjunto:** o nó `interact`, a interpolação com marcação de estilo e o JCS (já coberto pelo `examples/demo-save.json`). Entram em casos `flow` e `text` novos quando o runtime chegar a eles.

## 2. Formato

Cada arquivo de `conformance/` tem `title`, `covers` (as seções que exercita) e `cases`. Cada caso tem `id` (único no arquivo), `description`, `kind`, as entradas e `expect`, o resultado esperado.

```json
{ "id": "mod_neg_dividend", "description": "mod com o sinal do divisor (-7 mod 3 = 2)",
  "kind": "expression", "expr": { "fn": "mod", "args": [-7, 3] },
  "expect": { "type": "integer", "value": 2 } }
```

### 2.1. Valores com tipo

Variáveis de entrada vêm com tipo explícito, porque o JSON não distingue `2` de `2.0`:

```json
"variables": { "global.money": { "type": "integer", "value": 30, "default": 0,
                                 "constraints": { "min": 0, "max": 100, "on_overflow": "reject" } } }
```

Nos resultados, `type` diz qual dos dois é. Um `number` com parte fracionária zero aparece como `2.0` e DEVE ser comparado por valor. Nos casos `text`, `{ "type": "number", "value": 1234567 }` força `number`.

### 2.2. Tipos de caso

| `kind` | Entradas | `expect` |
|---|---|---|
| `expression` | `expr` (expressão de valor), `variables`, `rng_state`? | `{type, value}` ou `{error}` |
| `condition` | `conditions`, `variables`, `events` (eventos desde a última seleção) | `{value}` ou `{error}` |
| `effects` | `effects` (uma transação), `variables` | `{changes}` (lista `{variable, old, new}`, na ordem, só o que mudou) ou `{error}` |
| `text` | `mode` (`concat` ou `interpolation`), `value`, `locale` | `{text}` |
| `rng` | `op` (`sequence`, `random_int`, `activity_seed`, `plugin_seed`), `seed` e os parâmetros da operação | `{values, state_after?}` ou `{seed}` |
| `selection` | `chapter`, `scenes`, `state` (`variables`, `history`, `rng_state`), `content_request`? | Decisão (§2.3) |
| `text` com `mode: record` | `value` (a marca), `format` (`integer`, `number`, `time_ms`), `locale` | `{text}` |
| `record` | `board` (`order`, `keep`, `format`), `entries` (as marcas atuais), `submit` (`score`, `at`, `meta`?) | `{rank, entries}` (`rank` 0 quando a marca não entra) |
| `flow` | `scene` (nós no formato de `scene.schema.json`), `variables`, `locale`, `content_filter`? (modo stream, RT §5.5), `inputs` (lista de `"advance"`, `{choose: <opção>}` ou `{activity: {outcome, payload, skipped?, failed?}}`) | `{trace}`: lista em ordem, cada item com uma chave só: `event` (evento `sys.*` ou do conteúdo), `node` (nó em que entrou), `text` (fala já interpolada), `options` (opções mostradas), `changes` (mudanças de uma transação), `waiting` (o caso acabou parado num nó bloqueante), `error` e `end` (o `then` da cena) |

Um caso `text` aceita também `number_formats`, que simula `project.json → settings.number_formats`.

`error` é o código do RT §6.2: `VARIABLE_NOT_FOUND`, `TYPE_MISMATCH`, `OUT_OF_RANGE` ou `CONSTRAINT_VIOLATION`. Num caso `effects` com erro, nenhuma variável muda (a transação é desfeita), e o caso não lista mudanças.

Sementes e estados do PCG32 são hexadecimais de 16 dígitos, como no save.

### 2.3. Decisão do Scheduler

Um caso `selection` descreve o estado num ponto de seleção e espera o mesmo conteúdo de `scheduler.evaluated` (Preview Protocol §4.3), mais o histórico depois da decisão:

```json
"expect": {
  "action": "start_scene", "chosen": "019a7a00-…-00000000000b", "reason": "priority",
  "candidates": [
    { "scene": "019a7a00-…-00000000000a", "eligible": true, "blocked_by": "lower_priority" },
    { "scene": "019a7a00-…-00000000000b", "eligible": true }
  ],
  "selection_count_after": 1, "fallback_streak_after": 0 }
```

- `action` é `start_scene`, `exit_chapter` ou `end_game`; `chosen` é `null` quando nenhuma cena começa.
- `candidates` segue a ordem dos ids e fica vazia quando a decisão sai antes da etapa 4 do algoritmo (pedido aceito ou fim de capítulo).
- `blocked_by` aparece em toda candidata não escolhida: o primeiro filtro de elegibilidade que falhou (RT §4.2, na ordem `mode_manual`, `max_plays`, `cooldown`, `exclusive_group`, `conditions`), ou `lower_priority`/`tie_break` para as elegíveis.
- `request_refused` aparece quando um pedido foi recusado e a decisão seguiu adiante.
- `detail` e `failed` (Preview Protocol §4.3) são informativos e não entram na comparação.

## 3. Regras normativas que os casos fixam

Estas regras estavam implícitas ou ambíguas; os casos as fixam, e o RT foi ajustado:

1. **Divisão e `mod` por zero** abortam com `OUT_OF_RANGE` (RT §12.1).
2. **Arredondamento na interpolação** age sobre a representação decimal mais curta do número, a mesma do `concat`: `1.005` vira `1.01`, embora o valor binário seja um pouco menor. Assim JavaScript, GDScript e Python concordam sem aritmética decimal exata (RT §12.1).
3. **Negativo que arredonda para zero** aparece sem sinal (`-0.004` → `0`).
4. **`random_int(min, max)`** com intervalo de até 2^32 valores sorteia `r = next_u32()` e rejeita `r < (2^32 − n) mod n`, onde `n = max − min + 1`; o resultado é `min + r mod n`. Com intervalo maior, usa `next_u64() = (next_u32() << 32) | next_u32()` e 2^64 no lugar de 2^32 (RT §12.2).
5. **Semeadura do PCG32:** `state = 0`; avança um passo; `state += seed`; avança um passo. A saída usa o estado **anterior** ao passo (XSH-RR padrão). Com incremento 109 e semente 42, as saídas são as do gerador de referência do PCG (`0xa15c02b7`, `0x7b47f409`…), o que permite conferir a implementação contra fontes públicas.
6. **`weighted_pick`** ordena as empatadas pelo id, calcula `r = (next_u32() / 2^32) × soma dos pesos` em ponto flutuante de 64 bits, soma os pesos na mesma ordem e escolhe a primeira cujo acumulado passa de `r` (RT §4.3).
7. **`fallback_streak`** aumenta só quando a `fallback_scene` é escolhida pela etapa 5 e volta a 0 quando qualquer outra cena começa. Com 100, o capítulo termina com `reason: "exhausted"`.
8. **`changes`** lista só as variáveis cujo valor mudou, em ordem de aplicação. `set` para o mesmo valor não gera mudança nem `state.changed`.

## 4. Como cada implementação roda os casos

- **Runtime Godot:** `godot --headless -- --vn-test conformance/` (RT §12). O runner carrega cada arquivo, monta o estado mínimo pedido pelo caso (sem bundle completo) e chama diretamente o Condition Evaluator, o State Manager, o formatador de texto, o PCG32 e o Scene Scheduler.
- **Studio:** a suíte de testes do interpretador do Preview (TypeScript) lê os mesmos arquivos.
- **CI:** os dois runners e `tools/conformance.py` DEVEM passar em toda mudança no Runtime, no Studio ou nos casos. Um caso novo só entra junto com a correção dos três.

A saída de cada runner é uma linha por caso com falha, no formato `FALHOU <arquivo>#<id>`, com o esperado e o obtido, e um resumo `N/M`.

**Casos `flow`.** O runner monta só a cena do caso (sem capítulo nem Scheduler), aplica `variables` e alimenta os `inputs` em ordem a cada nó bloqueante; uma atividade usa o resultado do input em vez de um plugin real. O traço segue a ordem da spec 07 §4.2. São o primeiro alvo do runtime: passar neles é o passo antes de abrir a demo com `--vn-bundle` (RT §2.1). Casos com Scheduler entre cenas e com `interact` ficam para a próxima leva.

## 5. Mudanças

Um caso nunca muda de resultado sem uma mudança na spec que o justifique. Mudança de comportamento compatível ganha casos novos; mudança incompatível exige MAJOR do runtime (RT §13) e, junto, a atualização dos casos.
