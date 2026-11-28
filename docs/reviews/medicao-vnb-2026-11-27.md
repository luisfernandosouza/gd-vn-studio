# Medição do `.vnb` (M5-03, Build System §15 item 4)

Pendência: medir o tempo de decifrar e descomprimir um `.vnb` de 10 MB, para confirmar AES-CBC + Zstandard no boot, sobretudo no Web.

## Método

`cli/scripts/vnb_roundtrip.mjs prepare` gera um JSON canônico sintético de 10 485 799 bytes (eventos de diálogo com texto variado), grava como `.vnb` cifrado (Zstandard 19 + AES-256-CBC) e `runtime/tests/boot/test_vnb_roundtrip.gd` mede `VNBundleLoader.decode_vnb` (decifrar, descomprimir, SHA-256 do JSON), melhor de 5.

## Resultado (Godot 4.7.2 nativo, Linux x86_64, `--headless`)

| Arquivo | `.vnb` | JSON | Tempo |
|---|---|---|---|
| `narrative.vnb` da demo | 7 164 B | 30 855 B | 0,2 ms |
| sintético de 10 MB | 203 420 B | 10 485 799 B | 33 ms |

## Limites

- O JSON sintético comprime ~50x, mais que um bundle real (vocabulário pequeno). O custo de decifrar é proporcional ao tamanho **comprimido**, então o número tende a subir para bundles reais; o de descomprimir e do SHA-256 acompanha o JSON de 10 MB.
- Foi medido o Godot nativo. **A medição no Web (WASM, sem threads) continua pendente**: exige exportar o runtime para Web e rodar num navegador, o que não cabe na CI atual (o spike `preview-pck` tem o template Web). O item 4 do BS §15 só fecha com esse número; a CI imprime a medição nativa em cada execução (`GITHUB_STEP_SUMMARY`).
