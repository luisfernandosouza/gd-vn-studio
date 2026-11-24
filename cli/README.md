# CLI

As CLIs `vnstudio` (build e validação de projetos de jogo) e `vnplugin` (criar, testar e publicar plugins), em TypeScript e Node ([Build System](../docs/specs/05-build-system-specification.md), [Plugin SDK §13](../docs/specs/03-plugin-sdk-specification.md), [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

Tag `cli-v<versão>`, publicada no npm (`vnstudio`, `vnplugin`). Os schemas vêm de `docs/specs/schemas/` no build, sem cópia editada à mão: `docs/specs/tools/sync_generated_copies.py cli` gera `cli/schemas/`, fora do Git, para o pacote npm.

O pacote `@vnstudio/cli` faz parte do workspace npm da raiz (M0-06) e usa os tipos de [`@vnstudio/plugin-schema`](../sdk/plugin-schema/README.md) (`Scene`, `Variables`, `Variable`), gerados de `docs/specs/schemas/`. Há `vnstudio info <pasta>` (resumo das cenas e variáveis de um projeto), `vnstudio validate` (abaixo) e `--version`; os demais comandos do Build System e do Plugin SDK §13 chegam com as tarefas M3 e M5. O nome publicado no npm é decidido na tarefa de publicação.

```bash
npm ci                                       # na raiz do repositório
npm run build -w @vnstudio/cli               # gera cli/dist/
node cli/dist/bin/vnstudio.js info docs/specs/examples/demo-project
npm test -w @vnstudio/cli                    # Vitest
```

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
