# CLI

As CLIs `vnstudio` (build e validação de projetos de jogo) e `vnplugin` (criar, testar e publicar plugins), em TypeScript e Node ([Build System](../docs/specs/05-build-system-specification.md), [Plugin SDK §13](../docs/specs/03-plugin-sdk-specification.md), [spec 09 §1](../docs/specs/09-repositories-and-code-layout.md)).

Tag `cli-v<versão>`, publicada no npm (`vnstudio`, `vnplugin`). Os schemas vêm de `docs/specs/schemas/` no build, sem cópia editada à mão: `docs/specs/tools/sync_generated_copies.py cli` gera `cli/schemas/`, fora do Git, para o pacote npm.

Ainda vazio. O pacote chega com o workspace TypeScript (M0-06).
