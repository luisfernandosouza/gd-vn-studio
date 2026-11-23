# Spike M4-02: `vnpreview://`, plugins como `.pck` e template enxuto

> **Pasta temporária.** Código descartável, só para medir. Sai junto com `.github/workflows/preview-pck-spike.yml` quando o Preview real chegar (M4-04, M6-10); os resultados ficam no README das specs (decisões de 2026-11-23) e no histórico do Git.

Fecha as pendências "A conferir no primeiro protótipo" do README das specs (seção de 2026-11-15), salvo o teste B dos assets, que é a M4-01:

1. **Servir por `vnpreview://`** no WebView2, na WKWebView e no WebKitGTK, com `application/wasm` (PP §1.1).
2. **Plugins como `.pck`**: `class_name` num pacote montado depois do boot, troca do pacote e tempo de gerar o `.pck` a cada salvamento (PP §1.3, SDK §10.6).
3. **Template enxuto**: tempo de abrir o painel.

RESULTADOS_AQUI

## O que tem aqui

| Pasta | O que é |
|---|---|
| `host/` | O "runtime" do spike: projeto Godot 4.7.2 mínimo que fala JSON-RPC pela ponte do PP §1.1 (`vnPreview.send`/`onmessage`) e monta `.pck` de plugin. Não é o runtime do v1. `addons/vn_runtime_sdk/` é o stub do SDK do spike de 2026-11-15 |
| `plugins/probe/` | Plugin de prova: `class_name` usado como tipo, com `.new()`, constante e método estático; uma cena com `class_name`; e, no pacote v2, um `class_name` novo (`ProbeExtra`) |
| `tauri/` | App Tauri 2 mínimo que faz o papel do Studio: registra `vnpreview` com o mapa fixo de três prefixos (`src/vnpreview.rs`, com testes) e abre o runtime num iframe (`ui/index.html`) |
| `tools/make_pck.py` | Gera o `.pck` de um plugin a partir da cópia em `.vnstudio/preview/plugins/<namespace>/`, pelo export do editor (`--mode export`) ou pelo caminho rápido (`--mode fast`, `tools/pack_plugin.gd`) |
| `tools/build_lean_template.sh` | Compila o template Web enxuto |
| `tools/export_host.sh`, `prepare_project.py`, `check_results.py` | Exportação, projeto de teste e conferência dos resultados na CI |

## Como rodar

```bash
# Godot 4.7.2 com o template Web; opcional: o template enxuto (precisa do emsdk 4.0.11 e do scons)
tools/build_lean_template.sh <godot-src> build/templates/web_lean_nothreads_release.zip
LEAN_TEMPLATE=build/templates/web_lean_nothreads_release.zip tools/export_host.sh

# .pck dos plugins e tempo de geração
python3 tools/make_pck.py --plugin ../../docs/specs/examples/fishing-plugin --namespace fishing --work /tmp/w/fishing --out build/pck/fishing.pck
python3 tools/make_pck.py --plugin plugins/probe --namespace probe --work /tmp/w/probe --out build/pck/probe-v1.pck
python3 tools/make_pck.py --plugin plugins/probe --namespace probe --work /tmp/w/probe --out build/pck/probe-v2.pck --variant v2
python3 tools/make_pck.py --plugin ../../docs/specs/examples/fishing-plugin --namespace fishing --work /tmp/w/bench --out /tmp/b.pck --bench 10

# Roteiro de plugins no runtime nativo (o pacote principal abre com --main-pack, PP §1.2)
godot --headless --main-pack build/native/runtime-preview.pck -- --spike-pck build/pck

# Bancada no webview (no Linux, com xvfb-run); os ícones vêm de `npm run icons` do Studio
python3 tools/prepare_project.py build/pck /tmp/bench
cd tauri && cargo build --release && cd ..
SPIKE_RUNTIME=$PWD/build/web SPIKE_PROJECT=/tmp/bench/project SPIKE_OUT=/tmp/r.json tauri/target/release/vnpreview-spike
```
