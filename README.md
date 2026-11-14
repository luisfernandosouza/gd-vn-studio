# Visual Novel Studio — Especificações base (rascunho v1)

Marco da seção 16 do ADD: definir e congelar as três especificações que servem de contrato entre Studio, Runtime e plugins.

| # | Documento | Conteúdo |
|---|---|---|
| 0 | [Architecture Design Document v0.1](00-architecture-design-document-v0.1.md) | Documento original, só formatado |
| 1 | [Narrative Data Model](01-narrative-data-model.md) | Estrutura do projeto, variáveis e escopos, condições, efeitos, capítulos, cenas e nós, i18n, regras de validação |
| 2 | [Narrative Runtime Specification](02-narrative-runtime-specification.md) | Ciclo de vida, algoritmo do Scene Scheduler, execução de nós, State Manager, eventos, saves, erros, preview |
| 3 | [Plugin SDK Specification](03-plugin-sdk-specification.md) | Pacote, manifesto, permissões, Runtime SDK (GDScript), Editor SDK (TS), dependências, publicação |
| 4 | [Requisitos de autoria do Studio](04-studio-authoring-requirements.md) | O que o Studio oferece a quem não programa: condições em frases, "por que a cena não apareceu", erros legíveis, exportação, histórico, tradução, importação de roteiro, tema |
| 5 | [Build System](05-build-system-specification.md) | Pipeline de build, Build Staging, bundle `.vnb`, assets, presets por plataforma, PCK, proteção do conteúdo, manifesto, CLI `vnstudio build` |
| 6 | [Menus, botões e interação](06-ui-menus-and-interaction-specification.md) | Telas montadas pelo autor (título, pausa, configurações…), ações de botões, estilos, cenários com objetos clicáveis, nó `interact`, configurações do jogador (FPS da VN × minijogos), ideias de personalização |
| 7 | [Protocolo do Preview](07-preview-protocol.md) | Conversa Studio ↔ Runtime no Preview: sessão e token, métodos, notificações, `GameState`, `SchedulerEvaluation`, erros |
| 8 | [Vetores de conformidade](08-conformance-vectors.md) | Formato dos casos que o Runtime e o Preview do Studio DEVEM reproduzir, conjunto inicial de 105 casos e implementação de referência |

Artefatos:

- `schemas/` — 17 JSON Schemas (draft 2020-12): `common`, `project`, `variables`, `character`, `chapter`, `scene`, `assets`, `locale`, `save`, `plugin`, `plugins`, `plugin-lock`, `theme`, `ui-screen`, `set`, `preview-protocol` e `conformance`. O domínio `schemas.vnstudio.dev` nos `$id` é provisório.
- `examples/demo-project/` — projeto pequeno com 2 capítulos, 5 cenas, escolhas, branch, variável derivada, grupo de exclusividade, uso do Fishing Minigame, menu inicial com cenário clicável (`ui/title.json`, `sets/beach_title.json`), tela de configurações com FPS separado para VN e minijogos (`ui/settings.json`), créditos e um nó `interact`.
- `examples/fishing-plugin/` — plugin de referência completo: manifesto, GDScript de runtime, cena, testes com `VNTestHarness`, mock de editor, README e CHANGELOG. Corresponde a `vn_plugins/fishing/` do projeto de desenvolvimento.
- `examples/demo-save.json` — save válido, coerente com um caminho real do demo (chegada → praia → pescaria vencida) e assinado com uma chave de exemplo de 32 bytes zero.
- `tools/validate.py` — validador de referência (schema + regras semânticas).
- `tools/test_validate.py` — um projeto quebrado de propósito para cada código do validador.
- `conformance/` e `tools/conformance.py` — vetores de conformidade e a implementação de referência que os confere.

```bash
pip install jsonschema
python3 tools/validate.py examples/demo-project examples/fishing-plugin
# 0 erro(s), 0 aviso(s).
# --export aplica também as regras de exportação (P013, W013 vira erro)
python3 tools/test_validate.py
# um caso por código; todos devem passar
python3 tools/conformance.py
# 105/105 vetores conferem com a referência.
```

## Decisões propostas para as pendências do ADD §13

Cada linha é uma proposta, não uma decisão final. Onde está detalhada:  DM = Data Model, RT = Runtime Spec, SDK = Plugin SDK Spec, BS = Build System.

### 13.1 Sistema narrativo — todas endereçadas

| Pendência | Proposta | Onde |
|---|---|---|
| Algoritmo de seleção | Filtro de elegibilidade → maior prioridade → desempate; só em pontos de seleção, nunca no meio de cena | RT §4 |
| Desempate | Determinístico (menos vista → mais antiga → `order` → `id`); sorteio ponderado opcional por capítulo, reproduzível só com `reproducible_rng` (opcional) | RT §4.3, §12.2 |
| Nenhuma cena elegível | `on_exhausted`: `advance` (padrão) / `scene` (fallback) / `end_game` | DM §7, RT §4.3 |
| Repetição | Não por padrão (`max_plays: 1`); `max_plays` e `cooldown` | DM §8.1 |
| Exclusividade | `exclusive_groups` por capítulo ou jogo, com `max_plays` por grupo | DM §7–8, RT §4.2 |
| Ciclo de vida das variáveis | Tabela por escopo | DM §4.1, RT §6.5 |
| Persistência por escopo | `save` / `profile` / `session` | DM §4.4 |
| Variáveis derivadas | Sim, somente leitura, acíclicas, fora do save | DM §4.5 |
| Alterações simultâneas | Escritor único na thread principal, transações tudo-ou-nada com `expect` (compare-and-set), Scheduler só em ponto de seleção | RT §6.1 |

### 13.2 Editor — parcialmente

| Pendência | Proposta | Onde |
|---|---|---|
| Estrutura do projeto | Um arquivo por entidade, Git-friendly | DM §2 |
| Modelo de cenas e diálogos | Lista plana de nós tipados | DM §8 |
| Undo/redo | Todo comando gera JSON Patch + inverso; plugins usam o mesmo mecanismo | SDK §10.4 |
| Comunicação com Godot / sincronização do preview | WebSocket local + token + JSON-RPC 2.0, com hot reload | RT §11 |
| Interfaces de condições e de seleção de cenas | Condições em frases, predefinições de agendamento, painel "por que não apareceu" | Req §3–4, RT §11 |
| Importação de assets | Formatos, âncora, escala e posições do palco | DM §10.1–10.2 |
| Aparência do jogo | `theme.json` + Theme Editor | DM §10.3, Req §11 |

### 13.3 Runtime — endereçadas

Arquitetura e autoridade dos módulos (RT §1), contratos do State/Variable Manager (RT §6), ciclo de vida dos plugins (SDK §5.1), erros de plugins (RT §9), execução assíncrona (RT §10), persistência e restauração (RT §8), saves e plugins (SDK §9).

### 13.4 Plugin SDK — endereçadas

`plugin.json` (SDK §3 + schema), Runtime SDK e Editor SDK (SDK §5, §10), eventos (SDK §7), configuração (SDK §8), permissões (SDK §4), migração (SDK §9, §10.5), compatibilidade (SDK §11), preview (SDK §10.6), testes (SDK §12).

### 13.5 Segurança — parcialmente

Isolamento de Editor Plugins por iframe sandbox + bridge (SDK §10.1); permissões em três camadas (SDK §4); integridade por hash e revogação via catálogo (SDK §13.3). **Em aberto:** assinatura (proposta ed25519 no v2), política para plugins de runtime não confiáveis (exige sandbox separado, ADD §8.2).

### 13.6 Build e distribuição — endereçada no v1

Build Staging (BS §4), conteúdo do PCK (BS §4.2, §7.2), reprodutibilidade e cache (BS §10). **Em aberto:** conteúdo externo, DLC e atualizações parciais (BS §14), catálogo e publicação comunitária (SDK §13).

### 13.7 Produto — parcialmente

Decidido em 2026-11-14: runtime e SDKs sob licença **MIT** (como o Godot), para que os jogos exportados possam ser distribuídos sem restrição; Studio para Windows, macOS e Linux; interface do Studio e textos prontos do runtime com **inglês como idioma principal** e pt-BR, es, fr, it, de, ja, zh-Hans e zh-Hant como secundários no v1, extensível por arquivo de tradução (Req §9.1); nenhuma telemetria no v1. **Em aberto:** forma de distribuição e atualização do Studio, licença dos plugins oficiais, propriedade dos projetos, colaboração e roadmap de plataformas além do v1.

## Decisões de tecnologia (confirmadas em 2026-11-12)

A stack do ADD §2.1 foi revisada e mantida: **Tauri + React + TypeScript** no Studio, **Godot 4 + GDScript** no Runtime.

**Godot embutido no Studio.** Roteiristas e artistas instalam só o Studio e nunca precisam instalar ou abrir o Godot.

| Item | Decisão |
|---|---|
| Versão do Godot | **4.7.2** (estável mais recente em 2026-11-14; a 4.8 está em beta). Escolhida no lugar da 3.6, que é a linha antiga, só com correções críticas (BS §2.1) |
| Binário do Godot | Distribuído como *sidecar* do Tauri, na versão exata exigida pelo runtime (`compatibility.godot`). Alternativa: download sob demanda no primeiro build, com verificação de hash, para reduzir o instalador |
| Templates de exportação | Gerenciados pelo Studio, na mesma versão fixada do Godot |
| Build | Godot headless chamado pelo Build Manager, sobre a cópia em Build Staging (ADD §7) |
| Preview no Runtime | Usa o mesmo binário embutido, via WebSocket + JSON-RPC (RT §11) |
| Jogadores | Recebem o executável exportado, sem dependências |
| Desenvolvedores de runtime plugins | Únicos que usam o editor do Godot, para escrever e testar GDScript |
| Linguagem | Só GDScript nos plugins e no runtime. C# fica fora, porque o Godot 4 com C# não exporta para Web |
| Tamanho estimado do Studio | ~150–250 MB com Godot embutido |

**Bibliotecas do Studio** (aceitas em 2026-11-14): React Flow, Zustand + Immer, Ajv, CodeMirror/Monaco.

**Em aberto:** substituir o interpretador TypeScript do Preview no Studio pelo export Web (WASM) do runtime Godot, eliminando o segundo interpretador (RT §12). Próximo passo: um teste rápido do export Web dentro do Studio, medindo o tempo de recarga. Sandbox de runtime plugins não confiáveis (WASM ou Lua, v2).

## Decisões de 2026-11-12: jornada do autor sem programação

Saíram da análise da jornada de um roteirista ou artista, do download ao jogo exportado.

| Decisão | Onde |
|---|---|
| **IDs mistos:** cenas, capítulos, personagens, nós e opções usam UUID (v7, gerado pelo Studio, nunca exibido). Variáveis, `key` de personagem, expressões, grupos, finais, outcomes, assets, eventos e plugins mantêm nomes legíveis | DM §3, `common.schema.json → EntityId` |
| Personagem ganha `key` legível para as variáveis (`character.alice.affection`) | DM §3, `character.schema.json` |
| Tema do jogo em `theme.json` | DM §10.3, `theme.schema.json` |
| Finais declarados em `project.json → endings` (R012) | DM §8.2 |
| Metadados de exportação em `project.json → build` e assistente de exportação | Req §7 |
| Assets: formatos, `anchor`, `scale`, `nine_slice` | DM §10.1–10.2 |
| Explicação da seleção de cenas: `preview.explain_selection` e `scheduler.evaluated` | RT §11, Req §4 |
| Plugins: `outcome_labels`, `suggested_effects`, `plugin_locales`; permissões num único diálogo (W007, P010) | SDK §4.1, §6 |
| Mensagens de erro em linguagem simples, histórico de versões sem Git, planilha de tradução, importação de roteiro | Req §6, §8–10 |

## Decisões de 2026-11-12: jornada do dev de minijogos

Saíram da análise da jornada de quem desenvolve um minijogo, da instalação à publicação.

| Decisão | Onde |
|---|---|
| **Plugin devolve o resultado, a cena mapeia.** O Fishing Minigame não pede mais `variables.read/write`, `transactions` nem `variable_permissions`; as moedas viram `suggested_effects` e efeito da cena | SDK §4.4, §14, exemplo |
| **Variáveis de plugin aparecem como "do plugin X"** no Studio, somente leitura para o projeto (efeito sobre `plugin.*` é T002); `name` obrigatório na prática (W007) | DM §4.6, Req §5 |
| Repositório do plugin é um projeto Godot; o plugin fica em `vn_plugins/<namespace>/`, mesmo caminho `res://` no dev, no preview e no jogo (P012); sandbox `VNSandbox` | SDK §2.4 |
| Versão exata do Godot por versão do runtime; `vnplugin doctor` e `vnplugin godot install/open` | SDK §2.4, §13.1 |
| Prefixo do namespace em `class_name`, grupos e ações de input (P011); sem autoloads | SDK §2.4 |
| Depuração: `vnplugin link` (lock com `link: true`, sem hash, bloqueia exportação P013), modo desenvolvedor com depurador remoto do Godot e `preview.reload_plugins` | SDK §12.3, RT §11 |
| Testes: relógio virtual, `VNScriptedInput`, `VNPluginTest` | SDK §12.1 |
| `ctx.i18n.text` para textos ao jogador, traduzíveis pelo projeto; `ctx.theme`; ações de input padrão `vn_*`; tempo só por `delta` | SDK §5.7 |
| Permissão ligada à configuração (`$config.<campo>`, `format: vn-variable`) | SDK §4.4 |
| `compatibility.platforms` (W008); APIs do Godot vetadas (W009) | SDK §5.7, §12.2 |
| Publisher ligado à conta do GitHub, namespace reservado no catálogo, fluxo de publicação com diff de permissões e atualização expressa | SDK §13.2, §13.5 |
| Ao pular, o handle é encerrado antes de `_vn_cancel_activity` | SDK §6 |

## Decisões de 2026-11-13: build e proteção do conteúdo

| Decisão | Onde |
|---|---|
| **PCK embutido no executável** (Windows e Linux; macOS dentro do `.app`; Web separado por exigência da plataforma) | BS §7.2 |
| **Bundle em formato binário `.vnb`** nos builds de release: JSON canônico comprimido (Zstandard) e cifrado (AES-256-CBC desde 2026-11-14; era CTR), com `content_hash` no cabeçalho. O Preview continua com JSON | BS §5, RT §2 |
| **Detecção de modificação:** o runtime confere o `content_hash` de cada `.vnb`; saves e perfil levam assinatura HMAC (`integrity`), com política `ignore` / `flag` (padrão, liga `sys.save_modified`) / `reject` | BS §8.2–8.3, `save.schema.json`, DM §4.3 |
| **Criptografia do PCK como opção avançada**, desligada por padrão, com templates personalizados fornecidos pela equipe | BS §8.4 |
| Faixa `runtime.godot` do projeto é restrição; a versão exata vem do runtime do Studio (B014) | BS §2.1 |
| Só assets usados entram no jogo (B008); `always_include` para assets usados só por plugins | BS §6.1, `assets.schema.json` |
| Web exportado sem threads (sem exigir COOP/COEP); `build.locales` e `build.textures: lossy` para reduzir o download | BS §5.3, §6.2, §7.3 |
| Manifesto de build com versões e hashes de tudo; CLI `vnstudio build` para CI | BS §9, §11 |

## Decisões de 2026-11-14: revisão de lacunas

Saíram da revisão em [`reviews/revisao-specs-2026-11-13.md`](reviews/revisao-specs-2026-11-13.md); todas as sugestões foram aceitas.

| Decisão | Onde |
|---|---|
| **RNG reproduzível é opcional** e vem desligado (`settings.reproducible_rng`). Ligado: PCG32 com estado em hex no save, fluxo de RNG separado por atividade. Desligado: RNG comum do motor, nada no save, sorteios fora dos vetores de conformidade | RT §12.2, DM §6.1.1, `project.schema.json`, `save.schema.json` |
| Semântica de referência obrigatória para os dois interpretadores: tipos e resultados das funções, arredondamento, formatação numérica própria | DM §6.1.1, RT §12.1 |
| Minijogo pulado não aplica `on_result.effects`; campo ausente no payload usa `{result, default}` ou o padrão do tipo | RT §5.3, SDK §6, T005 |
| `choice` sem opção visível (e opção sem `goto`) segue `next`; opção ganha `value` para `record` | DM §8.2, `scene.schema.json`, R016 |
| Pedidos de cena só para o mesmo capítulo ou cena global; mudar de capítulo é `end_chapter` + `next` | DM §7, RT §4.3, R014 |
| Documento lógico do projeto para JSON Patch, com endereçamento por id (`@<id>`), `test` obrigatório e `ctx.ids` | SDK §10.4.1 |
| Atualização expressa no catálogo só sem mudança em `runtime/` (ou para oficiais), com 72 h de quarentena | SDK §13.5 |
| Save grava todas as variáveis `save`; `is_default` compara com o padrão efetivo; aliases `renamed_from` | RT §8.2–8.4, DM §5.1 e §12 |
| Falha por restrição (`reject`) não é erro de conteúdo; nó `effects` ganha `on_fail` | DM §6.2, RT §5.2 e §9 |
| Tabela de eventos `sys.*` com momento e payload; `sys.*` não entra em `events_since_selection` | RT §7 |
| Caminhos de tradução para textos fora das cenas, arquivos de locale por id, marcação de texto mínima | DM §9 e §9.1, R018 |
| Slots, Continuar, `settings.json` do jogador, perfil com *debounce*, backlog por caminho de texto | RT §8.5, `save.schema.json` |
| Ordem de chamadas aos plugins no load, com `_vn_load(null)` | RT §8.3, SDK §5.1 |
| Plugins: `default_locale` obrigatório, `config_migrations` declarativas, `VNSound` com `stop`, semântica de `input.capture` e de `PERMISSION_DENIED`, `WRONG_THREAD` | SDK §3–§8, RT §6 |
| Vínculos de desenvolvimento em `.vnstudio/plugin-lock.local.json`, fora do Git | SDK §12.3 |
| Build: versão do Godot normalizada para SemVer, compilação antes do staging, AES-256-CBC, exportar/importar chave de saves (B017), selfcheck em modo automático | BS §2.1, §3, §5, §8.1, §12 |
| Novos códigos: R014–R018, T005, P014–P016, W010–W016, B017 | DM §11, BS §13 |

## Decisões de 2026-11-14: segunda revisão

Saíram de [`reviews/revisao-specs-2026-11-14.md`](reviews/revisao-specs-2026-11-14.md); todas as sugestões foram aceitas.

| Decisão | Onde |
|---|---|
| **Godot 4.7.2** fixado pelo runtime 1.0 | BS §2.1, README |
| **Impressão digital da chave de saves no projeto** (`build.protection.save_key_id`, vai para o Git); a CLI nunca gera chave nova sozinha (`--new-save-key`) | BS §8.1, §11, `project.schema.json` |
| Plugins de editor não editam `/plugins`, `access` de variáveis nem dados de exportação (`FORBIDDEN_PATH`) | SDK §10.4.1 |
| RNG reproduzível (continua opcional): `handle.rng` por atividade, `ctx.rng` por plugin salvo em `rng.streams`, codificação da semente em bytes | RT §12.2, SDK §5.2 e §6, `save.schema.json` |
| Inteiros em ±(2^53 − 1) nos dois interpretadores (`OUT_OF_RANGE`); regra de `concat`, arredondamento da interpolação, JCS próprio | RT §6.2, §12.1; BS §5.1 |
| Pedido do conteúdo (`then.scene`) vem antes do fim de capítulo; pedido de plugin depois, guardado em `pending_request` | RT §4.3, `save.schema.json` |
| Ordem do load: plugins → `sys.game_started` → `sys.game_loaded` → retomar o nó | RT §8.3 |
| Autosave antes de atividade sempre; `scene_start` e nó `plugin` como pontos de save definidos | RT §5.3, §8.1 |
| `{result}` com tipo errado vale como ausente; `a.b` lê campo aninhado | DM §6.1, RT §5.3 |
| Escolha: `effects` + `record` numa transação; `cases` do `branch` ganham `id` | DM §6.2, §8.2 |
| Namespaces reservados; variáveis entre plugins só por dependência e só leitura | DM §3, §4.6, `common.schema.json` |
| Formatos `vn-asset`, `vn-scene`, `vn-character` em `config` e `params` | SDK §4.4 |
| Rótulos traduzíveis para valores de enum (`constraints.labels`) | DM §4.2, §9 |
| Acessibilidade mínima no v1 (tamanho do texto, menos movimento, legendas, alto contraste, menus por teclado/gamepad) | Req §12, `PlayerSettings`, `theme.colors.focus`, `audio.caption` |
| Android fora do v1 | `project.schema.json`, BS §7.2, §14 |
| Build de debug assina com chave fixa, nunca leva a `SAVE_KEY`; hash de todos os `.vnb` em `build_config` | BS §4.4, §8.2, §11.1 |
| Mensagens do runtime ao jogador (`G001`–`G005`) | BS §13.1 |
| Novos códigos: R019–R021, T006–T008, P017, P018, W017–W019 (84 casos em `test_validate.py`) | DM §11 |

## Decisões de 2026-11-14: menus, botões e idiomas

| Decisão | Onde |
|---|---|
| Telas do jogo são dados editados no **Menu Editor**: cada tela em `ui/<id>.json`, com elementos posicionados livremente (botão, imagem, texto, área clicável, slider, toggle, select, grades de save e galeria, backlog, container) | UI §2–§3, `ui-screen.schema.json` |
| Botões executam listas de **ações** (novo jogo, carregar, abrir tela, configurações, estados do cenário, sons, animações, `effects`, `emit`, URL, confirmação), com `if`/`else`; ações nunca escolhem cenas | UI §4 |
| **Estilos de botão** com nome no tema: imagem por estado, formas, fontes, efeitos de hover/press/foco, sons, animações prontas, `auto_shrink` para traduções | UI §7, `theme.schema.json` |
| **Cenários compostos** (`sets/`): camadas com estados e parallax, objetos clicáveis **cosméticos** no menu e nas cenas | UI §5, `set.schema.json` |
| Cliques que mudam a história só pelo nó **`interact`** (escolha espacial) | UI §6, DM §8.2, RT §5.2 |
| Configurações do jogador: volume por canal, modo de tela, resolução, VSync, **FPS da VN e FPS dos minijogos separados**, `min_fps` por atividade | UI §8, RT §5.3, `PlayerSettings`, `project.settings.display`, SDK `activities[].min_fps` |
| **Inglês como idioma principal** do Studio, do runtime e dos plugins oficiais; pt-BR, es, fr, it, de, ja, zh-Hans e zh-Hant secundários; outros por arquivo de tradução; RTL fora do v1 | Req §9.1, RT §12.1 |
| Novos códigos U001–U008 e W020; 104 casos em `test_validate.py` | UI §11 |
| **Protocolo do Preview** completo (E2) e **vetores de conformidade** com implementação de referência (E3); regras fixadas: divisão por zero é `OUT_OF_RANGE`, arredondamento sobre a representação decimal mais curta, semeadura do PCG32, `random_int` por rejeição, `weighted_pick` em ponto flutuante | spec 07, spec 08, RT §4.3, §12.1, §12.2 |

**Ainda em aberto** (ver a seção "O que falta" do relatório): escopo da galeria (a spec 06 já prevê `gallery_grid` com finais, imagens e músicas; falta decidir se imagens e músicas entram no v1 e como o perfil registra o que foi visto), quem opera o catálogo, nome e domínio definitivos, e os documentos E1 e E4–E15 (E2 e E3 já estão nas specs 07 e 08).

## Desvios em relação ao ADD

1. **Referências de variáveis sempre qualificadas** (`global.player_money`), inclusive nas permissões de plugins. O ADD usa às vezes o nome curto (`player_money`); o Studio pode exibi-lo assim, mas grava o ID completo.
2. **Plugin tem `id` global e `namespace` curto separados** (`vnstudio.fishing` / `fishing`). O ADD não distingue.
3. **`chapter.completed` virou `sys.chapters.<id>.completed`**, porque variáveis `chapter.*` deixam de existir ao sair do capítulo.
4. **Inventário fora do modelo de variáveis**: listas/conjuntos ficam para v1.1 ou para o plugin de inventário.
5. **Nada de GDExtension em plugins no v1**, para manter a distribuição revisável por código-fonte.
6. **Web entra como plataforma do v1** (exportação sem threads). O ADD §7.5 cita só Windows, Linux, macOS e Android. **Android fica fora do v1** (decisão de 2026-11-14).
