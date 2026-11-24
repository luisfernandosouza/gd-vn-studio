# CLI

As CLIs `vnstudio` (build e validação de projetos de jogo) e `vnplugin` (criar, testar e publicar plugins), em TypeScript e Node ([Build System](../docs/specs/05-build-system-specification.md), [Plugin SDK §13](../docs/specs/03-plugin-sdk-specification.md), [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

Tag `cli-v<versão>`, publicada no npm (`vnstudio`, `vnplugin`). Os schemas vêm de `docs/specs/schemas/` no build, sem cópia editada à mão: `docs/specs/tools/sync_generated_copies.py cli` gera `cli/schemas/`, fora do Git, para o pacote npm.

O pacote `@vnstudio/cli` faz parte do workspace npm da raiz (M0-06) e usa os tipos de [`@vnstudio/plugin-schema`](../sdk/plugin-schema/README.md) (`Scene`, `Variables`, `Variable`), gerados de `docs/specs/schemas/`. Por enquanto só há `vnstudio info <pasta>` (resumo das cenas e variáveis de um projeto) e `--version`; os comandos do Build System e do Plugin SDK §13 chegam com as tarefas M3 e M5. O nome publicado no npm é decidido na tarefa de publicação.

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
