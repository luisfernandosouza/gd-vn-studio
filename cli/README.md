# CLI

As CLIs `vnstudio` (build e validação de projetos de jogo) e `vnplugin` (criar, testar e publicar plugins), em TypeScript e Node ([Build System](../docs/specs/05-build-system-specification.md), [Plugin SDK §13](../docs/specs/03-plugin-sdk-specification.md), [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

Tag `cli-v<versão>`, publicada no npm (`vnstudio`, `vnplugin`). Os schemas vêm de `docs/specs/schemas/` no build, sem cópia editada à mão: `docs/specs/tools/sync_generated_copies.py cli` gera `cli/schemas/`, fora do Git, para o pacote npm.

O pacote `@vnstudio/cli` faz parte do workspace npm da raiz (M0-06) e usa os tipos de [`@vnstudio/plugin-schema`](../sdk/plugin-schema/README.md) (`Scene`, `Variables`, `Variable`), gerados de `docs/specs/schemas/`. Há `vnstudio info <pasta>` (resumo das cenas e variáveis de um projeto), `vnstudio validate` (abaixo) e `--version`; os demais comandos do Build System e do Plugin SDK §13 chegam com as tarefas M3 e M5. O nome publicado no npm é decidido na tarefa de publicação.

`src/plugins/` (M5-05) tem a resolução de dependências de plugins: as quatro origens da [spec 09 §3.1](../docs/specs/09-repositories-and-code-layout.md) (`catalog:official` contra [`catalog/official.json`](../catalog/README.md), `github:` com o token de `VNSTUDIO_GITHUB_TOKEN` ou do chaveiro, pacote guardado e embutido), o Dependency Resolver que gera o `plugin-lock.json` (Plugin SDK §11.3), o cache em `~/.vnstudio/cache/plugins/` e a etapa de dependências do build (Build System §3.2: B002, B003, B015 e P013). Os comandos `vnplugin install` e `vnstudio build` que a usam chegam com M5-11 e M5-12.

```bash
npm ci                                       # na raiz do repositório
npm run build -w @vnstudio/cli               # gera cli/dist/
node cli/dist/bin/vnstudio.js info docs/specs/examples/demo-project
npm test -w @vnstudio/cli                    # Vitest
```

## Compilador do bundle (`src/bundle/`, M5-02)

Porte em TypeScript de `docs/specs/tools/compile_bundle.py` ([Build System §5.1](../docs/specs/05-build-system-specification.md)): gera a forma canônica do RT §2 (`bundle.json` com o `content_hash`, `locales/<idioma>.json`, `plugins.json` e `licenses.json`), com os defaults resolvidos, o preset aplicado, a galeria resolvida, a edição censurada e o `plugins.json` a partir do lock. Para o mesmo projeto, os bytes são os mesmos da referência.

| Módulo | O que faz | Node? |
|---|---|---|
| `jcs.ts` | JSON canônico (RFC 8785) | não |
| `hash.ts` | SHA-256, HMAC-SHA256, `sha256-<base64>`, assinatura de saves (BS §8.3) | não |
| `compile.ts` | compilação, uma função por entidade (cena, capítulo, tela, asset…) | não |
| `incremental.ts` | `planReload`/`applyPatch`: patches do `preview.reload` (Preview Protocol §3) | não |
| `load.ts`, `write.ts` | leitura do projeto e gravação do bundle | sim |

Os módulos puros servem também ao Studio (WebView). O compilador não valida: quem chama roda o validador antes (M5-01) e para em erro, como a referência.

```ts
import { compileProject, loadProject, writeBundle } from './bundle/index.js';
writeBundle('out', compileProject(loadProject('docs/specs/examples/demo-project', { pluginDirs: ['docs/specs/examples/fishing-plugin'] })));
```

Os testes conferem os 7 vetores de `conformance/canonical.json`, os 8 de `conformance/compile/cases.json`, a equivalência incremental em cada vetor e a igualdade byte a byte com `compile_bundle.py` (exemplo das specs nas duas edições e os 8 vetores; precisa de `python3`, sem `jsonschema`).

## Build Staging (`src/build/`, M5-06)

`vnstudio stage <projeto> --out <pasta> [--plugin <pasta>...] [--offline] [--edition ...]` monta o Build Staging do [Build System §4](../docs/specs/05-build-system-specification.md) e para aí (o export é a M5-09; `vnstudio build`, a M5-11). Sem `--plugin`, os plugins vêm do `plugin-lock.json` pela etapa de dependências (M5-05); com ele, das pastas dadas (desenvolvimento e testes).

| Módulo | O que faz |
|---|---|
| `godot-project.ts` | `project.godot` do zero: nome, versão, cena principal, ícone/splash, resolução, esticamento, ações `vn_*` e renderizador do template, traduções vazias, filtro linear (BS §4.3) |
| `build-config.ts` | `build_config.gd` com as constantes de `VNBuildConfig` (BS §4.4) |
| `staging.ts` | `stageBuild`: template do runtime e do SDK, `vn_content/` (bundle, idiomas, plugins, licenças, assets, `build.json`), `vn_plugins/<namespace>/` só com `plugin.json`, `LICENSE` e `runtime/` (BS §4.5), `build_id`, B005, B014, B018 |

Escolhas onde a spec é omissa: o bundle entra na forma canônica em JSON (o runtime de debug a lê, RT §2.1) porque o `.vnb` é a M5-03, então o tipo `release` é recusado até lá; `CONTENT_HASHES` já traz o hash do JSON canônico de cada `.vnb`; sem `autoload/*`, porque o runtime não tem scripts de autoload (a cena `boot.tscn` monta os módulos); sem splash, `boot_splash/show_image=false` com a cor `colors.background` do tema, ou preto se o tema não a define; todos os assets de `assets.json` são copiados (a seleção só dos usados é a M5-07). A workflow [`cli-staging.yml`](../.github/workflows/cli-staging.yml) monta o staging da demo e o abre no Godot 4.7.2; o `--vn-selfcheck` entra com a M5-08.

## Validador de conteúdo (M5-01)

`vnstudio validate [--export] [--json] <projeto> [<plugin>...]` aplica as regras do Content Validator (Data Model §11, UI Spec §11, spec 09 §5): todos os códigos S, R, T, P, W e U. `--export` liga as regras de exportação (R021, P013; W013 e U009 viram erro). Sai com 1 se houver erro.

O código fica em [`src/validate/`](src/validate/) e é um porte fiel de [`docs/specs/tools/validate.py`](../docs/specs/tools/validate.py), a implementação de referência (Req §14). Cada diagnóstico traz `code`, `where`, `detail` (o texto técnico, igual ao do Python) e `message`, uma frase em linguagem simples (Req §6, [`messages.ts`](src/validate/messages.ts)). A API (`validateProject`) é a que o Studio vai usar na validação contínua (M6-03).

Para dar o mesmo resultado que o Python, o leitor de JSON separa `2` (int) de `2.0` (float), e a verdade, o `repr()` e a ordem seguem as do Python ([`py.ts`](src/validate/py.ts)). Os schemas vêm de `docs/specs/schemas/` (ou de `cli/schemas/` no pacote; `VNSTUDIO_SPECS` aponta outra pasta) e são conferidos com o Ajv (JSON Schema 2020-12, sem conferir `format`, como o `jsonschema` do Python), com mensagens em português.

**Paridade com `validate.py`.** [`scripts/validate_parity.py`](scripts/validate_parity.py) monta os 143 casos de `test_validate.py` mais o exemplo limpo e grava o que o Python acusa; [`parity.test.ts`](src/validate/parity.test.ts) roda o validador TypeScript nas mesmas pastas e exige os mesmos diagnósticos (para S000 e P004, que vêm da biblioteca de JSON Schema, compara código e local). Precisa de Python com `jsonschema`; sem ele o teste é pulado localmente. Na CI roda sempre, na workflow [`cli-validate.yml`](../.github/workflows/cli-validate.yml).

```bash
pip install 'jsonschema>=4.18'
npm test -w @vnstudio/cli                    # inclui os 144 casos de paridade
node cli/dist/bin/vnstudio.js validate docs/specs/examples/demo-project docs/specs/examples/fishing-plugin
```

Pendência fora desta pasta: o pacote npm precisa de `cli/presets/` (W021 e W024 leem os presets); hoje `sync_generated_copies.py cli` só gera `cli/schemas/`. No monorepo o validador lê `docs/specs/presets/`.
