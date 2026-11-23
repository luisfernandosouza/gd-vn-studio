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
| 8 | [Vetores de conformidade](08-conformance-vectors.md) | Formato dos casos que o Runtime e o Preview do Studio DEVEM reproduzir, conjunto de 142 casos (inclusive recordes, fluxo de cenas inteiras e modo stream), vetores de compilação e implementações de referência |
| 9 | [Repositórios e organização do código](09-repositories-and-code-layout.md) | Onde cada coisa mora no Git: monorepo do produto, repositório de plugin avulso e repositório de um jogo (plugins do catálogo, guardados e embutidos), `.gitignore`, onde os dados dos minijogos ficam no computador do jogador |

Artefatos:

- `schemas/` — 22 JSON Schemas (draft 2020-12): `common`, `project`, `variables`, `character`, `chapter`, `scene`, `assets`, `locale`, `save`, `plugin`, `plugins`, `plugin-lock`, `theme`, `ui-screen`, `set`, `preview-protocol`, `conformance`, `build-manifest` e os quatro do bundle compilado (`bundle`, `bundle-locale`, `bundle-plugins`, `bundle-licenses`). O `$id` de cada schema é `https://schemas.vnstudio.dev/specs-v1.0.0/<nome>.schema.json`, o endereço da versão `specs-v1.0.0` (decisão D13, spec 09 §1).
- `examples/demo-project/` — dados de exemplo, só JSON e sem arte (o jogo jogável fica num repositório separado, spec 09 §1.1): projeto pequeno com 2 capítulos, 5 cenas, escolhas, branch, variável derivada, grupo de exclusividade, uso do Fishing Minigame, menu inicial com cenário clicável (`ui/title.json`, `sets/beach_title.json`), tela de configurações com FPS separado para VN e minijogos (`ui/settings.json`), créditos e um nó `interact`. É a cópia dos JSON da demo, sem o campo `credit` dos assets (spec 09 §1.1).
- `presets/classic/` — preset de interface do v1: tema, as telas que o projeto não define (título, pausa, salvar, carregar, configurações, galeria, créditos, HUD, histórico e minijogos) e os textos traduzidos para os 9 idiomas do produto (UI Spec §2.1).
- `examples/fishing-plugin/` — plugin de referência completo: manifesto, GDScript de runtime, cena, testes com `VNTestHarness`, comando de editor, README e CHANGELOG. Corresponde a `vn_plugins/fishing/` do projeto de desenvolvimento.
- `examples/demo-save.json` — save válido, coerente com um caminho real do demo (chegada → praia → pescaria vencida) e assinado com uma chave de exemplo de 32 bytes zero.
- `tools/validate.py` — validador de referência (schema + regras semânticas).
- `tools/test_validate.py` — um projeto quebrado de propósito para cada código do validador.
- `tools/test_schemas.py` — confere os padrões dos schemas (chaves de tradução, id de plugin, mensagens do Preview) contra os formatos que as specs mandam gravar.
- `conformance/` e `tools/conformance.py` — vetores de conformidade e a implementação de referência que os confere.
- `tools/compile_bundle.py` — compilador de referência do bundle narrativo (BS §5.1): transforma um projeto na forma que o runtime lê, sem precisar do Studio (RT §2.1).
- `conformance/compile/` e `tools/test_compile.py` — vetores de compilação: variações de um projeto congelado (`conformance/compile/base/`) com o `content_hash` esperado, que o compilador do Studio também DEVE reproduzir (BS §5.1, spec 08).
- `tools/sync_demo_example.py` e `examples/demo-project/SOURCE.json` — gera o exemplo a partir do repositório da demo, sem os créditos de terceiros, e confere a cópia na CI (`.github/workflows/specs.yml`, spec 09 §1.1).
- `.github/workflows/repo-hygiene.yml` — recusa arte, áudio e vídeo fora das pastas permitidas do repositório do produto (spec 09 §1.1).

```bash
pip install jsonschema
python3 tools/validate.py examples/demo-project examples/fishing-plugin
# 0 erro(s), 0 aviso(s).
# --export aplica também as regras de exportação (P013, W013 vira erro)
python3 tools/test_validate.py
# um caso por código; todos devem passar
python3 tools/test_schemas.py
# padrões dos schemas contra os exemplos das specs
python3 tools/conformance.py
# 142/142 vetores conferem com a referência.
python3 tools/test_compile.py
# 8/8 vetores de compilação conferem.
python3 tools/compile_bundle.py examples/demo-project /tmp/demo-bundle examples/fishing-plugin
# grava bundle.json, locales/<lang>.json, plugins.json e licenses.json; --stage copia também assets e plugins;
# --godot <projeto-godot> grava em vn_content/ e vn_plugins/ do projeto do runtime
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
| Comunicação com Godot / sincronização do preview | **Decidido (2026-11-16):** o runtime Godot é o único interpretador. Painel com o export Web e ponte JavaScript; janela nativa com WebSocket local + token. JSON-RPC 2.0 nos dois, com recarga incremental | RT §11, PP |
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

Build Staging (BS §4), conteúdo do PCK (BS §4.2, §7.2), reprodutibilidade e cache (BS §10). **Em aberto:** conteúdo externo, DLC e atualizações parciais (BS §14), catálogo de terceiros e publicação comunitária, que ficam para o v2 (D11, SDK §13.2).

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
| Preview | Um interpretador só, o runtime: no painel do Studio, o export Web do runtime; na janela, o binário embutido. Mesmo JSON-RPC nos dois (RT §11, decisão de 2026-11-15, encerrada em 2026-11-16 depois do teste no macOS) |
| Jogadores | Recebem o executável exportado, sem dependências |
| Desenvolvedores de runtime plugins | Únicos que usam o editor do Godot, para escrever e testar GDScript |
| Linguagem | Só GDScript nos plugins e no runtime. C# fica fora, porque o Godot 4 com C# não exporta para Web |
| Tamanho estimado do Studio | ~150–250 MB com Godot embutido |

**Bibliotecas do Studio** (aceitas em 2026-11-14): React Flow, Zustand + Immer, Ajv, CodeMirror/Monaco.

**Em aberto:** sandbox de runtime plugins não confiáveis (WASM ou Lua, v2).

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

Saíram da revisão em [`../reviews/revisao-specs-2026-11-13.md`](../reviews/revisao-specs-2026-11-13.md); todas as sugestões foram aceitas.

| Decisão | Onde |
|---|---|
| **RNG reproduzível é opcional** e vem desligado (`settings.reproducible_rng`). Ligado: PCG32 com estado em hex no save, fluxo de RNG separado por atividade. Desligado: RNG comum do motor, nada no save, sorteios fora dos vetores de conformidade | RT §12.2, DM §6.1.1, `project.schema.json`, `save.schema.json` |
| Semântica de referência obrigatória para o runtime e a referência: tipos e resultados das funções, arredondamento, formatação numérica própria | DM §6.1.1, RT §12.1 |
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

Saíram de [`../reviews/revisao-specs-2026-11-14.md`](../reviews/revisao-specs-2026-11-14.md); todas as sugestões foram aceitas.

| Decisão | Onde |
|---|---|
| **Godot 4.7.2** fixado pelo runtime 1.0 | BS §2.1, README |
| **Impressão digital da chave de saves no projeto** (`build.protection.save_key_id`, vai para o Git); a CLI nunca gera chave nova sozinha (`--new-save-key`) | BS §8.1, §11, `project.schema.json` |
| Plugins de editor não editam `/plugins`, `access` de variáveis nem dados de exportação (`FORBIDDEN_PATH`) | SDK §10.4.1 |
| RNG reproduzível (continua opcional): `handle.rng` por atividade, `ctx.rng` por plugin salvo em `rng.streams`, codificação da semente em bytes | RT §12.2, SDK §5.2 e §6, `save.schema.json` |
| Inteiros em ±(2^53 − 1) (`OUT_OF_RANGE`); regra de `concat`, arredondamento da interpolação, JCS próprio | RT §6.2, §12.1; BS §5.1 |
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

## Decisões de 2026-11-14: minijogos no repositório, perfil e recordes

| Decisão | Onde |
|---|---|
| **Monorepo do produto** (`docs/specs`, `studio`, `runtime`, `sdk`, `cli`, `plugins`), com tags por componente | spec 09 §1 |
| **Plugins no repositório do jogo:** catálogo e GitHub só por referência; pacote guardado em `vendor/plugins/`; **minijogo embutido** em `plugins/<nome>/`, versionado com o jogo e empacotado no build | spec 09 §3, `plugins.schema.json`, `plugin-lock.schema.json` (`embedded`), BS §3.2, SDK §2.4 |
| **Dados de perfil e recordes por plugin** (`ctx.profile`, capacidade `profile.data`, `records` no manifesto), em `profile.json → plugins.<namespace>` | SDK §9.1, `save.schema.json`, `plugin.schema.json` |
| **Modo livre** de minijogos a partir do menu (`free_play`, ação `play_activity`, elemento `records_list`), sem mexer na história | SDK §6.1, RT §5.3, UI §3.1, §4 |
| Novos códigos P019–P021; 112 casos em `test_validate.py` | DM §11, spec 09 §5 |

**Ainda em aberto** (ver a seção "O que falta" do relatório): ~~escopo da galeria~~ (resolvido em 2026-11-16: galeria opcional por projeto, DM §10.5), ~~quem opera o catálogo~~ (resolvido em 2026-11-22: só o índice oficial no v1, D11), ~~nome e domínio definitivos~~ (resolvido em 2026-11-22, D13), e os documentos E1 e E4–E15 (E2 e E3 já estão nas specs 07 e 08).

## Decisões de 2026-11-14: antes do runtime (3ª e 4ª revisões)

| Decisão | Onde |
|---|---|
| **Idiomas: o jogo tem de 1 a n idiomas**, com qualquer tag BCP 47; o Studio, o preset e as mensagens do runtime têm uma lista fixa (en, pt-BR, es, fr, it, de, ja, zh-Hans, zh-Hant). Idioma do jogo fora da lista recebe os textos prontos em inglês até o autor traduzi-los (W021); `settings.number_formats` formata números de qualquer idioma | Req §9.1, DM §9, RT §12.1, UI §2.1 |
| **Formato do bundle** com schema e **compilador de referência em Python**; o compilador grava o jogo e os plugins dentro do projeto do runtime (`--godot`) e o editor do Godot roda a demo sem o Studio nem o catálogo (D16, D17) | RT §2, §2.1, BS §5.1, `bundle*.schema.json`, `tools/compile_bundle.py` |
| **Preset `classic` como arquivos**, inclusive as telas `backlog` e `minigames` (gerada a partir de `free_play`) | UI §2.1, `presets/classic/` |
| **Padrões do `PlayerSettings`** e fim do campo `fullscreen` (só `display_mode`) | UI §8, `save.schema.json` |
| **Boot, camadas de desenho, escala, digitação, miniatura, chave de desenvolvimento e ações de input** | RT §1.1, §2.1, §3.0, §5.2, §8.5, §10.1 |
| **Galeria de imagens e músicas no v1** (D5): `gallery: true` em `assets.json` e `profile.seen_assets` | DM §10.2, UI §3.1, RT §5.2 |
| **Modo livre só fora da partida** (D14), com `sys.ui.last_activity_outcome` e `sys.ui.last_record_rank` ao voltar | RT §5.3, UI §3.2, §4, SDK §6.1 |
| **Repositório privado do GitHub** como origem de plugin, com token no chaveiro do sistema (D15) | spec 09 §3.1 |
| Ação `reset_profile`, elemento `licenses_list`, mensagem G006, formato de exibição dos recordes, dados órfãos de plugin | UI §3.1, §4, BS §13.1, SDK §9.1 |
| Vetores `record` e `flow`; códigos W021–W023 e U009–U011; 119 casos em `test_validate.py` | spec 08, DM §11, UI §11 |
| `build-manifest.schema.json` | BS §9.2 |

**Ainda em aberto:** ~~quem opera o catálogo~~ (D11, resolvida em 2026-11-22), ~~nome e domínio definitivos~~ (D13 resolvida em 2026-11-22, ver abaixo) e os documentos E4–E7 e E9–E15.

## Decisões de 2026-11-15: correções da auditoria documental

Aplicam os achados A-01, A-02, A-03, A-04 e M-02 da auditoria de 2026-11-14.

| Decisão | Onde |
|---|---|
| **Escala com `stretch_aspect = expand`** em todo lugar: o BS §4.3 dizia `keep`, o RT §1.1 já dizia `expand` (A-01) | BS §4.3 |
| **Ordem dos plugins no boot**: topológica de dependências, empate pela ordem lexicográfica do id; o RT §3.0 e §12.1 diziam "ordem das chaves" (A-02) | RT §3.0, §12.1, SDK §5.1 |
| **Chaves de tradução aceitam ponto e maiúsculas depois do primeiro segmento**, para `variable/global.mood/value/calm` e `ui/<tela>/<elemento>/option/pt-BR` (A-03) | `locale.schema.json` |
| **Id de plugin aceita `_`**, para o `<id do projeto>.<nome>` recomendado (`seaside_story.quiz`) (M-02) | `plugin.schema.json`, `plugins.schema.json`, `plugin-lock.schema.json` |
| **Vetores de JCS e HMAC** (`canonical.json`, 7 casos); o JCS de referência fica só em `conformance.py` e o compilador o importa (A-04) | spec 08, BS §5.1, RT §12.1 |
| `tools/test_schemas.py`: padrões dos schemas conferidos contra os exemplos das specs | este README |

## Decisões de 2026-11-15: um interpretador só no Preview

O Preview no Studio deixa de ter um interpretador próprio em TypeScript. O Studio roda o **próprio runtime**, exportado para Web, num painel do webview; o runtime nativo, numa janela, continua para o modo desenvolvedor e para plugins sem `web`. Assim o autor vê exatamente o jogo do jogador e não há um segundo interpretador para manter igual.

**Encerrada em 2026-11-16.** O resultado do teste no macOS (WKWebView, o motor do Tauri no Mac, na tabela abaixo) foi considerado suficiente, e fica decidido usar só o runtime Godot como interpretador. O teste num Mac físico não é necessário para a decisão. A decisão está tomada, mas ficaram pendências técnicas, que a revisão de 2026-11-17 apontou: como os assets e os plugins chegam ao Preview (D18) e os itens de "A conferir" abaixo.

A decisão saiu do teste do export Web dentro dos webviews do Tauri (`spikes/preview-web/`, pasta temporária, apagada quando o projeto do Studio começou, na tarefa M0-05; o código e os resultados ficam no histórico do Git), com um bundle grande (405 cenas, 20 mil falas, 3,55 MB) e o template oficial:

| Motor (máquina) | Primeira abertura | Recarga incremental, p95 | Reler o bundle inteiro, p95 |
|---|---|---|---|
| Edge, o motor do WebView2 (Windows, RTX 3060) | 4,7 s | 4,6 ms | 0,99 s |
| WKWebView (macOS, runner do GitHub) | 3,6 s | 18 ms | 1,34 s |
| WebKit (macOS) | 2,0 s | 24 ms | 1,31 s |
| Chromium (macOS) | 3,0 s | 18 ms | 1,44 s |
| Chromium (Linux, sem GPU) | 1,2 s | 20 ms | 2,06 s |
| WebKitGTK 4.1 (Linux, sem GPU) | 3,4 s | 40 ms | 2,44 s |

A primeira abertura é sem cache; com o motor já compilado em cache, cai para 0,3 a 1,1 s no Chromium, no Edge e no WebKit do macOS. O WebKitGTK recompila o WASM a cada abertura. O minijogo de pesca do exemplo rodou com o GDScript real, abrindo em 5 a 155 ms (p95).

| Decisão | Onde |
|---|---|
| **Runtime como único interpretador.** Painel (export Web, padrão) e janela (nativo), com o mesmo JSON-RPC; a referência em Python só confere o runtime | RT intro, §11, §12; spec 08 |
| **Ponte JavaScript no painel**: `vnPreview.send` / `vnPreview.onmessage`, sem token; WebSocket com token só na janela | PP §1 |
| **Recarga incremental na memória**: `preview.reload({patch})` troca só as entidades compiladas que mudaram, sem reler o bundle nem recalcular o `content_hash`; a recarga completa fica para projeto, variáveis e plugins | PP §3, RT §11 |
| **Sem mock de atividade**: sai `renderActivityMock` do Editor SDK; a atividade roda o GDScript real. Plugin sem `web` mostra um formulário do `result_schema` e conclui com `complete_activity`, ou abre em janela | SDK §10.3, §10.6; PP §3 |
| **Vetores no runtime nativo e no Web**; sai a suíte do interpretador do Studio e a pasta `studio/interpreter/` | spec 08 §4, spec 09 |
| O plugin de exemplo troca o mock por um comando que abre o Preview no nó de pescaria | `examples/fishing-plugin/` |

**A conferir no primeiro protótipo** (antes de começar o Studio):

- **Teste B dos assets** (D18): abrir no painel 200 imagens de 1920 × 1080 e 30 músicas pelo carregador de bytes, medir memória e tempo, e trocar um asset em uso (PP §1.3).
- **Servir por `vnpreview://`** (conferido em 2026-11-23, ver as decisões daquela data): o spike usou HTTP; conferir o export servido pelo protocolo próprio do Tauri, com `application/wasm`, no WebView2, na WKWebView e no WebKitGTK (PP §1.1).
- **Plugins como `.pck`** (conferido em 2026-11-23): recarregar um plugin no painel trocando o seu `.pck` (`ProjectSettings.load_resource_pack`); conferir que scripts com `class_name` funcionam num pacote montado depois do boot; e medir o tempo de gerar o `.pck` com o Godot embutido headless a cada salvamento (PP §1.3, SDK §10.6).
- O tempo de abrir o painel com o template enxuto (o teste indicou cerca de 30% menos). Medido em 2026-11-23; a escolha do template está com o Luis.

## Decisões de 2026-11-15: modo stream (versão censurada)

| Decisão | Onde |
|---|---|
| **Só a apresentação muda, nunca a história.** Com o modo ligado, a cena roda inteira com outras imagens, sons e falas; escolhas, efeitos, desvios, minijogos e fim são os mesmos. O modo liga e desliga a qualquer momento e os saves valem nos dois | DM §10.4, RT §5.5 |
| **Três níveis de marcação:** asset (`censored.replace_with` ou `hide`, vale em todo lugar), texto (`censored_text`, `censored_prompt`, com tradução `…/censored`) e passo de apresentação (`censor: skip`/`only`) | DM §8.2, §9, §10.4, `assets.schema.json`, `scene.schema.json` |
| **Configuração do jogador `content_filter`**, com controle no preset, `project.json → content_filter` (`default`, `ask_on_first_launch`, `placeholder`) e o evento `sys.content_filter_changed` | UI §8, RT §3.0, §7.1, `save.schema.json`, `project.schema.json` |
| **Saves, galeria e backlog:** o palco é salvo com os ids originais; miniatura sensível vira placeholder; ver a versão censurada desbloqueia o item da galeria; ler a versão censurada conta como lido | RT §5.2, §5.5, §8.2, §8.5, UI §3.1 |
| **Minijogos:** assets do projeto chegam filtrados ao plugin; para o conteúdo próprio, `ctx.content_filter` e `"content_filter": "supported"` no manifesto | SDK §5.2, §5.6, `plugin.schema.json` |
| **Edição censurada** (`build.edition: censored`, `--edition censored`): filtro sempre ligado e originais fora do pacote | BS §5.4, §11, `tools/compile_bundle.py` |
| Códigos R022–R024 e W024; 127 casos em `test_validate.py`; 2 vetores `flow` novos | DM §11, spec 08 |

## Decisões de 2026-11-16: Preview encerrado e galeria opcional

| Decisão | Onde |
|---|---|
| **Preview: só o runtime Godot como interpretador.** O teste no macOS (WKWebView) foi suficiente; a decisão de 2026-11-15 está encerrada. As pendências técnicas (assets, plugins e `vnpreview://`) estão na seção de 2026-11-17 | RT §11, ADD §3.3 (nota), seção de 2026-11-15 acima |
| **Galeria opcional por projeto.** O autor liga a galeria e escolhe as seções em `project.json → gallery.sections` (`endings`, `images`, `music`); projeto novo começa sem galeria. Imagens e músicas entram uma a uma com `gallery: true` | DM §10.5, `project.schema.json`, Req §11.1 |
| **Sem galeria, nada aparece:** o compilador tira a tela `gallery`, o botão do título some (`sys.ui.has_gallery`) e as abas mostram só as seções ativas (`sys.ui.gallery_*`) | UI §2.1, §3.2, BS §5.1, `presets/classic/ui/gallery.json`, `title.json`, `tools/compile_bundle.py` |
| **Registro do que foi visto:** finais em `profile.endings` (sempre, com ou sem galeria); imagens e músicas em `profile.seen_assets` (sempre, desde D20 de 2026-11-17), só por nós `background` e `audio` de cenas, também no modo pular, ao carregar save e com o modo stream (marca o original) | RT §5.2, `save.schema.json` |
| Códigos U011 (revisto), U012–U014; 130 casos em `test_validate.py`; a demo liga as três seções | UI §11, `examples/demo-project/` |

## Decisões de 2026-11-17: revisão das bordas do Preview, do modo stream e da galeria

Aplicam os achados N-01 a N-20 da [revisão de 2026-11-17](../reviews/revisao-specs-2026-11-17.md) e as decisões D18 a D21, aceitas pelo Luis.

| Decisão | Onde |
|---|---|
| **D18. Assets no Preview por bytes.** O bundle do Preview aponta cada asset para o arquivo do autor (`vnpreview://` no painel, `file://` na janela); o runtime cria texturas, sons e fontes em memória e aplica ele mesmo as opções de import. O Preview mostra o mesmo que o jogo, salvo compressão, tempo e memória. Falta o teste B (acima) | PP §1.3, RT §2, §11, `bundle.schema.json` |
| **D19. O palco lembra o `censor` de cada item.** Ao mudar o modo stream, ou ao carregar, o que um passo `skip`/`only` pôs no palco some se o passo não valeria no modo atual; o cenário volta ao último sem marca (`background_base`) | RT §5.5, §8.2, §8.3, DM §10.4, `save.schema.json → Stage`, vetor `modo_stream_ligado_no_meio` |
| **D20. A galeria registra sempre.** `profile.seen_assets` guarda as imagens e músicas vistas com ou sem galeria; a tela filtra ao mostrar. Uma galeria que chega numa atualização já vem preenchida | DM §10.5, RT §5.2, Req §11.1 |
| **D21. Saves do Preview em memória.** Por padrão nada sobrevive ao fechar o Preview; "Manter saves do Preview" grava por projeto em `.vnstudio/preview/user/` (`preview.load` com `user_data: "project"`) | PP §1.4, spec 09 §3.4 |
| **R022 também nas telas:** `sys.ui.content_filter*` não pode decidir uma ação `effects` ou `emit` (`if`, valores, `visible_if`/`enabled_if` de quem a dispara) | DM §10.4, §11, UI §11, `tools/validate.py` |
| **Mais textos com versão censurada:** `censored_caption` em `audio` (a legenda segue o asset) e `censored_label` em hotspots e no `exit`; nomes, títulos de capítulo e de final ficam sem versão e devem ser neutros | DM §10.4, RT §5.5, BS §5.4, `scene.schema.json` |
| **Minijogos:** o modo stream NÃO DEVE mudar `outcome`, `payload`, escritas nem eventos; item na revisão do catálogo e `content_filter` no `VNTestHarness` | SDK §5.6, §12.1, §13.4 |
| **Preview do modo stream e da galeria:** `preview.set_setting`, `content_filter` em `preview.start` e mais campos em `simulate` (`content_filter`, `content_filter_available`, `last_activity_outcome`, `last_record_rank`, `seen_assets`, `gallery_unlock_all`); passos pulados pelo modo não geram `node.entered` | PP §3, §4, `preview-protocol.schema.json`, Req §11.1, §11.2 |
| **Runtime do Preview embutido no Studio:** o export Web e o `runtime-preview.pck` saem da release do runtime e funcionam sem internet, separados dos templates de exportação | PP §1.1, §1.2, RT §11, spec 09 §1 |
| **Vetores de compilação** (`conformance/compile/`, 7 casos) e a regra de equivalência incremental na CI do Studio | BS §5.1, spec 08, `tools/test_compile.py` |
| **Edição censurada:** asset com `hide` sai da galeria; rótulos e legendas censurados entram no lugar dos originais | BS §5.4, `tools/compile_bundle.py` |
| **Pergunta da primeira abertura:** a resposta é sempre gravada em `settings.json`, mesmo igual ao padrão | RT §3.0, §8.5 |
| **Uma fonte para a demo:** o repositório da demo é a fonte; `examples/demo-project/` é a cópia só com os JSON | spec 09 §1.1 |
| Código W025 (fala censurada com voz sem `censored`); DM §11 passa a citar U001–U014; 133 casos em `test_validate.py`; 138 vetores; redação de `gallery_grid` (UI §3.1) e do Req §11.1 | DM §11, UI §3.1, Req §11.1 |

## Decisões de 2026-11-22: demo, créditos, assets de teste e bordas do modo stream e do Preview

Aplicam os achados V-01 a V-14 da [revisão de 2026-11-22](../reviews/revisao-specs-2026-11-22.md) e as decisões D22 e D23, aceitas pelo Luis.

| Decisão | Onde |
|---|---|
| **D22. Assets de teste são internos.** Não aparecem para o jogador, não têm crédito e não existem em nenhum artefato distribuído. Arte de terceiros, mesmo para teste, só entra pela demo, em testes de ponta a ponta que a clonam numa versão fixa | spec 09 §1.1, §1.2 |
| **D23. O exemplo é a cópia filtrada da demo.** `tools/sync_demo_example.py` copia os JSON da demo no commit de `SOURCE.json` e tira só o campo `credit`; a workflow `specs.yml` roda as ferramentas e confere a cópia em todo PR | spec 09 §1.1, `.github/workflows/specs.yml` |
| **Vetores de compilação num projeto congelado** (`conformance/compile/base/`), que não acompanha o exemplo; 8 casos, inclusive `credit` fora do bundle | BS §5.1, spec 08 |
| **Créditos de terceiros no asset:** campo `credit` em `assets.json`; o Build System reúne em `licenses.txt` só os créditos dos assets que entram no jogo; `licenses_list` ganha `assets`; U009 avisa; o Asset Manager pergunta a origem ao importar. `credit` não entra no bundle nem no `content_hash` | DM §10.1, BS §4.5, UI §3.1, §11, Req §11.3, `assets.schema.json` |
| **Conteúdo dos artefatos:** o que entra em cada artefato do produto e o que nunca entra (`tests/`, `docs/`, `spikes/`, a demo); `exclude_filter` nas exportações do runtime e conferência na CI de release | spec 09 §1.2 |
| **Palco do modo stream com base por item** (completa D19): personagem e canal voltam ao estado anterior ao passo censurado (expressão, música), e o cenário pode voltar a um set. `censor` não vale mais em `hide` nem em `audio` sem `play` (R023). 2 vetores novos | RT §5.5, DM §10.4, §11, `save.schema.json → Stage`, spec 08 |
| **Caminhos do bundle do Preview relativos** (ajusta D18): `preview.load` traz `assets_base`, que o Studio obtém do Tauri em cada sistema (no Windows, `http://vnpreview.localhost/…`); o bundle do build só aceita `res://`, e o selfcheck recusa o resto (B018) | PP §1.3, §3, RT §2, §11, BS §12, §13, `bundle.schema.json`, `preview-protocol.schema.json` |
| **`VNStorage`** (ajusta D21): o Save Manager grava por uma interface com três implementações (`user://`, memória, pasta); no painel, a pasta é `user://preview/<project.id>/`; plugins não abrem `user://` direto (W009) | RT §8.5, §11, PP §1.4, SDK §12.2 |
| **R022 em containers:** a guarda do modo stream num `container` vale para os botões dentro dele | DM §10.4, UI §11, `tools/validate.py` |
| **Demo:** cenários do Noraneko com a versão do modo stream gerada por script (`bg/train_evening_safe`), créditos no campo `credit` (Noraneko Games nos cenários e sutemo na Alice), textos que combinam com o trem; o final "Noite de festival" continua sem asset próprio | repositório `gd-vn-studio-demo`, `examples/demo-project/` |
| 137 casos em `test_validate.py`, 39 em `test_schemas.py`, 140 vetores, 8 vetores de compilação | spec 08, este README |

### Itens antigos da auditoria de 2026-11-14 (M-01, M-04, M-05, M-06)

Corrigidos na mesma data, com a aprovação do Luis.

| Decisão | Onde |
|---|---|
| **M-01.** Hash de `.vnb` diferente mostra G002; G001 fica para bundle ausente, que não decodifica ou com versão de formato não suportada | RT §3.0, BS §8.2, §13.1 |
| **M-04.** O runtime não confere o código dos plugins: o `integrity` é do pacote `.vnplugin` e só o Build System o confere (B002); no jogo, os scripts ficam no PCK com as mesmas proteções dos do runtime, e o `plugins.vnb` é conferido pelo `content_hash` | RT §2.1, §3.0, §9, spec 09 §3.1 |
| **M-05.** O preset é escolhido em `theme.json → preset`, e o schema só aceita `classic` no v1; um nome desconhecido é erro de validação | RT §2, DM §10.3, UI §2.1, `theme.schema.json` |
| **M-06.** `sys.ui.last_activity_outcome` vale o `outcome` do `complete`, `failed` ou `cancelled` (nomes reservados nos `outcomes`). No modo livre, `vn_menu` (Esc, Start) é sempre do runtime e pergunta "Sair do minijogo?" (`runtime/confirm/quit_activity`); sair dá `cancelled` | SDK §6, §6.1, RT §5.3, §10.1, DM §4.3, UI §3.2, `plugin.schema.json`, preset `classic` |
| 139 casos em `test_validate.py`; hashes de idioma dos vetores de compilação regerados (texto novo do preset) | spec 08, este README |

## Decisões de 2026-11-22: segunda revisão (licenças, Preview e minijogos)

Aplicam os achados X-01 a X-13 da [segunda revisão de 2026-11-22](../reviews/revisao-specs-2026-11-22-2.md) e as decisões D24, D25 e D26, aceitas pelo Luis com as opções recomendadas. Algumas linhas mudam decisões da seção anterior, que fica como histórico.

| Decisão | Onde |
|---|---|
| **D24. O bundle do Preview é o mesmo do build** (desfaz os caminhos relativos): os assets ficam em `res://vn_content/assets/…`, e em modo preview o runtime troca esse prefixo por `assets_base`. O `content_hash` do Preview e o do jogo são iguais, e `bundle.schema.json` volta a exigir `res://` | PP §1.3, RT §2, §11, BS §12, `bundle.schema.json`, `preview-protocol.schema.json` |
| **D25. Os saves mantidos do Preview ficam em `.vnstudio/preview/user/` nos dois modos.** Na janela, por `--vn-user-dir`; no painel, o runtime manda `storage.write`/`storage.delete` e o Studio grava, e `preview.load` traz `user_files`. Nada do Preview fica em `user://` | PP §1.2, §1.4, §4, RT §8.5, §11 |
| **D26. `vn_menu` é sempre do runtime durante um minijogo**, nos dois modos: na história abre a pausa (salvar, carregar, configurações, título e "Pular minijogo" com `skippable`, ação `skip_activity`, `sys.ui.activity_skippable`); no modo livre pergunta "Sair do minijogo?" | SDK §4.2, §6.1, RT §5.3, §10.1, UI §3.2, §4, DM §4.3, preset `classic` (`pause`, 9 idiomas) |
| **Aviso de licença do motor em todo jogo:** o runtime mostra sempre a licença do Godot, das bibliotecas dele, do runtime e das fontes do preset (`licenses_list.include` ganha `engine`); U009 vira erro na exportação quando a tela de créditos não tem `licenses_list` | BS §4.5, UI §3.1, §11, spec 09 §1.2, `ui-screen.schema.json` |
| **`licenses.json` no bundle** (no lugar de `licenses.txt`; `licenses.vnb` em release, com hash): plugins e créditos de assets agrupados, com schema. Vale também no Preview e na recarga incremental. `credit` ganha `license_file` (fecha o B-20 da auditoria: as fontes OFL levam o texto da licença); `license` e `notice` não se traduzem | BS §4.5, §7.1, RT §2, DM §10.1, Req §11.3, PP §3, `bundle-licenses.schema.json`, `assets.schema.json`, `tools/compile_bundle.py` |
| **O protocolo `vnpreview` serve só o projeto aberto** (`/runtime/`, `/project/assets/`, `/project/preview/`), sem caminho absoluto na URL; o runtime codifica os segmentos do caminho no painel | PP §1.1, §1.3 |
| **W009 em tabela**, com `JavaScriptBridge`, `JavaScriptObject`, gravação em `user://` (`ConfigFile`, `ResourceSaver`, `Image.save_*`, `OS.get_user_data_dir`) e `PROCESS_MODE_ALWAYS` | SDK §12.2, PP §1.1, RT §8.5, `tools/validate.py` |
| **Base do palco = estado imediatamente antes do passo censurado:** `hide` e `stop` apagam a base; a base guarda a posição; com um set, `background` é `null`. 2 vetores novos | RT §5.5, DM §10.4, `save.schema.json`, spec 08, `tools/conformance.py` |
| **Modo livre pelo Preview:** `preview.input` com `play_activity` em `LOADED`; `skip_activity` e `cancel_activity` definidos; `activity.*` com `mode` | PP §3, §4 |
| **Mídia no repositório do produto:** lista fechada de pastas e a workflow `repo-hygiene.yml`; `docs/` não entra nos artefatos, salvo schemas e presets copiados | spec 09 §1.1, §1.2 |
| **Cópia da demo:** o script e a CI usam a mesma lista de arquivos, a comparação é byte a byte, o script confere o commit (`--update-source` para trocar), e a demo ganha uma workflow diária contra a `main` do produto (`PRODUCT_REPO_TOKEN`) | spec 09 §1.1, `tools/sync_demo_example.py`, `.github/workflows/specs.yml` |
| 144 casos em `test_validate.py`, 48 em `test_schemas.py`, 142 vetores, 8 vetores de compilação (com o hash de `licenses.json`; hashes regerados pelo texto novo do preset) | spec 08, este README |

## Decisões de 2026-11-22: nome, domínio e `$id` dos schemas (D13)

Fecha a decisão D13 da [revisão de 2026-11-14](../reviews/revisao-specs-2026-11-14.md), aberta desde então.

| Decisão | Onde |
|---|---|
| **Nome e domínio ficam como estão:** produto Visual Novel Studio, publisher oficial `vnstudio`, pacotes `@vnstudio/*` e domínio `vnstudio.dev`, que deixa de ser provisório | ADD §5.5, SDK §3, §10, §13.2, spec 09 §1 |
| **`$id` com a versão das specs:** `https://schemas.vnstudio.dev/specs-v1.0.0/<nome>.schema.json` nos 22 schemas (antes `…/1/…`). O segmento é a tag da Release das specs que publica o schema; cada Release publica os seus num caminho próprio, e um caminho publicado nunca muda nem sai do ar | spec 09 §1, `schemas/*.schema.json` |
| **`$schema` dos dados usa o mesmo endereço:** exemplo (e a demo, de onde ele é copiado), plugin de exemplo, save de exemplo, preset `classic`, vetores de conformidade e de compilação, e o validador de referência | `examples/`, `presets/`, `conformance/`, `tools/validate.py`, `tools/test_validate.py` |

## Decisão de 2026-11-22: catálogo de plugins no v1 (D11)

Fecha a decisão D11 da revisão de 2026-11-14 (issue #113). Luis escolheu a opção "só o índice oficial no monorepo".

| Decisão | Onde |
|---|---|
| **No v1 não há catálogo de terceiros.** O `catalog:official` é o índice `catalog/official.json` do monorepo, com só os plugins oficiais (`trust: official`, `state: published`), lido de uma URL HTTPS fixa. A CI de release o atualiza por pull request a cada tag `plugin-<namespace>-v*`, e a versão aparece no Studio depois do merge. A revogação é um pull request no mesmo arquivo | SDK §13.2, §13.3, §13.5, spec 09 §1, §3.1 |
| **Plugins de terceiros no v1** são distribuídos por `github:` ou por arquivo (`path:`), sempre `trust: local` com a confirmação por máquina. `vnplugin publish` faz só a Release, sem pedido ao catálogo | SDK §4.3, §13.1, §13.5, spec 09 §2, §3.1 |
| **Ficam para o v2**, num repositório de catálogo separado: o nível `reviewed`, os publishers, a reserva de namespace para terceiros, a revisão do SDK §13.4, os passos 4 a 7 do SDK §13.5 (pedido, CI do catálogo, revisão humana com prazo, atualização expressa) | SDK §4.3, §13.2, §13.4, §13.5 |
| **`plugins.schema.json` só aceita `catalog:official`** como catálogo no v1; 3 casos novos em `test_schemas.py` (51 no total) | `plugins.schema.json`, `tools/test_schemas.py` |
| Pré-condição da v1.0.0: o índice e as Releases dos plugins oficiais são baixáveis sem token | SDK §13.2 |

## Decisões de 2026-11-23: spike do Preview (M4-02)

Fecha três itens de "A conferir no primeiro protótipo" (seção de 2026-11-15) com o spike da tarefa M4-02 (`spikes/preview-pck/`, pasta temporária; o código e os números completos ficam no README dela e no histórico do Git). O teste B dos assets é a M4-01. Medido nos runners do GitHub: Windows e Linux sem GPU, macOS em Apple Silicon virtual.

| Resultado | Onde |
|---|---|
| **`vnpreview://` funciona nos três motores.** Servido pelo protocolo próprio do Tauri, o `.wasm` chega com `application/wasm` e compila em streaming no WebView2, na WKWebView e no WebKitGTK, e a página é um contexto seguro. O mapa fixo de três prefixos deu 404 para `..` codificado, caminho absoluto e arquivos do projeto fora do mapa | PP §1.1 |
| **No painel, o runtime lê bytes pelo `fetch` do navegador** (via `JavaScriptBridge`, que o runtime pode usar; W009 vale só para plugins). O `HTTPRequest` do Godot recusa a origem `vnpreview://` do macOS e do Linux | PP §1.3 |
| **`class_name` funciona num `.pck` montado depois do boot**: ao montar, o Godot 4.7 registra as classes do pacote. O plano B (um `.pck` único antes do boot, com `reload_plugins` reabrindo o motor) sai do PP §1.3 e do SDK §10.6 | PP §1.3, SDK §10.6 |
| **Troca do `.pck`**: nome de arquivo novo a cada geração, montagem por cima e releitura dos scripts com `CACHE_MODE_IGNORE` (com `CACHE_MODE_REPLACE` o Godot devolve o script antigo). Recarregar o plugin levou de 2 a 9 ms; ler e montar o pacote no painel, até 30 ms | PP §1.3 |
| **Gerar o `.pck` sem abrir o editor**: o Godot embutido roda com `--script` e empacota com `PCKPacker` os arquivos em texto e os assets já importados, com um cache de classes só do plugin. Leva 160 a 305 ms por salvamento (p50 nos três sistemas), contra 2,7 s do `--export-pack`, que também traria as classes do SDK com os caminhos da cópia de trabalho. O import headless só roda quando um asset do plugin muda | PP §1.3, SDK §10.6 |
| **Template enxuto: medido, escolha com o Luis.** Primeira abertura / reabertura (p50) com o oficial e com o enxuto: WebView2 5,8 / 5,5 s e 4,8 / 4,8 s; WKWebView 2,6 / 0,87 s e 0,73 / 0,70 s; WebKitGTK 3,0 / 2,6 s e 1,8 / 2,0 s. O enxuto tira módulos que um plugin pode usar, então um plugin poderia falhar só no painel. Servido por `vnpreview`, o WebView2 compila o WASM de novo a cada abertura | `spikes/preview-pck/README.md` |
| **Pendência nova para a M4-05:** `preview.load` e `preview.reload_plugins` ainda não dizem onde está o `.pck` de cada plugin, e o nome muda a cada geração | PP §3 |

## Desvios em relação ao ADD

1. **Referências de variáveis sempre qualificadas** (`global.player_money`), inclusive nas permissões de plugins. O ADD usa às vezes o nome curto (`player_money`); o Studio pode exibi-lo assim, mas grava o ID completo.
2. **Plugin tem `id` global e `namespace` curto separados** (`vnstudio.fishing` / `fishing`). O ADD não distingue.
3. **`chapter.completed` virou `sys.chapters.<id>.completed`**, porque variáveis `chapter.*` deixam de existir ao sair do capítulo.
4. **Inventário fora do modelo de variáveis**: listas/conjuntos ficam para v1.1 ou para o plugin de inventário.
5. **Nada de GDExtension em plugins no v1**, para manter a distribuição revisável por código-fonte.
6. **Web entra como plataforma do v1** (exportação sem threads). O ADD §7.5 cita só Windows, Linux, macOS e Android. **Android fica fora do v1** (decisão de 2026-11-14).
7. **Monorepo em vez de cinco repositórios.** O ADD §12 lista `visual-novel-studio`, `visual-novel-runtime`, `visual-novel-sdk`, `visual-novel-cli` e `official-plugins`; a spec 09 §1 junta tudo em `gd-vn-studio`, com tags por componente.
8. **Os dois previews do ADD §3.3 são o mesmo runtime.** O "Preview no Studio" é o runtime exportado para Web num painel do Studio, e o "Preview no Runtime Godot" é o mesmo runtime nativo numa janela; não há interpretador próprio do Studio (decisão de 2026-11-15).
