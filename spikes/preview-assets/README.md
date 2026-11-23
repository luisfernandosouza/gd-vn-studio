# Spike: assets por bytes no painel do Preview (teste B, M4-01)

> **Pasta temporária.** Código descartável, só para medir. Apagar esta pasta e `.github/workflows/preview-assets-spike.yml` quando o `VNAssets` do runtime (M4-07) tiver os próprios testes; os números ficam no relatório.

Relatório com os números e a decisão: [`docs/reviews/spike-assets-preview-2026-11-23.md`](../../docs/reviews/spike-assets-preview-2026-11-23.md).

O que mede (D18, PP §1.3, D24): 200 imagens de 1920 × 1080 e 30 músicas abertas no runtime exportado para Web pelo carregador de bytes, com os caminhos `res://vn_content/assets/…` do bundle trocados por `assets_base`; memória (heap do WASM, texturas, processos do webview), tempo até o quadro desenhado e troca de um asset em uso. Segue a bancada do spike do Preview Web de 2026-11-15 (já apagada), com o mesmo jeito de medir: a página faz o papel do Studio e o runtime avisa quando o quadro foi desenhado.

Não é o runtime: `godot/main.gd` só mostra uma imagem e toca uma música.

| Arquivo | O que faz |
|---|---|
| `godot/vn_assets_spike.gd` | carregador mínimo: troca do prefixo, leitura (`fetch` da página ou `HTTPRequest`), `ImageTexture` / `AudioStreamOggVorbis` / `AudioStreamMP3`, cache com LRU opcional |
| `godot/main.gd` | ponte JavaScript: `assets_config`, `assets_load`, `assets_reload`, `assets_clear`, `assets_stats` |
| `harness/index.html`, `harness/assets.js` | a página do "Studio" e o cenário do teste |
| `harness/wasm_hook.js` | entra no `<head>` do export e guarda a memória do WASM, para medir o heap |
| `tools/make_assets.py` | gera os assets sintéticos em `build/assets/` (fora do Git, spec 09 §1.1) |
| `tools/serve.mjs` | servidor da bancada, com `POST /swap` (o autor salvou o arquivo de novo) e `GET /rss` (memória dos processos) |
| `tools/assets_bench.mjs` | roda no Chromium, no Edge ou no WebKit do Playwright |
| `tools/webkitgtk_bench.py`, `tools/wkwebview_bench.swift` | rodam no WebKitGTK (Linux) e na WKWebView (macOS) |
| `tools/summary_assets.py` | resume os resultados |
| `results-2026-11-23-assets-*.json` | resultados usados no relatório |

## Como rodar

```bash
GODOT=/caminho/do/godot tools/export.sh                  # Godot 4.7.2 e o template Web sem threads
python3 tools/make_assets.py build/assets                # 200 imagens e 30 músicas (numpy, Pillow e ffmpeg)
node tools/assets_bench.mjs --browser chromium           # ou --channel msedge [--gpu]; grava build/results-assets-<motor>.json
xvfb-run -a -s "-screen 0 1920x1080x24" tools/webkitgtk_bench.py 8766 20   # WebKitGTK
python3 tools/summary_assets.py build/results-assets-*.json
```

A WKWebView e o Edge rodam na CI (`.github/workflows/preview-assets-spike.yml`, manual ou a cada push no branch do spike).
