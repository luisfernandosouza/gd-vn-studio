# @vnstudio/plugin-schema

Tipos TypeScript dos JSON Schemas das specs ([Plugin SDK §10](../../docs/specs/03-plugin-sdk-specification.md)), usados pelo Studio, pela CLI e pelo Editor SDK.

`docs/specs/schemas/` é a fonte única ([spec 09 §1](../../docs/specs/09-repositories-and-code-layout.md)). Este pacote não guarda cópia dos schemas: [`scripts/generate.mjs`](scripts/generate.mjs) lê todos, junta num documento só e gera [`generated/schemas.d.ts`](generated/schemas.d.ts) com o `json-schema-to-typescript`. O arquivo gerado vai para o Git e **não é editado à mão**.

```ts
import type { Scene, Variable, Variables, Project } from '@vnstudio/plugin-schema';
```

## Nomes

- A raiz de cada schema tem um nome fixo, na tabela `ROOTS` do script: `scene.schema.json` → `Scene`, `variables.schema.json` → `Variables`, `plugin.schema.json` → `PluginManifest`, `set.schema.json` → `SetFile`, `locale.schema.json` → `LocaleFile` e assim por diante. Um schema novo sem nome na tabela faz o script parar.
- Cada `$defs` mantém a chave (`common.schema.json#/$defs/VariableDefinition` → `VariableDefinition`). Se a chave colidir com outro nome, ganha o nome da raiz como prefixo (`ConformanceFileVariables`).
- `Variable` é apelido de `VariableDefinition`.
- Cada definição vira um tipo só, compartilhado por todos os schemas que a citam.

## Atualizar

Quem muda um schema em `docs/specs/schemas/` roda, na raiz do repositório:

```bash
npm ci
npm run generate          # regrava generated/schemas.d.ts
```

e faz commit do arquivo gerado no mesmo pull request. A workflow [`typescript.yml`](../../.github/workflows/typescript.yml) roda `npm run check:generated` e falha se o arquivo estiver desatualizado.

Limites do gerador: o TypeScript não expressa `pattern`, `minimum`, `if`/`then` nem `unevaluatedProperties`. Os tipos descrevem a forma dos dados; quem valida de verdade é o validador (Ajv, tarefa M5-01).
