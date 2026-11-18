# Build System Specification — v1.0.0-draft

- **Status:** rascunho para revisão
- **Base:** Architecture Design Document v0.1, seções 7, 13.6 e 15; [Narrative Runtime Specification](02-narrative-runtime-specification.md) §2 e §8; [Plugin SDK Specification](03-plugin-sdk-specification.md) §2 e §11; [Requisitos de autoria do Studio](04-studio-authoring-requirements.md) §7
- **Schemas relacionados:** [`project.schema.json`](schemas/project.schema.json) (`build`), [`save.schema.json`](schemas/save.schema.json) (`integrity`), [`plugin-lock.schema.json`](schemas/plugin-lock.schema.json)
- **Decisões de 2026-11-13:** PCK embutido no executável; bundle narrativo em formato binário nos builds de release; detecção de modificação no bundle e nos saves; criptografia do PCK como opção avançada, desligada por padrão.

Este documento define **como um projeto do Studio vira um jogo distribuível**: entradas, etapas, a estrutura do Build Staging, o que entra no PCK, o processamento de assets, os presets de exportação por plataforma, a proteção do conteúdo, o manifesto de build e a linha de comando. O assistente de exportação (Req §7) é a interface para quem não programa; este documento é o contrato do que acontece por baixo dele.

---

## 1. Princípios

1. **O projeto original nunca é modificado** (ADD §7.1). Tudo acontece numa cópia temporária, o Build Staging.
2. **O lock manda.** Plugins entram exatamente nas versões e hashes de `plugin-lock.json` (ADD §15, princípio 9). O build nunca resolve versões por conta própria.
3. **Uma versão de cada coisa.** Cada build registra a versão exata do Studio, do runtime, do Godot e de cada plugin no manifesto de build (§9).
4. **Mesma entrada, mesmo conteúdo.** Para as mesmas entradas, o bundle narrativo e o `content_hash` são idênticos byte a byte (§10).
5. **O assistente e a CLI usam o mesmo motor.** Não existe comportamento exclusivo de um dos dois (§11).
6. **Proteção do conteúdo é ofuscação, não segurança.** O jogo precisa ler o próprio conteúdo, então a chave sempre viaja com ele. O objetivo é tornar a leitura e a edição trabalhosas para a maioria dos jogadores, não impossíveis (§8).

## 2. Entradas

| Entrada | Origem | Observação |
|---|---|---|
| Pasta do projeto | Studio | Somente leitura durante o build |
| `plugin-lock.json` | Projeto | Sem vínculo ativo em `.vnstudio/plugin-lock.local.json` (P013) |
| Pacotes `.vnplugin` | Cache de pacotes (§10.2) | Conferidos contra `integrity` do lock (B002) |
| Template do runtime | Embutido no Studio, por versão do runtime | Projeto Godot do runtime, já com `addons/vn_runtime_sdk/` |
| Binário do Godot | Sidecar do Studio ou `~/.vnstudio/godot/<versão>/` | Versão **exata** fixada pelo runtime (SDK §2.4) |
| Templates de exportação | `~/.vnstudio/godot/<versão>/templates/` | Baixados sob demanda, com hash conferido (B004) |
| Perfis de assinatura | Cofre do sistema operacional | O projeto guarda só o nome do perfil (`build.signing`) |

### 2.1. Versão do runtime e do Godot

O Studio instalado traz uma versão do runtime, e cada versão do runtime fixa uma versão exata do Godot. **O runtime 1.0 fixa o Godot 4.7.2** (decisão de 2026-11-14: a estável mais recente; a 4.8 ainda está em beta). Trocar a versão fixada do Godot é, no mínimo, uma versão MINOR do runtime, e a CI do catálogo roda de novo os testes dos plugins publicados contra ela antes da troca. Os campos do projeto funcionam como **restrições**, não como escolhas:

- `project.json → runtime.min_version`: o build falha se o runtime do Studio for menor (B014).
- `project.json → runtime.godot`: faixa aceita pelo projeto. O build falha se a versão do Godot fixada pelo runtime estiver fora dela (B014). Isso resolve a aparente contradição entre a faixa do projeto e a versão exata do SDK: a faixa diz o que o projeto aceita, e o runtime escolhe a versão dentro dela.

**Versão do Godot como SemVer.** O Godot numera `4.7`, `4.7.2` e rotula `-stable`. Em node-semver, `4.7.0-stable` é pré-release e **não** satisfaz `>=4.7.0`. Por isso toda comparação usa a versão normalizada para SemVer puro (`4.7` → `4.7.0`, sufixo `-stable` removido); só versões não estáveis do Godot (`-rc1`, `-beta2`) continuam como pré-release. O rótulo original fica no manifesto, só para exibição (§9.2).

Fixar uma versão exata de runtime por projeto (para builds reprodutíveis entre instalações diferentes do Studio) fica para o v2; no v1, o manifesto de build registra o que foi usado.

## 3. Pipeline

```text
1. Preparação      validação --export · pré-requisitos por plataforma · espaço em disco
2. Compilação      projeto → bundle narrativo (JSON canônico) → content_hash → build_id
3. Dependências    lock → pacotes do cache → conferência de integrity · revogações
4. Staging         pasta <build_id> · template do runtime · plugins · project.godot · .vnb
5. Assets          seleção dos assets usados · conversões · configurações de import
6. Import          godot --headless --import (com cache de import)
7. Verificação     godot --headless -- --vn-selfcheck
8. Exportação      godot --headless --export-release <preset> (uma vez por plataforma)
9. Pós-exportação  assinatura · empacotamento final · manifesto · relatório
```

Cada etapa pode falhar com um código `B0xx` (§13). Falhas que dependem de uma plataforma (B001, B007, B012) tiram **só aquela plataforma** do build: as demais seguem, e o relatório mostra o que faltou em cada uma. Falhas comuns a todas (validação, compilação, dependências, chave de saves, import e verificação) interrompem o build inteiro. A compilação vem antes do staging porque o `build_id` usa o `content_hash`.

### 3.1. Preparação

1. Roda o validador do Studio com as regras de exportação (as mesmas de `validate.py --export`, a implementação de referência; Req §13). Qualquer erro bloqueia.
2. Confere os pré-requisitos de cada plataforma pedida (Req §7.1). Faltando algo que impede gerar o arquivo, B001; faltando só a assinatura, B010 (aviso).
3. Estima o espaço necessário (soma dos assets × 3, mais 500 MB por plataforma) e falha com B013 se não houver.
4. Em builds de release, resolve a chave de saves (§8.1) e falha com B017 se `build.protection.save_key_id` existir e a chave disponível faltar ou não conferir.

### 3.2. Dependências

1. Lê `plugin-lock.json`. Plugins com `enabled: false` não entram.
2. Para cada plugin, pega o `.vnplugin` do cache; se não estiver lá, baixa de `resolved`. Um pacote guardado (`path:` para um `.vnplugin`) é lido do repositório.
3. Calcula o SHA-256 do arquivo e compara com `integrity`. Diferente: B002.
4. Plugin embutido (`embedded: true`, spec 09 §3.2): empacota a pasta `vn_plugins/<namespace>/` com as regras do pacote reprodutível (Plugin SDK §2.1–§2.2), calcula o `integrity` e o registra no manifesto do build (§9.2). Não há o que conferir, porque o código é do próprio projeto; o histórico do Git é a referência.
5. Consulta o catálogo (quando houver rede) e falha com B003 se a versão estiver `revoked` e o autor não tiver confirmado explicitamente (SDK §13.3). Sem rede, segue com aviso B015.

## 4. Build Staging

### 4.1. Local

```text
~/.vnstudio/builds/<project_id>/<build_id>/
├── staging/          # o projeto Godot montado (§4.2)
├── out/<plataforma>/ # saída do export antes do empacotamento final
└── build.log         # log completo, mostrado em "Detalhes" no relatório
```

`build_id` = `<AAAAMMDD-HHMMSS>-<8 primeiros caracteres hex do SHA-256 do bundle.json canônico>` (os mesmos bytes do `content_hash`, que em JSON aparece em base64 SRI; §5.1). O staging é apagado ao final de um build bem-sucedido, a menos que o autor marque "Manter arquivos temporários" ou a CLI receba `--keep-staging`. Builds com falha mantêm o staging até o próximo build, para diagnóstico.

### 4.2. Estrutura

```text
staging/
├── project.godot                 # gerado (§4.3)
├── export_presets.cfg            # gerado (§7)
├── addons/vn_runtime_sdk/        # do template do runtime
├── vn_runtime/                   # código do runtime (Narrative Engine, Scheduler, Stage...)
│   ├── boot.tscn                 # cena principal
│   └── build_config.gd           # gerado: constantes do build (§4.4)
├── vn_plugins/<namespace>/       # um por plugin do lock (§4.5)
└── vn_content/
    ├── narrative.vnb             # bundle narrativo (§5)
    ├── locales/<lang>.vnb        # um por idioma incluído
    ├── plugins.vnb               # plugins habilitados, concessões e config
    ├── build.json                # manifesto resumido (§9.2)
    └── assets/...                # assets processados, mesma árvore de assets/ do projeto
```

Os caminhos `res://vn_plugins/<namespace>/` e `res://addons/vn_runtime_sdk/` são os mesmos do ambiente de desenvolvimento e do Preview, no painel e na janela (SDK §2.4). `assets.json` mapeia cada ID para `res://vn_content/assets/<path>` no bundle compilado.

### 4.3. `project.godot` gerado

O Build System escreve o `project.godot` do zero a partir do template do runtime e do `project.json`. Plugins nunca alteram este arquivo (SDK §2.4).

| Configuração do Godot | Origem |
|---|---|
| `application/config/name` | `title` no `default_locale` |
| `application/config/version` | `version` |
| `application/run/main_scene` | `res://vn_runtime/boot.tscn` |
| `application/config/icon` | `build.icon` |
| `application/boot_splash/image` | `build.splash`; ausente = cor de fundo do tema, sem logo do Godot |
| `display/window/size/viewport_width/height` | `settings.resolution` |
| `display/window/stretch/mode` / `aspect` | `canvas_items` / `expand` (fixos no v1; a sobra de uma janela com outra proporção mostra o cenário estendido, RT §2) |
| `autoload/*` | Somente os autoloads do runtime (`VNRuntime`, `VNStage`) |
| `input/vn_*` | Ações padrão do runtime (SDK §5.7) |
| `internationalization/locale/translations` | Vazio: o runtime traduz pelo bundle, não pelo sistema de traduções do Godot |
| `rendering/textures/canvas_textures/default_texture_filter` | `linear` (fixo no v1) |

### 4.4. `build_config.gd`

Script gerado com as constantes que o runtime precisa e que variam por build: `BUILD_ID`, `CONTENT_HASH`, `CONTENT_HASHES` (caminho de cada `.vnb` → SHA-256 do seu JSON canônico, §8.2), `RUNTIME_VERSION`, `DEBUG_BUILD`, `CONTENT_KEY` e `SAVE_KEY` (§8; em debug, a chave fixa de debug, §11.1), `SAVE_TAMPER_POLICY`. Ele é exportado como os demais scripts, em tokens binários (§7.1).

### 4.5. Plugins no staging

De cada `.vnplugin` são copiados para `vn_plugins/<namespace>/` somente:

- `plugin.json`, `LICENSE`;
- `runtime/` inteiro (scripts, cenas e assets).

Não entram no jogo: `editor/`, `tests/`, `docs/`, `README.md`, `CHANGELOG.md` (SDK §2.1). As licenças de todos os plugins e das fontes do tema são reunidas em `vn_content/licenses.txt`. A tela de créditos as mostra com o elemento `licenses_list` (UI Spec §3.1), que o preset `classic` já traz; um projeto com tela `credits` própria sem esse elemento recebe o aviso U009.

## 5. Bundle narrativo

### 5.1. Compilação

O compilador produz primeiro a forma canônica em JSON, exatamente como descrita no RT §2 (`bundle.json`, `locales/<lang>.json`, `plugins.json`): validada, com defaults resolvidos, variáveis de personagem instanciadas, aliases de `renamed_from` reunidos, o preset aplicado (UI Spec §2.1) e a galeria resolvida: sem `project.json → gallery`, a tela `gallery` fica fora, e `gallery`/`gallery_order` saem dos assets cuja seção não está ativa (Data Model §10.5). Os três arquivos têm schema ([`bundle.schema.json`](schemas/bundle.schema.json), [`bundle-locale.schema.json`](schemas/bundle-locale.schema.json), [`bundle-plugins.schema.json`](schemas/bundle-plugins.schema.json)).

**Compilador de referência.** [`tools/compile_bundle.py`](tools/compile_bundle.py) implementa esta seção em Python e é a primeira peça do Build System: `python3 tools/compile_bundle.py <projeto> <saída> [pastas-de-plugins…] [--stage] [--edition standard|censored]`. Ele roda o validador antes (para em erro) e grava a forma canônica com o `content_hash`. Com `--stage`, copia também os assets e os plugins; com `--godot <projeto-godot>`, grava tudo em `vn_content/` e `vn_plugins/` desse projeto, para rodar o jogo no editor do Godot sem o Studio (RT §2.1). O compilador do Studio DEVE gerar o mesmo `bundle.json`, byte a byte, para o mesmo projeto.

**Vetores de compilação.** Com um interpretador só (RT §11), o código de jogo que existe em duas linguagens é o compilador (e o validador). [`conformance/compile/cases.json`](conformance/compile/cases.json) traz projetos pequenos, cada um uma variação do exemplo das specs (preset, galeria ligada, desligada ou só com finais, `--edition censored`, `renamed_from`, idioma fora do produto, asset escondido na galeria), com o `content_hash`, o hash de cada idioma e o de `plugins.json` esperados. [`tools/test_compile.py`](tools/test_compile.py) confere a referência contra eles; o compilador do Studio passa nos mesmos casos (spec 08). Na CI do Studio vale também a **equivalência incremental**: para cada caso, compilar entidade por entidade e aplicar os patches de `preview.reload` (Preview Protocol §3) sobre o bundle anterior dá o mesmo `bundle.json` que compilar tudo de novo.

**JSON canônico:** UTF-8, chaves ordenadas, sem espaços, números no formato mais curto que preserva o valor, strings com escape mínimo (RFC 8785, JCS). `content_hash` = SHA-256 do `bundle.json` canônico, como no RT §2. Ele independe da codificação final, então o mesmo conteúdo tem o mesmo hash no Preview e no jogo.

**Serializador próprio.** O runtime (GDScript) e o Studio (TypeScript) DEVEM implementar o JCS, porque `JSON.stringify` do Godot formata números de outro jeito (e o do JavaScript não ordena chaves). O mesmo serializador é usado no `content_hash`, na assinatura de saves e perfil (§8.3) e no `build.json`. Os vetores de JCS e de HMAC estão em [`conformance/canonical.json`](conformance/canonical.json) (spec 08); o caso `demo_save` confere a assinatura de `examples/demo-save.json` com a chave de debug.

**Representação de hashes.** Os mesmos 32 bytes aparecem de três formas, sempre convertidas assim: em JSON, `sha256-` + base64 padrão (formato SRI, `common.schema.json → Hash`); em texto curto (`build_id`, nomes de pasta), hex minúsculo; em binário (cabeçalho do `.vnb`), os bytes crus.

### 5.2. Formato `.vnb` (builds de release)

Builds de release gravam cada arquivo do bundle no formato binário `.vnb`; o Preview e os builds de debug podem usar o JSON direto.

```text
offset  tamanho  campo
0       4        magia "VNB1"
4       2        versão do formato (uint16, little-endian) = 1
6       2        flags (bit 0 = conteúdo cifrado)
8       32       content_hash (SHA-256 do JSON canônico deste arquivo)
40      4        tamanho do JSON descomprimido (uint32, little-endian)
44      16       IV (zeros se não cifrado)
60      n        corpo: JSON canônico comprimido com Zstandard, depois cifrado (se flag 0)
```

- **Compressão:** Zstandard nível 19. O Godot lê com `PackedByteArray.decompress(size, FileAccess.COMPRESSION_ZSTD)`.
- **Cifra:** AES-256-**CBC** com `CONTENT_KEY`, IV aleatório por arquivo e padding PKCS#7. O Godot decifra com `AESContext` no modo CBC nativo, numa chamada só, e o runtime remove o padding. CTR exigiria cifrar bloco a bloco num laço em GDScript, lento para bundles grandes, sobretudo no Web; como a cifra é ofuscação (princípio 6), CBC não perde nada.
- Nos builds de release a flag 0 é sempre ligada; ela existe para que ferramentas de diagnóstico leiam `.vnb` sem cifra gerados em debug.
- Todos os inteiros do cabeçalho são little-endian.

O runtime DEVE recusar `.vnb` com versão de formato desconhecida (G001, §13.1).

### 5.3. Idiomas

Por padrão entram todos os idiomas de `project.json → locales`. `build.locales` limita a lista (por exemplo, para um build Web menor); precisa incluir o `default_locale` (regra R013 do validador). Um idioma por arquivo `.vnb`, carregado sob demanda quando o jogador troca de idioma.

### 5.4. Edição censurada

O modo stream (Data Model §10.4) funciona em dois jeitos de build:

| `build.edition` | O que o jogador recebe |
|---|---|
| `standard` (padrão) | O jogo completo. O jogador liga e desliga o modo stream nas configurações (UI Spec §8) |
| `censored` | A **edição censurada**: o modo fica sempre ligado, o controle some das telas e os originais nem entram no pacote. Útil para lojas, sites ou plataformas que exigem classificação livre, ou para uma versão Web de demonstração |

Na edição censurada, o compilador aplica o filtro uma vez, no build:

- `censored_text` e `censored_prompt` passam a ser o texto do nó, e as traduções `…/censored` ocupam o lugar das originais. Uma fala censurada sem tradução cai no texto censurado do idioma-fonte, nunca no original traduzido.
- `censored_label` (hotspots e `exit`) passa a ser o rótulo, e `censored_caption` a legenda de `audio`; a legenda de um som com `censored.hide` sai do nó.
- Passos `censor: skip` viram um desvio para o passo seguinte (mantêm o `id`, para saves e caminhos de texto continuarem válidos); passos `censor: only` perdem a marca e rodam sempre.
- Um asset com `censored.replace_with` passa a apontar para o arquivo da substituta (com âncora, escala e import dela), mantendo o próprio lugar na galeria; um asset com `censored.hide` fica no bundle só como marca e perde `gallery` e `gallery_order`, para a galeria não ganhar um item que só mostraria o placeholder. Em nenhum dos dois casos o arquivo original é copiado para o staging (§6.1).
- `bundle.json → project.content_filter` sai com `edition: censored` e `default: true`; o runtime ignora o `content_filter` de `settings.json` e a pergunta da primeira abertura.

Os saves das duas edições têm `content_hash` diferentes e são tratados como save de outra versão do jogo (RT §8.4). Para lançar as duas, o autor gera dois builds (por exemplo, `vnstudio build --edition censored` para a loja que exige). O `build-manifest.json` registra a edição em `edition`.

## 6. Processamento de assets

### 6.1. Seleção

Entram no staging:

1. Todo asset referenciado pelo bundle compilado (cenas, personagens, finais, tema e seus estilos, telas de `ui/`, cenários de `sets/`, fontes de reserva de `fonts.fallbacks` só para os idiomas de `build.locales`, `build.icon`, `build.splash`);
2. Todo asset de `assets.json` marcado com `"always_include": true` (para assets usados só por plugins via `config`);
3. Todos os arquivos de `runtime/` dos plugins (sem filtro: o Build System não analisa o código do plugin).

Asset registrado e não usado gera aviso B008 e não entra no jogo. Isso reduz o tamanho e evita vazar material descartado (por exemplo, um final cortado).

### 6.2. Conversões e import

| Tipo | Tratamento | Configuração de import no Godot |
|---|---|---|
| `background`, `sprite`, `image` (PNG/JPG/WebP) | Copiados sem conversão | `compress/mode` conforme `build.textures`: `lossless` (padrão) ou `lossy` (WebP qualidade 0,85); `mipmaps` desligado |
| `image` SVG | Rasterizado pelo import do Godot na escala 1 | Igual acima |
| `audio_music`, `audio_voice` em WAV | Convertidos para OGG Vorbis (qualidade 0,6) no staging, aviso B009 | `loop` ligado para música |
| `audio_sfx` | Copiados sem conversão | Padrão |
| `video` | OGV, copiado | Padrão |
| `font` | Copiada | `antialiasing` e `hinting` padrão; MSDF desligado |

- **VRAM compression** não é usada no v1: VN é 2D com imagens grandes vistas em tela cheia, onde artefatos de compressão aparecem. `lossy` é a alavanca de tamanho, recomendada para Web e Android.
- O campo `import` de cada asset em `assets.json` (DM §10) sobrescreve os valores acima, campo a campo.
- Assets dos plugins usam as configurações de import padrão do Godot, já que os arquivos `*.import` não vão no pacote (SDK §2.1).

### 6.3. Cache de import

O import do Godot é a etapa mais lenta. O Build System mantém `~/.vnstudio/import-cache/<project_id>/<versão do Godot>/` com a pasta `.godot/imported/` do último build e um índice `{caminho → hash do arquivo + hash das configurações de import}`. Antes do import, restaura no staging as entradas cujo par de hashes não mudou. O cache é descartável: apagá-lo só deixa o próximo build mais lento.

## 7. Presets de exportação

O `export_presets.cfg` é gerado no staging, um preset por plataforma de `build.platforms`. O autor nunca o edita.

### 7.1. Comum a todas as plataformas

| Opção | Valor |
|---|---|
| `export_filter` | `all_resources` |
| `exclude_filter` | `*.md, *.txt, tests/*, docs/*` (exceto `vn_content/licenses.txt`) |
| `script_export_mode` | Tokens binários comprimidos (valor numérico a confirmar no Godot 4.7.2, §15) |
| `binary_format/embed_pck` | `true` onde a plataforma permite (§7.2) |
| `encryption/*` | Ligados só com criptografia do PCK (§8.4) |
| `application/file_version`, `product_version` | `version` (com `.0` final no Windows) |
| `application/company_name` | `build.company` |
| `application/product_name` | `title` no `default_locale` |

### 7.2. Por plataforma

| Plataforma | Arquitetura | Saída do export | Entrega final | PCK |
|---|---|---|---|---|
| `windows` | x86_64 | `<nome>.exe` | `<nome>-<versão>-windows.zip` com o `.exe` | Embutido |
| `linux` | x86_64 | `<nome>.x86_64` | `<nome>-<versão>-linux.tar.gz` (preserva o bit de execução) | Embutido |
| `macos` | universal | `<nome>.app` | `<nome>-<versão>-macos.zip`; `.dmg` quando gerado num Mac | Dentro do `.app` (`Contents/Resources`) |
| `web` | wasm32 | `index.html`, `.wasm`, `.js`, `.pck` | `<nome>-<versão>-web.zip`, pronto para itch.io | Separado (exigência da plataforma) |
| `android` | — | Fora do v1 (§14); não é aceito em `build.platforms` | — | — |

`<nome>` = `build.executable_name`. Os ícones `.ico` (16 a 256 px) e `.icns` são gerados a partir de `build.icon`.

### 7.3. Web

- Exportação **sem threads** (`variant/thread_support = false`). Assim o jogo roda em qualquer hospedagem, sem exigir os cabeçalhos COOP/COEP. Plugins que usam threads próprias já devem omitir `web` de `compatibility.platforms` (SDK §5.7, aviso W008).
- O relatório mostra o tamanho total do download e avisa (B016) acima de 100 MB, sugerindo `build.textures: "lossy"` e `build.locales` reduzido.
- Saves e perfil ficam no IndexedDB do navegador (`user://` do Godot Web). O assistente avisa que limpar os dados do navegador apaga os saves.

## 8. Proteção do conteúdo

Decisões de 2026-11-13. Ver princípio 6: tudo aqui é ofuscação e detecção de alteração, não proteção contra quem tem conhecimento técnico e tempo.

| Camada | Padrão | Contra o quê |
|---|---|---|
| PCK embutido no executável (§7.2) | Sempre, onde a plataforma permite | Arquivo solto óbvio para abrir |
| Bundle `.vnb` comprimido e cifrado (§5.2) | Sempre em release | Ler a história com uma ferramenta de extração de PCK ou um editor de texto |
| Scripts em tokens binários (§7.1) | Sempre em release | Ler o código do runtime, onde está a chave |
| Verificação do `content_hash` (§8.2) | Sempre | Bundle editado ou corrompido |
| Assinatura do save (§8.3) | `flag` | Editar o save à mão para liberar finais ou galeria |
| Criptografia do PCK (§8.4) | Desligada | Extrair assets (imagens, música) e scripts do PCK |

### 8.1. Chaves

- `CONTENT_KEY`: 32 bytes aleatórios gerados **a cada build**. Fica só em `build_config.gd`.
- `SAVE_KEY`: 32 bytes aleatórios gerados **uma vez por projeto**, na primeira exportação, e guardados no cofre do sistema operacional como `vnstudio/<project_id>/save-key`. Não muda entre versões, para que saves antigos continuem válidos depois de uma atualização do jogo. A CLI aceita `VNSTUDIO_SAVE_KEY` (base64) para CI.
- **Levar a chave para outra máquina.** Preferências do projeto → "Exportar chave de saves" gera um arquivo `.vnkey` cifrado com uma senha escolhida pelo autor; "Importar chave de saves" o lê em outro computador ou na máquina de outra pessoa da equipe.
- **Impressão digital.** `project.json` não guarda a chave, mas guarda a impressão digital dela em `build.protection.save_key_id` (8 primeiros caracteres hex do SHA-256 da chave; não é segredo), gravada pelo Studio no primeiro build de release e repetida no manifesto de build. Como `project.json` vai para o Git, a regra vale para qualquer máquina, colaborador ou CI: se `save_key_id` existe e a chave disponível (cofre ou `VNSTUDIO_SAVE_KEY`) falta ou tem outra impressão digital, o build **para** com B017 e pede a importação. Uma chave nova só é gerada sem `save_key_id`, ou com confirmação explícita no Studio (`--new-save-key` na CLI), avisando que todos os saves de jogadores aparecerão como modificados; o Studio então atualiza `save_key_id`.

Nenhuma chave é gravada na pasta do projeto, para não ir parar no Git.

### 8.2. Verificação do conteúdo

Ao carregar cada `.vnb`, o runtime descomprime, calcula o SHA-256 do JSON e compara com o cabeçalho e com a entrada do arquivo em `build_config.CONTENT_HASHES` (para `narrative.vnb`, também com `CONTENT_HASH`). Assim trocar um idioma ou o `plugins.vnb` inteiro também é detectado. Diferença: o jogo mostra "Os arquivos do jogo estão corrompidos. Reinstale o jogo." e não inicia. Isso pega edição ingênua e corrupção de download; quem extrair a chave consegue regravar tudo de forma consistente.

### 8.3. Assinatura de saves e perfil

- Save e `profile.json` ganham o campo `integrity` = `hmac-sha256-<base64>` sobre o JSON canônico do arquivo **sem** o campo `integrity`, com `SAVE_KEY` (ver [`save.schema.json`](schemas/save.schema.json)).
- `build.protection.save_tamper` define o que acontece quando a assinatura não confere ou falta:

| Valor | Comportamento |
|---|---|
| `ignore` | Carrega normalmente. A assinatura é gravada, mas não conferida |
| `flag` (padrão) | Carrega, registra no log e liga `sys.save_modified` (somente leitura, `persistence: session`). O autor pode usar a variável em condições, por exemplo para não liberar um final secreto. Saves de builds de debug também caem aqui |
| `reject` | Mostra "Este save foi modificado e não pode ser carregado." e não carrega. Para o perfil, começa um perfil novo, guarda o antigo como `profile.rejected.json` e mostra G006 no título |

### 8.4. Criptografia do PCK (opção avançada)

O Godot cifra o PCK com AES-256, mas só com **templates de exportação compilados com a chave** (`SCRIPT_AES256_ENCRYPTION_KEY`). Não é possível distribuir templates prontos, porque a chave estaria neles. Por isso, no v1:

1. A opção fica em "Avançado" no assistente, desligada por padrão: `build.protection.encrypt_pck: true`.
2. O autor (ou alguém da equipe) compila os templates da versão exata do Godot com a chave, seguindo um guia do Studio, e aponta a pasta dos templates nas preferências do Studio (por máquina, não no projeto). A chave fica no cofre do sistema operacional.
3. O Build System confere a versão dos templates personalizados contra a versão fixada (B012) e liga `encryption/encrypt_pck` e `encryption/encrypt_directory` no preset.
4. Sem templates configurados, o build falha com B012 e a mensagem explica o que fazer ou como desligar a opção.

Um serviço do Studio que compila templates por projeto fica como proposta para o v2.

## 9. Saída e manifesto

### 9.1. Pasta de saída

Por padrão `<Documentos>/VN Studio Builds/<project_id>/<versão>/`, configurável por máquina nas preferências do Studio (não no projeto, porque é um caminho local). Gerar de novo a mesma versão substitui a pasta, depois de confirmar. Cada plataforma vira um arquivo de entrega (§7.2), ao lado do `build-manifest.json`.

### 9.2. `build-manifest.json`

Schema: [`build-manifest.schema.json`](schemas/build-manifest.schema.json). Gravado na pasta de saída e, numa forma resumida (`build_id`, `version`, `content_hash`, `runtime`, `godot`), em `res://vn_content/build.json` dentro do jogo, para o runtime mostrar no log e na tela "Sobre".

```json
{
  "manifest_version": 1,
  "build_id": "20261113-221500-9f2c1a7b",
  "project": { "id": "seaside_story", "version": "0.1.0", "content_hash": "sha256-..." },
  "created_at": "2026-11-13T22:15:00Z",
  "type": "release",
  "edition": "standard",
  "tools": { "studio": "1.0.0", "runtime": "1.0.0", "runtime_sdk": "1.0.0", "godot": "4.7.2", "godot_label": "4.7.2-stable" },
  "plugins": [
    { "id": "vnstudio.fishing", "version": "1.0.0", "integrity": "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=" },
    { "id": "seaside_story.quiz", "version": "0.3.0", "integrity": "sha256-…", "embedded": true }
  ],
  "locales": ["pt-BR", "en"],
  "protection": { "encrypt_pck": false, "save_tamper": "flag", "save_key_id": "5f1c0a93" },
  "outputs": [
    { "platform": "windows", "file": "Seaside Story-0.1.0-windows.zip", "bytes": 84213760, "sha256": "...", "signed": false },
    { "platform": "linux", "file": "Seaside Story-0.1.0-linux.tar.gz", "bytes": 83120112, "sha256": "...", "signed": false }
  ],
  "warnings": ["B008 asset bg/unused_beach não é usado e ficou de fora"]
}
```

Um schema `build-manifest.schema.json` acompanha a próxima revisão; este exemplo é a referência até lá. O `integrity` do exemplo (e o de `examples/demo-project/plugin-lock.json`) é ilustrativo: é o SHA-256 de um arquivo vazio, porque o pacote do plugin de referência ainda não é gerado. O Build Reporter (Req §7.2) lê este arquivo.

### 9.3. Histórico

Antes de cada build o Studio cria um ponto automático no histórico de versões (Req §8). O ponto guarda o `build_id`, para que o autor saiba exatamente qual estado do projeto gerou cada build enviado.

## 10. Reprodutibilidade e caches

### 10.1. O que é garantido

- Mesmo projeto, mesmo lock e mesma versão do runtime: **mesmo JSON canônico e mesmo `content_hash`** (DEVE).
- Os `.vnb` diferem entre builds só pelo IV e pela `CONTENT_KEY`; decifrados, são idênticos.
- O PCK e os executáveis **não** têm garantia de serem idênticos byte a byte, porque o export do Godot não é totalmente determinístico. O manifesto (§9.2) é a prova do que entrou.

### 10.2. Caches

| Cache | Local | Chave |
|---|---|---|
| Pacotes de plugins | `~/.vnstudio/cache/plugins/<id>/<versão>/` | `integrity`; arquivo com hash diferente é apagado e baixado de novo |
| Godot e templates | `~/.vnstudio/godot/<versão>/` | Versão + hash oficial |
| Import | `~/.vnstudio/import-cache/<project_id>/<versão do Godot>/` | Hash do arquivo + hash das configurações (§6.3) |

"Limpar caches" nas preferências apaga os três; nada no projeto depende deles.

## 11. Linha de comando

O mesmo motor do assistente, para CI e para quem prefere terminal. O Studio instala o comando `vnstudio`.

```bash
vnstudio build <pasta-do-projeto> \
  [--platform windows,linux,macos,web]   # padrão: build.platforms
  [--out <pasta>]                         # padrão: §9.1
  [--debug]                               # build de debug (§11.1)
  [--keep-staging]
  [--offline]                             # não consulta catálogo nem baixa nada; falha se faltar algo no cache
  [--json]                                # imprime o manifesto em stdout ao terminar
  [--new-save-key]                        # gera chave de saves nova mesmo com save_key_id (§8.1)
  [--edition standard|censored]           # padrão: build.edition (§5.4)
```

| Código de saída | Significado |
|---|---|
| 0 | Todas as plataformas geradas (pode haver avisos) |
| 1 | Erro de validação do projeto ou do lock, ou asset ilegível (B005) |
| 2 | Pré-requisito ou dependência ausente ou recusada (B001, B002, B003, B004, B012, B013, B014, B017) |
| 3 | Falha em ao menos uma plataforma durante import, verificação ou export (B006, B007) |
| 4 | Erro interno |

A CLI nunca gera chave de saves nova por conta própria quando `build.protection.save_key_id` existe: sem a chave no cofre nem em `VNSTUDIO_SAVE_KEY`, sai com B017 (código 2).

Assinatura na CLI: os perfis são lidos do cofre como no Studio, ou de variáveis de ambiente `VNSTUDIO_SIGN_<PLATAFORMA>_*` para CI. O `.github/workflows` de exemplo fica para a próxima revisão.

### 11.1. Build de debug

`--debug` (ou "Exportar versão de teste" no assistente) gera o jogo com o runtime em modo debug: validação de payloads de eventos e `params` em tempo de execução (RT §7.2, §5), logs detalhados em `user://logs/`, `.vnb` sem cifra, `save_tamper` forçado para `flag` e o executor de testes `--vn-test` disponível (RT §12).

O build de debug **não** leva a `SAVE_KEY` real, porque é enviado a testadores sem proteção nenhuma. Ele assina saves e perfil com uma chave fixa de debug (32 bytes zero, a mesma de `examples/demo-save.json`). Um build de release trata essas assinaturas como inválidas: saves de testadores carregam pela política do projeto (em `flag`, com `sys.save_modified`). O nome do arquivo ganha o sufixo `-debug` e o manifesto registra `"type": "debug"`.

## 12. Verificação no staging (`--vn-selfcheck`)

Antes de exportar, o Build System roda `godot --headless --path staging -- --vn-selfcheck`. O runtime, nesse modo:

1. Carrega e confere todos os `.vnb` (§8.2).
2. Confere se todo caminho `res://` do bundle existe no staging.
3. Carrega os scripts e cenas de todos os plugins (pega erro de sintaxe ou dependência ausente) e chama `_vn_init` com uma NarrativeAPI de verificação.
4. Inicia um novo jogo e roda até o primeiro ponto de seleção, sem renderizar, em modo automático: falas avançam sozinhas, escolhas pegam a primeira opção habilitada e atividades completam na hora com o `default_outcome` (ou o primeiro de `outcomes`) e payload vazio. Com `settings.reproducible_rng`, usa seed fixo. Limite de 60 s; estourar é B006.

Falha: B006, com a causa traduzida quando conhecida e o trecho do log em "Detalhes".

## 13. Códigos

Mesmo padrão de mensagens simples de Req §6; o texto técnico fica em "Detalhes".

| Código | Nível | Mensagem para o autor |
|---|---|---|
| B001 | erro | Para gerar o jogo para *{plataforma}* falta *{requisito}*. As outras plataformas continuam. |
| B002 | erro | O arquivo do plugin *{plugin}* não é o mesmo que foi instalado. Reinstale o plugin pelo Gerenciador de plugins. |
| B003 | erro | A versão *{versão}* do plugin *{plugin}* foi retirada pelo autor por um problema. Atualize o plugin ou confirme que quer usá-la mesmo assim. |
| B004 | erro | Não foi possível baixar os arquivos de exportação do Godot. Verifique a internet e tente de novo. |
| B005 | erro | O arquivo *{asset}* não pôde ser lido. Ele pode estar corrompido; tente exportá-lo de novo no programa de origem. |
| B006 | erro | O jogo não conseguiu iniciar na verificação final: *{causa}*. |
| B007 | erro | A geração do jogo para *{plataforma}* falhou. Veja os detalhes. |
| B008 | aviso | *{asset}* não é usado em nenhum lugar e ficou de fora do jogo. |
| B009 | aviso | *{asset}* está em WAV e foi convertido para OGG para o jogo ficar menor. |
| B010 | aviso | O jogo para *{plataforma}* não foi assinado. Os jogadores verão um alerta de segurança ao abrir. |
| B011 | — | Reservado. |
| B012 | erro | A criptografia do jogo está ligada, mas os templates personalizados não estão configurados ou são de outra versão do Godot. |
| B013 | erro | Não há espaço suficiente no disco. São necessários cerca de *{tamanho}*. |
| B014 | erro | Este projeto pede uma versão diferente do motor do jogo (*{pedido}*). Atualize o Studio ou ajuste o projeto. |
| B015 | aviso | Sem internet: não foi possível conferir se algum plugin foi retirado pelo autor. |
| B016 | aviso | O jogo para Web ficou com *{tamanho}*. Acima de 100 MB o carregamento pode ser lento. |
| B017 | erro | A chave de saves deste projeto não está neste computador. Importe-a (Preferências do projeto → Importar chave de saves) para que os saves dos jogadores continuem válidos. |

### 13.1. Mensagens do runtime para o jogador

Erros que o **jogador** vê no jogo exportado, no idioma do jogo (traduzíveis pelo caminho `runtime/message/<código em minúsculas>`, ex.: `runtime/message/g002`):

| Código | Quando | Mensagem (pt-BR) |
|---|---|---|
| G001 | `.vnb` com versão de formato desconhecida ou que não decodifica | O conteúdo do jogo está corrompido ou é de uma versão incompatível. Reinstale o jogo. |
| G002 | Hash de um `.vnb` não confere (§8.2) | Os arquivos do jogo estão corrompidos. Reinstale o jogo. |
| G003 | Save com `save_tamper: reject` e assinatura inválida (§8.3) | Este save foi modificado e não pode ser carregado. |
| G004 | Save com `save_format` MAJOR desconhecido ou de outro projeto (RT §8.3) | Este save é de uma versão incompatível do jogo. |
| G005 | Falha ao gravar save ou perfil (disco cheio, permissão) | Não foi possível salvar o jogo. Verifique o espaço em disco. |
| G006 | Perfil com `save_tamper: reject` e assinatura inválida (§8.3, RT §3.0) | Os dados do jogo foram modificados e não puderam ser usados. Um perfil novo foi criado: finais, galeria e recordes foram zerados. |

As traduções dessas mensagens para os idiomas do produto vêm no preset (`presets/classic/locales/`).

## 14. Fora de escopo do v1

- **Pacotes extras de conteúdo** (DLC, capítulos novos, traduções baixáveis) via `ProjectSettings.load_resource_pack`. A estrutura `res://vn_content/` foi escolhida para permitir isso depois: um pacote extra traria seu próprio `vn_content/packs/<id>/` com `.vnb` e assets.
- **Atualizações parciais** (patch só do conteúdo). No v1, atualizar o jogo é distribuir o executável de novo; os saves migram pelo RT §8.4.
- **Publicação direta** em lojas (Steam, itch.io via butler). O ZIP do §7.2 já serve para envio manual.
- Fixar a versão do runtime por projeto (§2.1).
- Compilação de templates com criptografia como serviço (§8.4).
- Android e iOS (decisão de 2026-11-14: Android fora do v1).

## 15. Pendências

1. Medir o tempo de import e export do demo-project em cada plataforma, para calibrar o cache e a estimativa de espaço.
2. Confirmar no Godot 4.7.2 os nomes e valores exatos das opções de preset citadas no §7 (inclusive o valor de `script_export_mode` e `variant/thread_support` no Web).
3. Definir o guia de compilação dos templates com criptografia para Windows, macOS e Linux.
4. Medir o tempo de decifrar e descomprimir um `.vnb` de 10 MB no Web, para confirmar AES-CBC + Zstandard no boot.
