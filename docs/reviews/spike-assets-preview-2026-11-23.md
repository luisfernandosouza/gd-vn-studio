# Spike M4-01: assets por bytes no painel do Preview (teste B)

Data: 2026-11-23. Issue: #67 (M4-01). Refs: README das specs ("A conferir no primeiro protótipo"), PP §1.3, D18, D24.

**Decisão: seguir com o carregador de bytes da D18, sem mudar as specs.** O painel abriu as 200 imagens de 1920 × 1080 e as 30 músicas nos motores do Tauri, trocou a imagem e a música em uso e mostrou os bytes novos em todos os casos. Três ajustes ficam para a implementação do `VNAssets` (M4-07, #73), nenhum deles muda decisão das specs:

1. **Ler os bytes pelo `fetch` da página**, entregues ao Godot com `JavaScriptBridge.js_buffer_to_packed_byte_array`, e não pelo `HTTPRequest`: o `HTTPRequest` no Web lê o corpo um pedaço por quadro e ficou de 1,7 a 8,5 vezes mais lento na leitura de um PNG de 3,3 MB. Além disso, o spike M4-02 (#131) viu que o `HTTPRequest` recusa URLs `vnpreview://`, que é a origem do painel no macOS e no Linux; o `fetch` da página funcionou ali.
2. **Cache com limite.** Cada fundo de 1920 × 1080 vira uma textura RGBA8 de 7,9 MiB (o Preview não comprime, PP §1.3), então 200 fundos ocupam 1,55 GiB e levam o processo do motor a 2,4 a 2,6 GB. Com um LRU de 16 recursos, as mesmas 200 imagens passam pela tela com 134 MiB de texturas e o processo fica estável perto de 1 GB. No WebKitGTK a memória do processo não volta depois que o cache é esvaziado, então o limite tem que valer desde o início, não como faxina posterior.
3. **Ler sem cache do navegador** (`fetch(url, { cache: 'no-store' })`, e o protocolo `vnpreview` respondendo `Cache-Control: no-store` para `/project/assets/`): é o que garante que a troca `/assets/<id>` (PP §3) traga o arquivo novo, e não a cópia antiga do cache HTTP do webview.

## O que foi medido

Bancada em [`spikes/preview-assets/`](../../spikes/preview-assets/README.md) (pasta temporária): um carregador mínimo em GDScript (`godot/vn_assets_spike.gd`) e o cenário na página que faz o papel do Studio (`harness/assets.js`).

- **Assets** (`tools/make_assets.py`, sintéticos e fora do Git): 200 imagens de 1920 × 1080 com cara de fundo (gradiente, formas e ruído leve), sendo 140 PNG (3,3 MB em média, 461 MB no total), 40 JPG (0,28 MB) e 20 WebP (0,08 MB); 30 músicas de 3 min, 24 OGG Vorbis (2,2 MB) e 6 MP3 a 192 kbps (4,3 MB). Alguns nomes têm acento e espaço (`cenários/`, `praia à noite 007.png`, `tema da praia 05.ogg`).
- **Caminhos como na D24:** o mapa de assets é o do bundle (`res://vn_content/assets/…`), e o carregador troca o prefixo por `assets_base` e codifica cada segmento (RFC 3986) antes de ler. Cada imagem tem um bloco de cor-marca que o runtime devolve depois de decodificar; todas as 200 vieram certas em todos os motores, inclusive as de nome acentuado.
- **Cenários:** (1) as 200 imagens passam pela tela uma a uma com cache LRU de 16; (2) motor novo, as 200 imagens e as 30 músicas ficam todas no cache (o teste B como o README pede); (3) troca da imagem em uso, 20 vezes, e da música em uso, 10 vezes, com o Studio gravando o arquivo novo por cima do do autor e mandando a troca; (4) esvaziar o cache; (5) 20 PNG pelo `HTTPRequest`, pelo `fetch` e com mipmaps.
- **Memória:** heap do WASM (tamanho da `WebAssembly.Memory` do motor), texturas (`RENDERING_INFO_TEXTURE_MEM_USED`) e memória residente somada dos processos do motor do webview.
- **Tempo:** da chamada na página até o quadro com a imagem desenhado (ou a música trocada), dividido em leitura, decodificação e criação da textura.

## Resultados

### Carga de uma imagem (cenário 2, p50 em ms, do pedido ao quadro desenhado)

| Motor (máquina) | PNG 3,3 MB | JPG | WebP | leitura PNG | decodificação PNG | 200 imagens, total |
|---|---|---|---|---|---|---|
| Chromium (Linux, 4 vCPU, sem GPU) | 178 | 116 | 128 | 137 | 31 | 32,6 s |
| WebKitGTK 2.52.6 (Linux, sem GPU) | 91 | 38 | 51 | 43 | 32 | 15,4 s |
| WKWebView (macOS, runner do GitHub, M2 Pro virtual, GPU) | 50 | 25 | 34 | 8 | 33 | 9,0 s |
<!-- windows-carga -->

A criação da textura custa 1 a 7 ms. A decodificação é a mesma em todos os motores (é código do Godot no WASM): ~31 ms por PNG, ~15 ms por JPG, ~28 ms por WebP; os mipmaps somam ~3 ms. A leitura varia com o motor. No Chromium sem GPU ela tem um custo fixo de ~90 ms por arquivo, que aparece igual quando a própria página lê o arquivo sem o Godot (134 ms para o PNG), então vem do motor desenhando na CPU, não da ponte.

### Memória (MB)

| Motor | Motor aberto | 200 imagens no cache | + 30 músicas | Cache esvaziado | 200 imagens com LRU de 16 |
|---|---|---|---|---|---|
| Texturas (todos os motores) | 7 | 1.589 | 1.589 | 7 | 134 |
| Heap do WASM (todos os motores) | 38 | 46 | 138 | 244 | 46 |
| Processos do Chromium (Linux) | 952 | 2.581 | 2.668 | 1.990 | 1.109 |
| Processos do WebKitGTK (Linux) | 892 | 2.414 | 2.524 | 3.581 | 1.030 |
| Processos da WKWebView (macOS) | 1.035 | 2.581 | 2.666 | 2.318 | 1.031 |
<!-- windows-memoria -->

- **Texturas:** 7,9 MiB por fundo, linear no número de imagens. É o custo esperado de não comprimir no Preview (PP §1.3 já admite memória diferente do jogo).
- **Heap do WASM:** quase não cresce com as imagens (o buffer de decodificação é reaproveitado), mas guarda as músicas inteiras (os OGG e MP3 ficam comprimidos na memória, perto do tamanho do arquivo: +92 MB para 78 MB de áudio) e nunca encolhe. Depois das trocas de música e de esvaziar o cache ficou em 244 MB, longe do limite de 2 GB do WASM32.
- **Processo:** o Chromium devolve parte da memória ao esvaziar o cache; o WebKitGTK não devolve (subiu para 3,6 GB depois das trocas e do cache esvaziado). Daí o ajuste 2.

### Troca de um asset em uso (p50 / p95 em ms, do arquivo gravado ao quadro com o asset novo)

| Motor | Imagem PNG em uso (20 trocas) | Música OGG em uso (10 trocas) |
|---|---|---|
| Chromium (Linux) | 206 / 219 | 285 / 458 |
| WebKitGTK (Linux) | 94 / 100 | 213 / 413 |
| WKWebView (macOS) | 48 / 54 | 138 / 299 |
<!-- windows-troca -->

Em todas as trocas a tela mostrou a imagem nova (cor-marca conferida) e a música nova (duração conferida), e a música continuou do mesmo ponto. A troca não reinicia o motor nem a cena.

### Leitor: `fetch` da página contra `HTTPRequest` (20 PNG, leitura p50 em ms)

| Motor | `fetch` + `js_buffer_to_packed_byte_array` | `HTTPRequest` (pedaços de 4 MB) |
|---|---|---|
| Chromium (Linux) | 130 | 220 |
| WebKitGTK (Linux) | 27 | 177 |
| WKWebView (macOS) | 12 | 102 |
<!-- windows-leitor -->

### Música

As 30 músicas carregaram em 0,8 s (WKWebView) a 4,2 s (Chromium Linux), 17 a 172 ms cada; a "decodificação" é só montar o stream (3 a 7 ms), porque o Godot decodifica o áudio enquanto toca. No Chromium e na WKWebView a posição andou 2,0 s em 2 s, isto é, tocou em tempo real. No WebKitGTK do contêiner não há saída de som, e a posição não andou; não é falha do carregador, mas a reprodução nesse motor fica para conferir numa máquina com som.

## Limites

- **GPU.** As medidas do Linux são sem GPU (SwiftShader e llvmpipe desenham na CPU, e a "memória de texturas" fica no processo). <!-- limites-ci -->
- **HTTP, não `vnpreview://`.** O spike serve os assets por HTTP local. Servir pelo protocolo do Tauri é o item seguinte do README (M4-02); o carregador não depende disso, porque `assets_base` é só o começo da URL.
- **Sem SVG, WAV e fontes.** O teste B pede imagens e músicas; os outros formatos da PP §1.3 entram nos testes do M4-07.
- **Assets sintéticos.** Os PNG têm o tamanho de arte real, mas fundos pintados à mão podem comprimir mais ou menos; o custo de textura não muda, porque depende só da resolução.

## Para a implementação (M4-07)

- Leitor por `fetch` da página com `no-store`, e o `vnpreview` com `Cache-Control: no-store` nos assets.
- Cache LRU limitado por memória de textura (por exemplo, 256 MiB), sempre ligado no painel; o recurso em uso na tela nunca é descartado.
- A troca `/assets/<id>` descarta o id e recarrega só o que está em uso, como o spike fez; música em uso continua da mesma posição.
- Como uma imagem leva de 40 a 180 ms para chegar à tela sem GPU, vale pré-carregar os assets do próximo bloco de nós enquanto o jogador lê (comportamento do runtime, não do protocolo).
