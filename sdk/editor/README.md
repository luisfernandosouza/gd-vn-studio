# @vnstudio/editor-sdk

API das Editor Extensions dos plugins ([Plugin SDK §10](../../docs/specs/03-plugin-sdk-specification.md)), publicada no npm com a tag `sdk-editor-v<versão>` ([spec 09 §1](../../docs/specs/09-repositories-and-code-layout.md)).

Por enquanto é o esqueleto do workspace (tarefa M0-06): a versão do SDK, `VNError`, `Disposable` e os tipos dos dados do projeto (`Scene`, `Variable`…), que vêm de [`@vnstudio/plugin-schema`](../plugin-schema/README.md). O `PluginContext` do §10.3, a bridge por `postMessage` e o `PluginContext` falso de `@vnstudio/editor-sdk/testing` chegam com a tarefa M7-04.

```bash
npm ci                                   # na raiz do repositório (workspace npm)
npm run build -w @vnstudio/editor-sdk    # gera dist/
```
