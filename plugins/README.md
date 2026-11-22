# Plugins oficiais

Minijogos oficiais (`vnstudio.*`), um projeto de desenvolvimento Godot por pasta, no mesmo formato do repositório de um plugin avulso ([spec 09 §1 e §2](../docs/specs/09-repositories-and-code-layout.md), [Plugin SDK §2.4](../docs/specs/03-plugin-sdk-specification.md)).

```text
plugins/fishing/
├── project.godot               # Git
├── sandbox/                    # Git: cena de teste (sandbox.tscn)
├── .vnplugin/                  # Git: versão do Godot; local.json fica fora
├── addons/vn_runtime_sdk/      # fora do Git: `vnplugin doctor --fix` restaura
├── .godot/                     # fora do Git
└── vn_plugins/fishing/         # o plugin: só esta pasta vira o .vnplugin
```

- Os assets de cada plugin oficial são originais e têm a licença declarada no próprio plugin. Mídia só pode ficar em `plugins/*/vn_plugins/*/runtime/` e `plugins/*/sandbox/` (spec 09 §1.1; conferido por `repo-hygiene.yml`).
- Tag `plugin-<namespace>-v<versão>` (ex.: `plugin-fishing-v1.0.0`), com o `.vnplugin` na Release.
- Enquanto `plugins/fishing/` não tem código, o exemplo das specs em `docs/specs/examples/fishing-plugin/` é a referência. Quando o plugin oficial existir (tarefa M3-08), o exemplo passa a ser gerado a partir dele pela CI.
