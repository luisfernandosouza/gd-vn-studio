# CLI

As CLIs `vnstudio` (build e validação de projetos de jogo) e `vnplugin` (criar, testar e publicar plugins), em TypeScript e Node ([Build System](../docs/specs/05-build-system-specification.md), [Plugin SDK §13](../docs/specs/03-plugin-sdk-specification.md), [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

Tag `cli-v<versão>`, publicada no npm (`vnstudio`, `vnplugin`). Os schemas vêm de `docs/specs/schemas/` no build, sem cópia editada à mão: `docs/specs/tools/sync_generated_copies.py cli` gera `cli/schemas/`, fora do Git, para o pacote npm.

O pacote `@vnstudio/cli` faz parte do workspace npm da raiz (M0-06) e usa os tipos de [`@vnstudio/plugin-schema`](../sdk/plugin-schema/README.md) (`Scene`, `Variables`, `Variable`), gerados de `docs/specs/schemas/`. Por enquanto só há `vnstudio info <pasta>` (resumo das cenas e variáveis de um projeto) e `--version`; os comandos do Build System e do Plugin SDK §13 chegam com as tarefas M3 e M5. O nome publicado no npm é decidido na tarefa de publicação.

`src/plugins/` (M5-05) tem a resolução de dependências de plugins: as quatro origens da [spec 09 §3.1](../docs/specs/09-repositories-and-code-layout.md) (`catalog:official` contra [`catalog/official.json`](../catalog/README.md), `github:` com o token de `VNSTUDIO_GITHUB_TOKEN` ou do chaveiro, pacote guardado e embutido), o Dependency Resolver que gera o `plugin-lock.json` (Plugin SDK §11.3), o cache em `~/.vnstudio/cache/plugins/` e a etapa de dependências do build (Build System §3.2: B002, B003, B015 e P013). Os comandos `vnplugin install` e `vnstudio build` que a usam chegam com M5-11 e M5-12.

```bash
npm ci                                       # na raiz do repositório
npm run build -w @vnstudio/cli               # gera cli/dist/
node cli/dist/bin/vnstudio.js info docs/specs/examples/demo-project
npm test -w @vnstudio/cli                    # Vitest
```
