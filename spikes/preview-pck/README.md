# Spike M4-02: `vnpreview://`, plugins como `.pck` e template enxuto

> **Pasta temporária.** Código descartável, só para medir. Sai junto com `.github/workflows/preview-pck-spike.yml` quando o Preview real chegar (M4-04, M6-10); os resultados ficam no README das specs (decisões de 2026-11-23) e no histórico do Git.

Fecha as pendências "A conferir no primeiro protótipo" do README das specs (seção de 2026-11-15), salvo o teste B dos assets, que é a M4-01:

1. **Servir por `vnpreview://`** no WebView2, na WKWebView e no WebKitGTK, com `application/wasm` (PP §1.1).
2. **Plugins como `.pck`**: `class_name` num pacote montado depois do boot, troca do pacote e tempo de gerar o `.pck` a cada salvamento (PP §1.3, SDK §10.6).
3. **Template enxuto**: tempo de abrir o painel.

## Resultados

Godot 4.7.2, export Web sem threads, runners do GitHub (Windows e Linux sem GPU; macOS em Apple Silicon virtual), workflow `Spike Preview PCK` do PR #131. Cada abertura vai da criação do iframe até o primeiro quadro desenhado pelo runtime (`spike.ready`).

### 1. `vnpreview://` nos três motores: funciona

| Motor | Origem | `.wasm` | Compilação em streaming | Contexto seguro |
|---|---|---|---|---|
| WebView2 (Windows, Edge 157) | `http://vnpreview.localhost` | `application/wasm` | sim (532 ms) | sim |
| WKWebView (macOS) | `vnpreview://localhost` | `application/wasm` | sim (235 ms) | sim |
| WebKitGTK 4.1 (Linux) | `vnpreview://localhost` | `application/wasm` | sim (694 ms) | sim |

- O app (`tauri/src/vnpreview.rs`) responde só aos três prefixos do PP §1.1. Nos três motores, pedidos de dentro da página para `%2e%2e`, `..%2f`, `/project/segredo.txt`, `/segredo.txt` e o caminho absoluto de um arquivo fora do projeto deram 404; os testes do Rust cobrem também `\`, `:`, NUL, `//`, link simbólico que sai da pasta e métodos que não são GET/HEAD.
- O asset `assets/música de teste/olá mundo.txt`, com os segmentos codificados, chegou igual (SHA-256 conferido) pelo `fetch` do navegador.
- **O `HTTPRequest` do Godot não aceita a origem `vnpreview://`** (macOS e Linux): `request()` devolve `ERR_INVALID_PARAMETER`, porque só aceita `http` e `https`. No Windows, onde a origem é `http://vnpreview.localhost`, funciona. No painel, o runtime lê bytes (`.pck`, assets, bundle) pelo `fetch` do navegador via `JavaScriptBridge` (`host/main.gd`, `_js_fetch`): o `ArrayBuffer` vira `PackedByteArray` por `JavaScriptBridge.eval`.

### 2. Plugins como `.pck`: funciona, sem o plano B

| Medida | Linux nativo (`--main-pack`) | WebView2 | WKWebView | WebKitGTK |
|---|---|---|---|---|
| `class_name` de um pacote montado depois do boot | sim | sim | sim | sim |
| Ler o `.pck` (fetch) + gravar em `/tmp` + montar | 0,1 ms (só montar) | 28 + 0,2 + 0,4 ms | 10 + 1 + 0 ms | 6 + 0 + 0 ms |
| Trocar o pacote e recarregar o plugin | 2,4 ms | 5,9 ms | 6 ms | 9 ms |

- Ao montar um pacote, o Godot 4.7 chama `refresh_global_class_list()` e registra os `class_name` do pacote (`core/config/project_settings.cpp`). O plugin de pesca do exemplo, sem mudança (`var _game: FishingGame`, `preload` da cena), e o plugin de prova (`class_name` como tipo, `.new()`, constante, método estático, cena com `class_name`, herança de `VNRuntimePlugin` do pacote principal) funcionaram. O pacote v2 trouxe um `class_name` que não existia no boot (`ProbeExtra`), e ele também funcionou.
- **Recarga:** `ResourceLoader.load(path, "", CACHE_MODE_REPLACE_DEEP)` **não** relê um GDScript: o `GDScriptCache` devolve o script antigo. Com `CACHE_MODE_IGNORE`, o cache relê o arquivo do pacote (`.gd` ou `.gdc`) e recompila o mesmo objeto `Script`; uma passada pelos scripts do plugin bastou (as constantes de outro script não ficam embutidas).
- **Cada geração precisa de um nome de arquivo novo.** O Godot não desmonta pacotes e lê cada arquivo de um pacote montado direto do `.pck` (offset guardado na montagem); sobrescrever o arquivo de um pacote em uso corromperia o que ainda não foi lido. Um arquivo apagado do plugin continua visível até o motor reabrir.
- **O cache de classes do export do editor é um problema.** `--export-pack` põe no pacote `project.binary`, `uid_cache.bin` e um `global_script_class_cache.cfg` com todas as classes do projeto de trabalho, inclusive as do SDK, com os caminhos dele; ao montar, o runtime registraria essas classes por cima das suas. O caminho rápido (abaixo) grava só as classes do plugin.
- No painel, o `.pck` vai para o sistema de arquivos em memória do Emscripten (`/tmp/vnpreview/…`), não para `user://` (D25).

### 3. Tempo de gerar o `.pck` a cada salvamento (plugin de pesca, 10 salvamentos)

| Caminho | Linux | macOS | Windows |
|---|---|---|---|
| Export do editor (`godot --headless --export-pack`), p50 | 2.712 ms | — | — |
| Caminho rápido (`--script tools/pack_plugin.gd`, sem editor), p50 / p95 | **160 / 165 ms** | **271 / 380 ms** | **305 / 325 ms** |
| Primeira geração (import headless + pacote) | 3,0 a 7,2 s | 3,5 s | 8,7 s |

Quase todo o tempo do export do editor é abrir o editor (`--editor --quit` sozinho leva 2,8 s). O caminho rápido roda o Godot sem editor e empacota com `PCKPacker` os arquivos em texto como estão (`.gd`, `.tscn`, `.tres`, `.json`…), que o Godot carrega sem compilar, mais os assets já importados (`.import` e `.godot/imported/`). O import headless só roda na primeira vez e quando um asset do plugin muda.

### 4. Template enxuto

| Motor | Oficial (39,5 MB): primeira / reabertura p50 | Enxuto (28,2 MB): primeira / reabertura p50 |
|---|---|---|
| WebView2 (Windows, sem GPU) | 5.816 / 5.491 ms | 4.808 / 4.826 ms |
| WKWebView (macOS) | 2.588 / 867 ms | 725 / 698 ms |
| WebKitGTK (Linux, sem GPU) | 2.978 / 2.562 ms | 1.828 / 1.989 ms |

- O enxuto abre de 12% a 72% mais rápido e o plugin de pesca roda nele. Mas ele tira módulos que um plugin pode usar (3D, física 3D, GLTF, rede, WebSocket, CSG…) e é compilado com `deprecated=no`, então um plugin que funciona no jogo exportado poderia falhar só no painel, contra o "mesmo resultado" do PP §1.3. Compilar leva ~16 min na CI (com cache por versão).
- No WebView2, servido por `vnpreview`, reabrir não fica mais rápido: o motor compila o WASM de novo a cada abertura, como o WebKitGTK. O teste de 2026-11-15 por HTTP, numa máquina com GPU, tinha dado 4,7 s na primeira abertura e 0,9 s com cache. Como o painel fica aberto entre edições (PP §1.1, item 4), isso pesa só ao abrir o Preview.
- **Decisão do Luis (2026-11-23): o painel usa o template oficial** (README das specs, decisões de 2026-11-23).

### Pendência nova

O protocolo ainda não diz onde o runtime acha o `.pck` de cada plugin: `preview.load` e `preview.reload_plugins` (`ids`) não trazem o caminho, e o nome muda a cada geração. Fica para a M4-05 (métodos do Preview) propor o campo.

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
