# Spike: Preview com um interpretador só (export Web do runtime)

Teste da proposta A ("Propostas: Preview e estado normativo das specs"): o runtime Godot exportado para Web, embutido numa página que faz o papel do Studio, consegue recarregar o conteúdo em menos de 1 s depois de uma edição? Se conseguir, o interpretador TypeScript do Preview no Studio deixa de ser necessário.

**Resultado: passa com folga, desde que o Preview use recarga incremental e receba o conteúdo em memória.** Num bundle de 405 cenas e 20 mil falas (3,55 MB), a fala editada aparece em 20 ms (p95). Sem as otimizações, o mesmo bundle leva 3,7 s.

Isto é um spike, não o runtime: o `main.gd` só mostra falas e escolhas, aplica fundos e anda pela lista de nós. O stub do SDK (`addons/vn_runtime_sdk/`) tem só o que o plugin de pesca usa.

## Resultados

Godot 4.7.2, export Web sem threads, Chromium headless com SwiftShader (sem GPU), 4 vCPUs Xeon 2,1 GHz. Cada linha é o tempo de ponta a ponta, da edição na página até o quadro com o texto novo desenhado, em 20 edições. As otimizações se acumulam de cima para baixo.

### Recarga depois de editar uma fala

| Caminho | Demo (5 cenas, 28 KB) p50 / p95 | Bundle grande (405 cenas, 3,55 MB) p50 / p95 |
|---|---|---|
| Base: grava o bundle canônico e reinicia o motor | 1.489 / 1.581 ms | 3.237 / 3.702 ms |
| Otimização 3: motor sempre aberto | 189 / 223 ms | 1.951 / 2.055 ms |
| Otimização 2: + bundle em memória, sem recalcular hash | 30 / 42 ms | 145 / 175 ms |
| Otimização 1: + recarga incremental (só a cena) | 26 / 36 ms | **16 / 20 ms** |

Para onde vai o tempo no bundle grande, sem as otimizações 1 e 2: leitura do arquivo pelo `HTTPRequest` do Godot (1,2 a 1,3 s), JCS e SHA-256 no Studio (~260 ms), JCS e SHA-256 no runtime em GDScript (200 a 330 ms) e `JSON.parse_string` (40 a 70 ms). O hash calculado em GDScript confere com o do compilador de referência nos dois bundles.

### Abertura do Preview e outros critérios

| Medida | Template oficial (39,5 MB) | Template enxuto (28,2 MB) |
|---|---|---|
| Primeira abertura, sem cache | 1.233 ms | 844 ms |
| Abertura com cache (otimização 5), p50 / p95 | 756 / 1.246 ms | 588 / 608 ms |

| Critério da proposta A | Meta | Medido |
|---|---|---|
| Recarga depois de uma edição (bundle grande, p95) | < 1 s | 20 ms (incremental), 175 ms (bundle inteiro em memória) |
| Primeira abertura do Preview | < 5 s | 0,84 a 1,23 s |
| Pular para uma cena com estado escolhido | sem reiniciar | 31 ms p95 no bundle grande (`start` com cena, nó e variáveis) |
| Minijogo do plugin de pesca | GDScript real, sem mock | roda: o overlay abre em 62 ms p95, com o `fishing_plugin.gd` e o `fishing_game.tscn` do exemplo |

O template enxuto (otimização 4) é o oficial compilado com `disable_3d=yes`, `optimize=size` e sem 33 módulos que uma VN não usa (física 3D, XR, GLTF, rede, compressão de texturas de GPU etc.). Ver `tools/build_lean_template.sh`.

### WebKitGTK (motor do Tauri no Linux)

WebKitGTK 2.52 (`webkit2gtk-4.1`, o mesmo do Tauri 2), sob Xvfb, desenho na CPU (Mesa llvmpipe), mesma máquina. Rodado por `tools/webkitgtk_bench.py`.

| Caminho (acumulado) | Demo p50 / p95 | Bundle grande p50 / p95 |
|---|---|---|
| Motor sempre aberto | 187 / 263 ms | 2.293 / 2.437 ms |
| + bundle em memória | 28 / 31 ms | 148 / 189 ms |
| + recarga incremental | 29 / 31 ms | **32 / 40 ms** |

| Medida | Template oficial | Template enxuto |
|---|---|---|
| Primeira abertura (processo novo) | 3.411 ms | 2.386 ms |
| Abertura de novo no mesmo processo, p50 | 3.523 ms | 2.418 ms |

O salto para uma cena com variáveis levou 33 ms (p95) e o minijogo de pesca abriu em 155 ms (p95). A recarga fica igual à do Chromium; a diferença está na abertura, 2 a 3 vezes mais lenta, porque o WebKit compila o WASM de novo a cada abertura (não guarda o código compilado em cache como o Chromium). Mesmo assim fica abaixo da meta de 5 s.

Reiniciar o motor a cada edição fica muito pior no WebKitGTK (7 a 22 s), e a abertura piora a cada nova instância do motor no mesmo processo. É mais um motivo para o Preview nunca reiniciar o motor (otimização 3).

### Windows com GPU (Edge, o motor do WebView2)

Ryzen 5 5600G, NVIDIA RTX 3060 (ANGLE D3D11), Edge 157, export oficial. Rodado por `node tools/bench.mjs --browser chromium --channel msedge --gpu`.

| Caminho (acumulado) | Demo p50 / p95 | Bundle grande p50 / p95 |
|---|---|---|
| Base: grava o bundle e reinicia o motor | 913 / 965 ms | 1.302 / 1.549 ms |
| Motor sempre aberto | 34 / 41 ms | 886 / 990 ms |
| + bundle em memória | 4,1 / 4,6 ms | 181 / 220 ms |
| + recarga incremental | 4,1 / 4,6 ms | **4,0 / 4,6 ms** |

Abertura: 4,65 s na primeira vez (sem cache) e 0,93 s (p50) com cache. Salto para uma cena: 4,8 ms (p95). Minijogo de pesca: 5,1 ms (p95). Com GPU, a recarga incremental fica 4 a 8 vezes mais rápida que sem GPU; a parte que depende de CPU (ler o arquivo, JCS, hash e parse do bundle inteiro) melhora pouco, então as otimizações 1 e 2 continuam necessárias. O Chromium do Playwright não abriu nesta máquina (erro de configuração lado a lado do Windows), mas o Edge é o mesmo motor do WebView2 que o Tauri usa no Windows.

### macOS (runner do GitHub, Apple M2 Pro virtual, GPU via Metal)

Workflow `.github/workflows/preview-web-spike.yml`; números em `results-2026-11-15-macos.json`.

| Caminho, p50 / p95 | Chromium, demo | Chromium, bundle grande | Safari/WebKit, demo |
|---|---|---|---|
| Reinicia o motor | 465 / 794 ms | 1.781 / 2.140 ms | 1.326 / 3.841 ms |
| Motor sempre aberto | 100 / 111 ms | 1.420 / 1.443 ms | 311 / 321 ms |
| + bundle em memória | 16 / 18 ms | 128 / 132 ms | 32 / 37 ms |
| + recarga incremental | 17 / 19 ms | **17 / 18 ms** | **16 / 19 ms** |

Abertura: Chromium 3,0 s sem cache e 0,34 s com cache; WebKit 1,9 s e 0,6 s. Os ~16 ms do caminho incremental são um quadro a 60 Hz: com GPU o tempo fica preso ao vsync.

O WebKit (motor do Safari) travou no bundle grande, na rodada que reinicia o motor 20 vezes, e o job bateu o limite de 60 min; os outros caminhos do bundle grande não rodaram no WebKit. A WKWebView (`tools/wkwebview_bench.swift`) não devolveu resultado em 25 min. Falta repetir essas duas sem a rodada de reinício.

## O que isso significa para as specs

1. **Um interpretador basta.** O Preview no Studio pode ser o próprio runtime exportado para Web. Sai o interpretador TypeScript, o `renderActivityMock` do SDK §10.6 e a obrigação de manter JCS, aritmética, formatação, RNG e Scheduler em duas linguagens.
2. **A recarga precisa ser incremental e em memória.** O `preview.reload` do PP §3 recebe hoje `bundle_path` e o runtime relê a pasta. Para ficar abaixo de 1 s num jogo grande, o Preview Web deve receber a cena ou o arquivo de idioma alterado pela ponte JavaScript, sem gravar arquivo, sem `HTTPRequest` e sem recalcular o `content_hash` (que continua valendo no jogo exportado e no boot).
3. **O template enxuto vale a pena, mas não é obrigatório.** Ele corta 30% da primeira abertura, mas o template oficial já cumpre a meta.

## Limites do teste

- **GPU só no Windows.** No Linux e na primeira rodada, SwiftShader e llvmpipe desenham na CPU; com GPU (Windows) tudo fica mais rápido.
- **macOS incompleto.** Chromium e WebKit medidos no runner do GitHub; falta o bundle grande no WebKit e a WKWebView.
- **Sem assets.** O spike não carrega imagens, áudio nem vídeo. A proposta B (carregador `VNAssets`) precisa de um teste separado, inclusive de como os bytes chegam do Studio ao runtime Web.
- **Runtime mínimo.** O runtime de verdade terá Scheduler, State Manager e UI completos; a parte medida aqui (parse, troca da cena e redesenho) é a que cresce com o tamanho do jogo.

## Como rodar

```bash
# 1. Godot 4.7.2 e os templates de exportação Web instalados
GODOT=/caminho/do/godot tools/export.sh                 # exporta para build/web (e build/web-lean, se houver o template enxuto)
# opcional: tools/build_lean_template.sh <godot-src>    # precisa do emsdk 4.0.11 e do scons
python3 tools/make_bundles.py build/bundles             # bundle do demo e bundle grande sintético
node tools/bench.mjs --edits 20 --templates web,web-lean  # grava build/results.json
```

A bancada usa o Playwright e o Chromium; `harness/index.html` é a página que faz o papel do Studio.
