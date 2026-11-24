# Índice oficial de plugins

`official.json` é o `catalog:official` do v1 (Plugin SDK §13.2, spec 09 §1, decisão D11): lista só os plugins oficiais (publisher `vnstudio`). O Studio, a CLI e o Build System o leem de `https://raw.githubusercontent.com/luisfernandosouza/gd-vn-studio/main/catalog/official.json`; ele não entra em nenhum artefato.

Quem escreve é a CI de release, por pull request, a cada tag `plugin-<namespace>-v<versão>`; a revogação é outro pull request no mesmo arquivo (`vnplugin revoke`). Ninguém edita à mão fora desses dois casos.

Formato (lido por `cli/src/plugins/catalog.ts`):

```json
{
  "catalog_version": 1,
  "plugins": [
    {
      "id": "vnstudio.fishing",
      "namespace": "fishing",
      "versions": [
        {
          "version": "1.0.0",
          "url": "https://github.com/luisfernandosouza/gd-vn-studio/releases/download/plugin-fishing-v1.0.0/vnstudio.fishing-1.0.0.vnplugin",
          "integrity": "sha256-…",
          "state": "published",
          "trust": "official",
          "revoked": { "reason": "…" }
        }
      ]
    }
  ]
}
```

`revoked` só aparece numa versão retirada (SDK §13.3): ela deixa de ser instalada, e o build de um projeto que já a usa falha com B003 até o autor atualizar ou confirmar. Está vazio até a primeira Release do fishing.
