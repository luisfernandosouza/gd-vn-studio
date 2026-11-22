# Repositórios e organização do código — v1.0.0-draft

- **Status:** rascunho para revisão
- **Base:** ADD §5 e §10; Plugin SDK §2, §11–§13; Build System §3–§4; Data Model §2

Este documento diz onde cada coisa mora no Git. Há três tipos de repositório:

1. **O repositório do produto** (`gd-vn-studio`), com o Studio, o runtime, os SDKs, a CLI e os plugins oficiais.
2. **O repositório de um plugin avulso**, para quem publica um minijogo no catálogo.
3. **O repositório de um jogo**, com o projeto de VN e, se o autor quiser, os minijogos feitos só para ele.

As palavras **DEVE**, **DEVERIA** e **PODE** seguem a RFC 2119.

## 1. Repositório do produto (`gd-vn-studio`)

Um monorepo. Os componentes têm versões próprias, mas mudam juntos com frequência (um campo novo no Data Model toca schema, Studio, runtime e validador), então ficam no mesmo repositório e passam pela mesma CI.

```text
gd-vn-studio/
├── README.md, LICENSE (MIT), CONTRIBUTING.md
├── docs/
│   ├── specs/                  # estas especificações (normativas)
│   │   ├── 00-… a 09-….md
│   │   ├── schemas/            # JSON Schemas: fonte única para Studio, runtime e CLI
│   │   ├── conformance/        # vetores de conformidade (spec 08)
│   │   ├── examples/           # dados de exemplo das specs: só JSON e código, sem arte (§1.1)
│   │   ├── presets/            # presets de interface (classic): tema, telas e textos (UI Spec §2.1)
│   │   └── tools/              # validador, conformidade e compilador de bundle de referência (Python)
│   └── reviews/                # relatórios de revisão
├── studio/                     # Studio: Tauri + React + TypeScript
│   ├── src/                    # interface (React)
│   ├── src-tauri/              # processo nativo (Rust): arquivos, Godot embutido, Git
│   └── preview/                # painel do Preview: ponte com o runtime Web (Preview Protocol §1.1)
├── runtime/                    # Runtime: projeto Godot 4.7.2 + GDScript
│   ├── project.godot
│   ├── vn_runtime/             # Narrative Engine, Scheduler, State Manager, UI Manager…
│   │   ├── presets/            # cópia gerada de docs/specs/presets/ + fontes embutidas (presets/fonts/)
│   │   └── licenses/           # licenças do runtime, do Godot e das fontes do preset (Build System §4.5)
│   └── tests/                  # testes e runner headless dos vetores (--vn-test)
├── sdk/
│   ├── runtime/addons/vn_runtime_sdk/   # Runtime SDK (GDScript), copiado para os projetos de plugin
│   └── editor/                 # Editor SDK (@vnstudio/editor-sdk, npm)
├── cli/                        # CLIs vnstudio e vnplugin (TypeScript, Node)
├── plugins/                    # plugins oficiais (vnstudio.*), um projeto de desenvolvimento cada
│   └── fishing/                # mesmo formato do repositório avulso (§2)
│       ├── project.godot, sandbox/, .vnplugin/
│       └── vn_plugins/fishing/ # o plugin
└── .github/workflows/          # CI: specs.yml (ferramentas das specs e cópia da demo), repo-hygiene.yml (mídia), Studio, runtime, plugins
```

- **Fonte única dos schemas.** `docs/specs/schemas/` é a única cópia. O Studio, a CLI e o runtime os leem dali no build. Nenhum componente mantém uma cópia editada à mão.
- **Presets.** `docs/specs/presets/` é a fonte; o build do runtime copia para `runtime/vn_runtime/presets/` e acrescenta as fontes (`preset/font_*`). Como os schemas, nenhuma cópia é editada à mão.
- **Desenvolvimento do runtime sem o Studio.** `docs/specs/tools/compile_bundle.py <projeto> --godot runtime <pastas-de-plugins…>` compila um projeto de jogo para `runtime/vn_content/` e copia os plugins para `runtime/vn_plugins/<namespace>/`; as duas pastas ficam fora do Git. Depois é só abrir `runtime/` no editor do Godot (RT §2.1). Para a demo, a pasta do plugin é `plugins/fishing/vn_plugins/fishing` ou, enquanto o código não existe, `docs/specs/examples/fishing-plugin`.
- **Runtime do Preview.** A release do runtime gera, além dos templates de exportação, o runtime para o Preview do Studio: o export Web sem threads (`.wasm`, `.js`, `.pck`) para o painel e o pacote `runtime-preview.pck` para a janela (Preview Protocol §1.1 e §1.2). Os dois vêm embutidos no instalador do Studio, sem os testes do runtime (§1.2), entram na conta do tamanho dele e não dependem de baixar nada.
- **Vetores de conformidade.** A CI roda `docs/specs/tools/conformance.py` e o runner do runtime, nativo e Web, sobre `docs/specs/conformance/` em todo pull request (spec 08 §4).
- **Exemplos.** `docs/specs/examples/` guarda só os dados que as specs e o validador usam (§1.1). `docs/specs/examples/fishing-plugin/` é o exemplo de plugin das specs. Quando o código começar, o plugin oficial passa a viver em `plugins/fishing/`, e o exemplo vira uma cópia gerada a partir dele pela CI, para não divergirem.
- **Versões e tags.** Cada componente tem SemVer próprio (ADD §10) e uma tag com prefixo:

  | Componente | Tag | Publicado em |
  |---|---|---|
  | Studio | `studio-v1.2.0` | Release do GitHub (instaladores) |
  | Runtime | `runtime-v1.0.0` | Embutido no Studio; Release com os templates de exportação |
  | Runtime SDK | `sdk-runtime-v1.0.0` | Release (zip do addon) |
  | Editor SDK | `sdk-editor-v1.0.0` | npm |
  | CLI | `cli-v1.0.0` | npm (`vnstudio`, `vnplugin`) |
  | Plugin oficial | `plugin-fishing-v1.0.0` | Release com o `.vnplugin`, e catálogo |
  | Specs | `specs-v1.0.0` | Release; o `$id` dos schemas aponta para a versão |

  `vnplugin publish` aceita `--tag-prefix plugin-<namespace>-` para o monorepo; fora dele, a tag continua `v<versão>` (Plugin SDK §13.5).
- **Catálogo.** O catálogo de plugins é um repositório separado (Plugin SDK §13.2), porque recebe pull requests de terceiros e tem CI e permissões próprias. Quem o opera ainda está em aberto (decisão D11 da revisão de 2026-11-14).

### 1.1. Sem jogo de exemplo nem arte no repositório do produto

O repositório do produto não contém um jogo de exemplo, nem arte, música ou voz de jogo, inclusive arte gerada por IA. Ele guarda código, specs e dados de teste.

- **Dados de exemplo das specs.** `docs/specs/examples/demo-project/` e `demo-save.json` são o projeto mínimo que ilustra as specs e alimenta o validador, os testes (`tools/test_validate.py`) e a CI. São só JSON. `assets.json` cita caminhos (`backgrounds/noraneko/Train_beach.png`…), mas nenhum desses arquivos existe no repositório, e o validador de referência não exige que existam. Os vetores de compilação não usam o exemplo: usam uma cópia congelada em `conformance/compile/base/` (spec 08).
- **Uma fonte para a demo** (decidido em 2026-11-17; como fazer, decisão D23 de 2026-11-22). O repositório da demo é a fonte dos dados do jogo. `docs/specs/examples/demo-project/` é uma cópia só com os JSON, gerada por `docs/specs/tools/sync_demo_example.py` a partir da demo no commit registrado em `examples/demo-project/SOURCE.json`.
  - **Diferença permitida:** só o campo `credit` dos assets (Data Model §10.1), que o script tira. Os créditos de terceiros ficam só na demo, e o repositório do produto não guarda crédito de arte que não distribui. Tudo o mais é igual, byte a byte.
  - **O que é copiado:** só os JSON da raiz e das pastas de dados (`chapters/`, `characters/`, `locales/`, `scenes/`, `sets/`, `ui/`). A lista fica no script, e a CI usa a mesma (`--sparse`) no checkout da demo. Fica de fora todo o resto, inclusive `assets/`, `tools/`, `source/`, `.vnstudio/`, `plugins/`, `migrations/`, os `.md`, `LICENSE` e `.gitignore`.
  - **Versão:** o script confere com `git rev-parse HEAD` que a demo está no commit de `SOURCE.json` e para se não estiver. `--update-source` copia de outro commit de propósito e grava o commit novo em `SOURCE.json`.
  - **CI:** a workflow `specs.yml` roda as ferramentas das specs em todo pull request, faz o checkout da demo no commit de `SOURCE.json` e roda o script com `--check`, que falha se o exemplo divergir. Ela também valida a demo com as specs daquela versão. Como o repositório da demo é privado, o checkout usa o secret `DEMO_REPO_TOKEN` (token com leitura de Contents na demo). Sem o secret, a workflow avisa e pula só essa conferência.
  - **Ordem:** uma mudança que mexe no exemplo entra primeiro na demo. Depois, o pull request do produto roda o script com `--update-source`.
  - **Do lado da demo:** a workflow `specs.yml` da demo valida e compila a demo com as specs da `main` do produto em todo PR, na `main` e uma vez por dia, e mostra o que o exemplo precisaria mudar. Assim uma mudança de qualquer um dos lados que quebre a demo aparece logo, sem esperar a próxima cópia. O checkout do produto, que é privado, usa o secret `PRODUCT_REPO_TOKEN` da demo (leitura de Contents no `gd-vn-studio`); sem ele, a workflow só avisa.
- **Assets de teste** (decisão D22 de 2026-11-22). São internos: não aparecem para o jogador, não têm crédito e não existem em nenhum artefato distribuído (§1.2). Quando o runtime e o Studio precisarem de imagens e sons para testes, eles são gerados por script na CI (cores sólidas, formas, tons de áudio sintéticos) ou ficam em `runtime/tests/fixtures/` como placeholders feitos à mão, sem arte gerada por IA. **Arte de terceiros, mesmo para teste, só entra pela demo:** um teste que precisa de arte de verdade é um teste de ponta a ponta que clona a demo numa versão fixa (abaixo). Assim a licença e o crédito ficam cumpridos na demo, e o produto continua sem arte.
- **Onde pode haver mídia.** Arquivos de imagem, áudio ou vídeo (e fontes de arte como `.psd`) só podem estar em:
  - `runtime/tests/fixtures/`, os placeholders de teste acima;
  - `plugins/*/vn_plugins/*/runtime/`, os assets originais de cada plugin oficial (abaixo);
  - `plugins/*/sandbox/`, a cena de teste do projeto de desenvolvimento de um plugin oficial.

  A workflow `repo-hygiene.yml` confere isso em todo pull request, sem filtro de caminho, e falha com a lista dos arquivos fora dessas pastas. As fontes do preset (`runtime/vn_runtime/presets/fonts/`) não são arte de jogo e ficam fora da conferência.
- **Plugins oficiais.** Os minijogos em `plugins/` seguem a mesma regra: os assets de cada plugin oficial são originais e têm a licença declarada no próprio plugin.
- **Jogo de exemplo jogável.** Fica num repositório separado, [`gd-vn-studio-demo`](https://github.com/luisfernandosouza/gd-vn-studio-demo), com o próprio histórico e licença de assets. Ele é um repositório de jogo comum (§3) e usa os plugins oficiais pelo catálogo, como qualquer jogo. A CI do produto pode exportá-lo como teste de ponta a ponta, clonando-o numa versão fixa, sem trazer os assets para o repositório do produto. Os créditos dos assets de terceiros da demo ficam no `CREDITS.md` dela e no campo `credit` de `assets.json`, e aparecem na tela de créditos do jogo da demo.

### 1.2. Conteúdo dos artefatos

Decisão de 2026-11-22. Nada que serve só para desenvolver o produto chega a quem instala o Studio, o runtime, o SDK ou um plugin oficial.

| Artefato | Entra |
|---|---|
| Instalador do Studio | O Studio compilado, o runtime do Preview (export Web e `runtime-preview.pck`), o Godot embutido, e os schemas e presets, que o build do Studio **copia** de `docs/specs/schemas/` e `docs/specs/presets/` |
| Templates de exportação e `runtime-preview.pck` | `runtime/` sem `tests/`, com os presets copiados de `docs/specs/presets/` e os textos de licença em `vn_runtime/licenses/`: a licença do runtime (MIT), a do Godot com as das bibliotecas dele, e a OFL das fontes do preset. O runtime os mostra na tela de créditos de todo jogo (Build System §4.5) |
| Addon do Runtime SDK, pacotes npm e CLIs | O código e as definições de tipos |
| `.vnplugin` oficial | O que o Plugin SDK §2.1 manda |

**Nunca entra, em nenhum artefato:** `tests/` e `*/tests/*` (inclusive `runtime/tests/fixtures/`), `docs/` como pasta (specs, revisões, exemplos, vetores e `conformance/compile/base/`; só os schemas e os presets entram, copiados pelo build, como na tabela), `spikes/`, os `.md`, salvo o `README.md` e o `CHANGELOG.md` que o Plugin SDK §2.1 manda pôr no `.vnplugin`, e qualquer arquivo da demo.

- **Exportações do runtime.** Os presets de exportação do runtime (Web do Preview, `runtime-preview.pck` e templates) usam `exclude_filter` com `tests/*, */tests/*, docs/*, *.md`. O `exclude_filter` do Build System §7.1 vale para o jogo do autor; este vale para o produto.
- **CI de release.** Antes de publicar, a CI lista o conteúdo de cada `.pck` e do instalador e falha se aparecer um caminho da lista acima, ou um arquivo de imagem, áudio ou vídeo fora dos presets. Ela também confere que `vn_runtime/licenses/` está nos templates e no `runtime-preview.pck`.

## 2. Repositório de um plugin avulso

É o ambiente de desenvolvimento do Plugin SDK §2.4: o repositório é um projeto Godot, e só a pasta `vn_plugins/<namespace>/` vira o `.vnplugin`.

```text
fishing-plugin/
├── project.godot               # Git
├── sandbox/sandbox.tscn        # Git
├── .vnplugin/                  # Git: versão do Godot; o vínculo com projetos de VN fica fora (local.json)
├── addons/vn_runtime_sdk/      # fora do Git: `vnplugin doctor --fix` restaura na versão de sdk.runtime
├── .godot/                     # fora do Git (cache do editor)
└── vn_plugins/fishing/         # o plugin (Git)
```

`vnplugin create` gera também o `.gitignore`:

```text
.godot/
addons/vn_runtime_sdk/
.vnplugin/local.json
*.vnplugin
vn_plugins/*/editor/node_modules/
```

`editor/dist/` vai para o Git, porque entra no pacote e a CI do catálogo confere que ele corresponde a `editor/src/` (Plugin SDK §13.4).

## 3. Repositório de um jogo

O repositório é o projeto de VN (Data Model §2). Os plugins aparecem de quatro formas, conforme a origem:

```text
meu-jogo/
├── project.json, variables.json, assets.json, theme.json
├── characters/, chapters/, scenes/, ui/, sets/, locales/
├── assets/                      # imagens, áudio, fontes (Git LFS recomendado acima de 50 MB no total)
├── plugins.json, plugin-lock.json
├── plugins/                     # minijogos feitos para este jogo (embutidos, §3.2)
│   └── quiz/                    # projeto de desenvolvimento do plugin (mesmo formato do §2)
│       ├── project.godot, sandbox/
│       └── vn_plugins/quiz/
├── vendor/plugins/              # pacotes de terceiros guardados no repositório (§3.3)
│   └── acme.cards-1.2.0.vnplugin
├── .vnstudio/                   # fora do Git: cache, Preview, vínculos e estado do editor
└── .gitignore                   # gerado pelo Studio
```

### 3.1. As quatro origens

| Origem | `source` em `plugins.json` | O que vai para o Git | `plugin-lock.json` | Exportação |
|---|---|---|---|---|
| Catálogo | `catalog:official` | Só a referência | `resolved` (URL), `integrity`, `trust` | Pacote do cache, conferido pelo hash |
| GitHub fora do catálogo | `github:owner/repo` (público ou privado) | Só a referência | `resolved` (URL da Release), `integrity`, `trust: local` | Idem |
| Pacote guardado | `path:vendor/plugins/<arquivo>.vnplugin` | O arquivo `.vnplugin` | `resolved: path:…`, `integrity`, `trust: local` | Pacote do repositório, conferido pelo hash |
| Embutido | `path:plugins/<pasta>` | O código-fonte do plugin | `resolved: path:…`, `embedded: true`, `trust: local`, sem `integrity` | Empacotado da pasta no build (§3.2) |

Uma quinta forma, o **vínculo** de desenvolvimento (Plugin SDK §12.3), não vai para o Git: fica em `.vnstudio/plugin-lock.local.json` e aponta para a pasta de um plugin avulso em outro lugar da máquina. A exportação recusa vínculos (P013).

**Plugins oficiais antes do catálogo.** Enquanto o catálogo não existe, o lock de um plugin oficial aponta para a Release do monorepo: `resolved: "https://github.com/luisfernandosouza/gd-vn-studio/releases/download/plugin-fishing-v1.0.0/vnstudio.fishing-1.0.0.vnplugin"`, com a tag do §1. O `integrity` é o hash do pacote publicado. Até a primeira Release, o `integrity` do lock da demo é provisório (o hash de um arquivo vazio) e o runtime de debug carrega o plugin copiado para `runtime/vn_plugins/` (RT §2.1). Só o Build System confere o `integrity`, e o runtime nunca o confere (RT §3.0). O lock é corrigido quando o pacote existir.

**Repositório privado.** `github:` aceita repositório privado, para um estúdio que reaproveita o mesmo minijogo em vários jogos sem publicá-lo: um repositório de plugin (§2), vários jogos apontando para ele. O token de leitura nunca fica no projeto: o Studio e a CLI o guardam no chaveiro do sistema (Keychain no macOS, Credential Manager no Windows, Secret Service no Linux), pedido na primeira instalação; na CI vem da variável de ambiente `VNSTUDIO_GITHUB_TOKEN`. O pacote baixado vai para o cache como qualquer outro, e a exportação não precisa do token se o cache já o tem. Sem token, a instalação para com uma mensagem que explica como criar um token só de leitura.

Pacotes do catálogo e do GitHub nunca vão para o repositório do jogo. Ficam no cache `~/.vnstudio/cache/plugins/<id>/<versão>/` (Build System §10.2) e são baixados de novo numa máquina nova, conferidos pelo `integrity` do lock.

### 3.2. Plugin embutido

É o caminho para o minijogo que só existe neste jogo e não vai ser publicado. O código fica no mesmo repositório, sob o mesmo histórico do roteiro, e quem clona o repositório tem tudo.

- **Criar.** No Plugin Manager, "Novo minijogo deste projeto", ou `vnplugin create --embedded <pasta-do-projeto>`. Cria `plugins/<nome>/` no formato do §2 e acrescenta a entrada em `plugins.json` com `source: "path:plugins/<nome>"`.
- **Caminho.** `path:` aponta para a pasta do projeto de desenvolvimento. O Studio procura dentro dela o único `vn_plugins/<namespace>/plugin.json`. Uma pasta sem esse arquivo, ou com mais de um, é erro P021.
- **Versão.** A versão vem do `plugin.json` e vai para o lock, como em qualquer plugin. Ela continua importando: o save guarda a versão de cada plugin, e as migrações (`save.data_version`, `profile.data_version`) dependem dela.
- **Godot e runtime.** O embutido herda a versão do runtime e do Godot do projeto (Build System §2.1). A pasta `.vnplugin/` do projeto de desenvolvimento é opcional; se existir e fixar outra versão, vale a do projeto, e o Studio avisa. `vnplugin godot open` abre o editor nessa versão.
- **`editor/dist`.** O Studio compila `editor/src` para `editor/dist` ao salvar, com o mesmo bundler de `vnplugin build`, e avisa quando `dist` está mais velho que `src`. `editor/dist` não vai para o Git (§3.4).
- **Edição e Preview.** O Studio lê os arquivos direto da pasta, como num vínculo, e recarrega o plugin no Preview ao salvar (`preview.reload_plugins`). O dev abre `plugins/<nome>/` no Godot com `vnplugin godot open` e depura como no Plugin SDK §12.3.
- **Lock.** Quando o `plugin.json` muda de versão, de permissões ou de dependências, o Studio atualiza a entrada do lock sozinho, porque o código é do próprio projeto. Mudança de permissões abre o diálogo de concessão (Plugin SDK §4.1).
- **Confiança.** O plugin embutido é `trust: local`. Cada máquina confirma uma vez que o código do projeto pode rodar (Plugin SDK §4.3); a confirmação fica em `.vnstudio/`, fora do Git, para que um repositório clonado de terceiros nunca execute código sem o aviso.
- **Exportação.** O Build System empacota a pasta `vn_plugins/<namespace>/` com as regras do `.vnplugin` reprodutível (Plugin SDK §2.1–§2.2), calcula o `integrity` e o registra no manifesto do build (Build System §9). A partir daí, o plugin segue o mesmo caminho dos outros no staging (Build System §4.5).
- **Id.** Qualquer id válido. Recomenda-se `<id do projeto>.<nome>` (ex.: `seaside_story.quiz`), que deixa claro que o plugin é deste jogo. O namespace segue as regras de sempre (único no projeto, P001; não reservado).
- **Publicar depois.** Para transformar um embutido em avulso: copiar `plugins/<nome>/` para um repositório próprio, publicar (Plugin SDK §13.5) e trocar `source` para `catalog:` ou `github:`. Saves continuam valendo, porque id e namespace não mudam.

### 3.3. Pacote guardado

Para plugins de terceiros que o autor quer manter dentro do repositório: uso offline, plugins privados de um estúdio ou a garantia de que o pacote nunca some. "Guardar no projeto" no Plugin Manager copia o `.vnplugin` do cache para `vendor/plugins/<id>-<versão>.vnplugin` e troca o `source`. O `integrity` não muda. Pacotes com mais de 10 MB disparam a sugestão de Git LFS.

### 3.4. `.gitignore` do projeto

O Studio cria e mantém este bloco no `.gitignore` do projeto:

```text
# Visual Novel Studio
.vnstudio/
plugins/*/.godot/
plugins/*/addons/vn_runtime_sdk/
plugins/*/.vnplugin/local.json
plugins/*/vn_plugins/*/editor/node_modules/
plugins/*/vn_plugins/*/editor/dist/
build/
```

`.vnstudio/` reúne o que é da máquina: cache de import, Preview (inclusive `.vnstudio/preview/user/`, os saves do Preview quando o autor pede para mantê-los, Preview Protocol §1.4), `plugin-lock.local.json`, confirmações de confiança e o histórico de backups (Req §8).

## 4. Onde os dados dos minijogos ficam no computador do jogador

Para completar o quadro, o que fica fora do Git (Runtime Spec §8.5, Plugin SDK §9 e §9.1):

| Dado | Arquivo em `user://` | Vida |
|---|---|---|
| Estado do minijogo numa partida (`_vn_save`) | `saves/<slot>.json → state.plugins.<namespace>` | Uma partida |
| Variáveis do plugin com `persistence: save` | `saves/<slot>.json → state.variables` | Uma partida |
| Variáveis do plugin com `persistence: profile` | `profile.json → variables` | Entre partidas |
| Dados de perfil do plugin (`ctx.profile.set_data`) | `profile.json → plugins.<namespace>.data` | Entre partidas |
| Recordes (`ctx.profile.submit_record`) | `profile.json → plugins.<namespace>.records` | Entre partidas |

## 5. Validação

| Código | Nível | Regra |
|---|---|---|
| P021 | erro | Fonte `path:` de `plugins.json` não existe, ou a pasta de um plugin embutido não tem exatamente um `vn_plugins/<namespace>/plugin.json` |

O validador de referência carrega sozinho os manifestos dos plugins embutidos, sem precisar recebê-los na linha de comando.
