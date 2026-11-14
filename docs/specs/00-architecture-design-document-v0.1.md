# Visual Novel Studio — Documento de Arquitetura e Especificação Técnica

- **Versão:** 0.1
- **Status:** Documento inicial de arquitetura
- **Objetivo:** Consolidar decisões arquiteturais, especificações propostas e pendências do Visual Novel Studio.

---

## 1. Visão geral do projeto

O Visual Novel Studio será uma plataforma para criação de Visual Novels com suporte a narrativas dinâmicas, variáveis internas, seleção inteligente de cenas e minigames.

A plataforma terá duas partes principais:

- **Visual Novel Studio:** editor externo utilizado por roteiristas, artistas e desenvolvedores.
- **Visual Novel Runtime:** ambiente responsável por executar a Visual Novel e seus sistemas de gameplay.

O objetivo é permitir que pessoas sem conhecimento de programação consigam construir histórias, configurar cenários, diálogos, personagens, escolhas e condições narrativas.

Ao mesmo tempo, desenvolvedores poderão criar minigames e funcionalidades adicionais através de um sistema extensível de plugins.

### 1.1. Objetivos principais

- Permitir criação de Visual Novels sem programação.
- Oferecer editor visual de cenas e narrativas.
- Suportar variáveis persistentes e temporárias.
- Permitir narrativas dinâmicas.
- Selecionar cenas automaticamente com base em prioridades e condições.
- Permitir integração de minigames.
- Possibilitar criação de plugins.
- Oferecer exportação para diferentes plataformas.
- Permitir que desenvolvedores externos ampliem as funcionalidades da plataforma.

## 2. Arquitetura tecnológica

### 2.1. Tecnologias definidas

| Componente | Tecnologia |
|---|---|
| Aplicação desktop | Tauri |
| Interface | React |
| Linguagem do editor | TypeScript |
| Runtime do jogo | Godot 4 |
| Linguagem do runtime | GDScript |
| Comunicação de dados | JSON |
| Validação de schemas | JSON Schema |
| Versionamento | Git |
| Versionamento de pacotes | Semantic Versioning |
| Empacotamento de plugins | ZIP com extensão `.vnplugin` |
| Build do jogo | Godot Headless |
| Distribuição inicial de plugins | GitHub Releases |

### 2.2. Arquitetura geral

A plataforma será organizada em quatro grandes camadas.

**Visual Novel Studio** — responsável pela criação e edição do projeto. Módulos previstos: Project Manager, Narrative Editor, Scene Editor, Dialogue Editor, Character Manager, Asset Manager, Variable Manager, Condition Editor, Scene Scheduler Editor, Plugin Manager, Preview System, Build Manager.

**Visual Novel Runtime** — responsável pela execução do jogo. Módulos previstos: Narrative Engine, Scene Scheduler, Condition Evaluator, State Manager, Variable Manager, Event Executor, Plugin Manager, Save Manager, UI Manager, Audio Manager, Asset Manager.

**Plugin SDK** — responsável por permitir a criação de extensões. Componentes: Editor SDK, Runtime SDK, Plugin Manifest, Plugin Schema, Plugin CLI, Plugin Validator.

**Build System** — responsável por preparar e exportar os jogos. Componentes: Content Validator, Dependency Resolver, Plugin Packager, Asset Processor, Build Staging, Godot Import, Godot Export, Build Reporter.

## 3. Editor externo

### 3.1. Objetivo

O editor será uma aplicação desktop independente do editor visual do Godot. Roteiristas e artistas deverão conseguir trabalhar sem abrir o editor Godot.

### 3.2. Responsabilidades do editor

Criar projetos; gerenciar capítulos; criar cenas narrativas; editar diálogos; configurar escolhas; gerenciar personagens; importar e organizar assets; criar e editar variáveis; configurar condições; definir prioridades de cenas; configurar eventos de plugins; visualizar previews; gerenciar plugins; executar builds.

### 3.3. Preview

O projeto deverá suportar dois tipos de preview:

- **Preview no Studio:** visualização integrada ao editor.
- **Preview no Runtime Godot:** execução da Visual Novel no ambiente real de jogo.

A comunicação entre o Studio e o Godot deverá ser padronizada. A escolha definitiva entre WebSocket, comunicação por processo ou outra solução ainda está pendente.

## 4. Sistema narrativo dinâmico

### 4.1. Conceito

A história não será executada exclusivamente através de uma sequência linear de cenas. O sistema deverá considerar variáveis internas, escolhas anteriores, resultados de minigames e condições narrativas para determinar quais cenas poderão ser executadas.

### 4.2. Seleção de cenas

Estratégia definida: **Priority-based Scene Selection**.

Cada cena poderá possuir: identificador, capítulo, condições de elegibilidade, prioridade, estado de execução, restrições, conteúdo narrativo, eventos associados.

```json
{
  "id": "scene_fishing_master",
  "priority": 80,
  "conditions": [
    { "variable": "fishing_won", "operator": "equals", "value": true },
    { "variable": "fishing_skill", "operator": "greater_than_or_equal", "value": 10 }
  ]
}
```

O Scene Scheduler deverá:

1. Identificar as cenas candidatas.
2. Avaliar suas condições.
3. Descartar cenas inelegíveis.
4. Ordenar as cenas restantes por prioridade.
5. Aplicar critérios adicionais de desempate.
6. Selecionar a cena.
7. Atualizar seu estado de execução.

O algoritmo definitivo e as regras de desempate ainda precisam ser especificados.

### 4.3. Gerenciamento de variáveis

Estratégia definida: **Hybrid Variable Management**.

Categorias previstas: variáveis globais, de personagem, locais de cena, de capítulo e de plugin.

```text
global.player_money
character.alice.affection
scene.current_choice
chapter.completed
plugin.fishing.total_caught
```

Cada variável deverá possuir: ID, nome, tipo, valor padrão, escopo, persistência, restrições, permissões de acesso.

Ainda precisam ser definidas as regras completas de escopo, ciclo de vida e persistência.

## 5. Sistema de plugins

### 5.1. Estratégia definida

O ecossistema de plugins será inicialmente desenvolvido pela equipe oficial, mas preparado para receber desenvolvedores externos futuramente.

Decisões: plugins oficiais e externos; distribuição baseada em código-fonte; SDK independente; pacotes versionados; instalação através do Plugin Manager; integração com o Build System.

### 5.2. Tipos de plugins

- **Editor Extension** — adiciona ferramentas ao Studio (editor de mapas, timeline, ferramentas de animação, editores especializados).
- **Runtime Extension** — adiciona funcionalidades ao jogo (Fishing Minigame, Inventory System, Combat System, Rhythm Game).
- **Full Extension** — integra editor e runtime (ex.: sistema de quests com editor visual e execução no Godot).

### 5.3. Estrutura dos pacotes

Formato definido: `.vnplugin` (arquivo ZIP com extensão própria).

```text
fishing-plugin/
├── plugin.json
├── README.md
├── LICENSE
├── CHANGELOG.md
├── editor/
│   ├── package.json
│   ├── src/
│   ├── dist/
│   └── schemas/
├── runtime/
│   ├── src/
│   ├── scenes/
│   └── assets/
├── resources/
├── tests/
└── docs/
```

### 5.4. Plugin Manifest

Cada plugin deverá possuir um manifesto `plugin.json`. Campos propostos: `manifest_version`, `id`, `name`, `version`, `description`, `author`, `license`, `sdk`, `compatibility`, `targets`, `entrypoints`, `capabilities`, `events`, `dependencies`.

O manifesto será declarativo e deverá ser validado antes da instalação.

### 5.5. SDK

O SDK será independente do Visual Novel Studio. Pacotes previstos: `@vnstudio/plugin-sdk`, `@vnstudio/editor-sdk`, `@vnstudio/plugin-cli`, `@vnstudio/plugin-schema`.

- **Editor SDK** — APIs: panels, commands, events, schemas, assets, narrative, notifications, preview.
- **Runtime SDK** — APIs: NarrativeAPI, VariableAPI, EventAPI, AssetAPI, AudioAPI, SceneAPI, SaveAPI.

As interfaces e assinaturas definitivas ainda precisam ser documentadas.

## 6. Comunicação entre plugins e Visual Novel Runtime

### 6.1. Princípio arquitetural

Plugins não deverão modificar diretamente o armazenamento interno do Narrative Engine. Eles deverão utilizar APIs controladas pelo Runtime.

```text
Plugin → Narrative API → State Manager → Variable Manager → Condition Evaluator → Scene Scheduler
```

### 6.2. Narrative API

| Serviço | Responsabilidade |
|---|---|
| Variables | Consultar e alterar variáveis |
| Events | Emitir e receber eventos |
| Transactions | Executar alterações atômicas |
| Inventory | Gerenciar itens |
| Characters | Consultar dados de personagens |
| Scenes | Solicitar transições autorizadas |

### 6.3. Alteração de variáveis

```gdscript
narrative.variables.get_value("player_money")
narrative.variables.add_value("player_money", 100)
narrative.variables.set_value("fishing_won", true)
```

As operações deverão verificar: existência da variável, tipo de dado, permissões, escopo, restrições, estado atual do jogo. O State Manager será responsável por validar e aplicar as alterações.

### 6.4. Permissões

```json
{
  "variable_permissions": {
    "read": ["player_money", "fishing_skill"],
    "write": ["player_money", "fishing_skill", "fishing_won"]
  }
}
```

As permissões efetivas serão configuradas e verificadas pelo projeto e pelo runtime. O manifesto não será considerado uma barreira de segurança por si só.

### 6.5. Variáveis próprias dos plugins

```json
{
  "variables": [
    { "id": "fishing.total_caught", "type": "integer", "default": 0, "scope": "global" }
  ]
}
```

O sistema deverá oferecer namespaces exclusivos para evitar conflitos.

### 6.6. Eventos narrativos

```gdscript
narrative.events.emit("fishing.completed", { "fish_count": 3, "score": 850 })
```

### 6.7. Transações

```gdscript
var transaction = narrative.begin_transaction()
transaction.add("player_money", 100)
transaction.add("fishing_skill", 5)
transaction.set("fishing_won", true)
var result = transaction.commit()
```

Se uma operação for inválida, nenhuma alteração da transação deverá ser aplicada.

### 6.8. Controle de cenas

Plugins não deverão controlar livremente a sequência narrativa. **Plugins executam gameplay. Narrative Engine controla a história.** Plugins poderão solicitar transições especiais quando possuírem autorização. O Scene Scheduler continuará responsável pela seleção de cenas.

## 7. Build System

### 7.1. Estratégia

O Build System utilizará uma cópia temporária do runtime. O projeto original não deverá ser modificado durante a preparação do build.

### 7.2. Pipeline

```text
Studio Project → Dependency Resolver → Plugin Lock → Build Staging → Plugin Integration
→ Asset Processing → Godot Import → Godot Validation → Godot Export → Final Game
```

### 7.3. Plugin Lock

Cada projeto possuirá um `plugin-lock.json` registrando IDs, versões, origem, hash dos pacotes e estado de habilitação. O build deverá utilizar as versões fixadas no lockfile.

### 7.4. Dependências

O Dependency Resolver deverá verificar dependências, resolver versões, detectar conflitos e dependências circulares, identificar plugins desabilitados e garantir reprodutibilidade.

### 7.5. Exportação

Godot Headless. Plataformas: Windows, Linux, macOS, Android futuramente. A estratégia definitiva de distribuição dos assets narrativos, PCK e conteúdos externos ainda precisa ser estabelecida.

## 8. Segurança

### 8.1. Editor Plugins

Contextos isolados; API Bridge controlada; acesso limitado ao projeto; validação das mensagens; permissões por funcionalidade; nenhum acesso irrestrito aos comandos internos do Tauri. Para extensões externas, deverá existir isolamento real entre o código do plugin e o contexto privilegiado da aplicação.

### 8.2. Runtime Plugins

Plugins GDScript executam dentro do processo Godot e não devem ser tratados como código isolado. Política: plugins oficiais revisados pela equipe; externos com revisão obrigatória antes do catálogo oficial; desconhecidos não executam automaticamente; verificação de hashes; histórico de versões; revogação de versões comprometidas. Uma futura arquitetura de plugins não confiáveis exigirá um runtime sandbox separado.

## 9. Distribuição e publicação

### 9.1. Ferramenta CLI

```bash
vnplugin create | validate | test | package | install | publish
```

### 9.2. Processo de publicação

Desenvolvimento → Validação → Testes → Revisão de segurança → Empacotamento → Geração de hash → Publicação.

### 9.3. Estados

Draft, Review, Published.

### 9.4. Distribuição inicial

GitHub Releases e um catálogo JSON simplificado. Marketplace completo é evolução futura.

## 10. Compatibilidade e versionamento

Controladas separadamente: versão do Studio, do Editor SDK, do Runtime SDK, do Godot e de cada plugin. Semantic Versioning; mudanças incompatíveis exigem MAJOR. Migrações de configuração; compatibilidade de projetos antigos sempre que possível; migrações destrutivas exigem confirmação explícita.

## 11. Plugin de referência

Fishing Minigame: manifesto, configuração visual no editor, schema de parâmetros, runtime Godot, comunicação com Narrative API, atualização de variáveis, emissão de eventos, integração com saves, testes isolados, inclusão no build final. O sucesso desse plugin será um dos principais critérios de validação da arquitetura.

## 12. Estrutura dos repositórios

> **Nota (2026-11-14):** superada pela [spec 09](09-repositories-and-code-layout.md) §1, que adota um monorepo (`gd-vn-studio`). O texto abaixo fica como registro do ADD v0.1.

```text
VisualNovelPlatform/
├── visual-novel-studio/
├── visual-novel-runtime/
├── visual-novel-sdk/
├── visual-novel-cli/
└── official-plugins/
    ├── fishing/
    ├── inventory/
    ├── relationship/
    └── rhythm/
```

## 13. Pendências arquiteturais

> **Nota (2026-11-14):** a maioria destas pendências já tem resposta nas specs 01 a 09; o [README](README.md) mostra onde cada uma foi tratada. A lista abaixo fica como registro do ADD v0.1.

### 13.1. Sistema narrativo
Algoritmo definitivo de seleção de cenas; critérios de desempate; comportamento sem cena elegível; repetição de cenas; exclusividade entre cenas; ciclos de vida das variáveis; persistência por escopo; variáveis derivadas; alterações simultâneas.

### 13.2. Editor
Estrutura completa do projeto; modelo de dados de cenas e diálogos; interface de condições e de seleção de cenas; undo/redo; comunicação com Godot; sincronização do preview; importação de assets.

### 13.3. Runtime
Arquitetura do Narrative Engine; contratos do State Manager e do Variable Manager; ciclo de vida e erros dos plugins; execução assíncrona; persistência e restauração de estado; integração entre saves e plugins.

### 13.4. Plugin SDK
Finalizar `plugin.json`, Editor SDK e Runtime SDK; contratos de eventos, configuração e permissões; migração; compatibilidade; API de preview; API de testes.

### 13.5. Segurança
Isolamento de Editor Plugins; permissões; aprovação; assinatura; integridade; revogação; plugins externos não confiáveis.

### 13.6. Build e distribuição
Build Staging; conteúdo do PCK; conteúdo externo; atualização dos jogos; reprodutibilidade; cache de dependências; catálogo; publicação comunitária.

### 13.7. Produto
Distribuição do Studio; licenças do SDK e plugins oficiais; propriedade dos projetos; colaboração; internacionalização; roadmap de plataformas.

## 14. Roadmap sugerido

1. **Fundação** — estrutura do projeto, modelo de dados narrativos, runtime básico, Variable Manager, Narrative Engine, Scene Scheduler.
2. **Editor** — Project Manager, Scene Editor, Dialogue Editor, Character Manager, Variable Manager visual, Condition Editor, Preview.
3. **Plugin SDK** — Plugin Manifest, Runtime SDK, Editor SDK, Plugin Registry, Plugin Manager, Fishing Minigame.
4. **Build System** — Dependency Resolver, Plugin Lock, Build Staging, Godot Headless, exportação Windows, testes automatizados.
5. **Ecossistema** — Plugin CLI, documentação, GitHub Releases, catálogo, revisão de plugins externos, publicação comunitária.
6. **Expansão** — multiplataforma, marketplace, colaboração, atualizações de conteúdo, ecossistema ampliado.

## 15. Princípios arquiteturais definitivos

1. O editor externo não deve depender do editor visual do Godot.
2. O runtime deve funcionar independentemente do Studio.
3. O SDK deve ser independente da implementação interna do Studio.
4. Plugins devem interagir com a narrativa somente através de APIs controladas.
5. O Narrative Engine é a autoridade sobre o estado narrativo.
6. O Scene Scheduler é a autoridade sobre a seleção de cenas.
7. Plugins executam gameplay; o Narrative Engine controla a história.
8. Plugins devem declarar suas dependências e permissões.
9. Builds devem utilizar versões fixadas de plugins.
10. Projetos antigos devem ter estratégias de compatibilidade e migração.
11. Código de terceiros não deve ser considerado seguro simplesmente por estar empacotado.
12. O sistema deve privilegiar modularidade e simplicidade para permitir evolução por uma equipe pequena.

## 16. Próximo marco de desenvolvimento

Definir e congelar três especificações:

1. **Narrative Data Model** — como cenas, diálogos, escolhas, variáveis, condições e prioridades são armazenados.
2. **Narrative Runtime Specification** — como o jogo executa cenas, avalia condições, atualiza variáveis e seleciona novos conteúdos.
3. **Plugin SDK Specification** — contratos entre plugins, Studio e Runtime.

**Status geral:** arquitetura conceitual consolidada; contratos detalhados, schemas definitivos e implementação ainda pendentes.
