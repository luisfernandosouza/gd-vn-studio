# Revisão das especificações antes do runtime — 2026-11-14 (4ª rodada)

- **Situação (2026-11-14):** aplicada. D16 e D17 decididas: o compilador em Python grava o jogo e os plugins dentro do projeto do runtime (`--godot`), porque o Godot só resolve `res://` dentro do projeto aberto; por isso `--vn-plugins` deu lugar à cópia para `runtime/vn_plugins/` e `--vn-bundle` aceita só pastas `res://`. Idiomas: o jogo tem de 1 a n idiomas; o Studio e o preset têm uma lista fixa.
- **Escopo:**
  - `gd-vn-studio`: specs 00 a 09, os 17 schemas, os exemplos, os vetores e as ferramentas.
  - `gd-vn-studio-demo`: projeto, assets e plugin usado.
- **Foco:** o que impede ou atrapalha implementar o runtime em Godot 4.7.2 e rodar a demo no editor do Godot.
- **Relação com a 3ª rodada:** os itens do [relatório anterior](revisao-specs-2026-11-14-3.md) continuam valendo e nenhum foi aplicado ainda. Este relatório só os repete quando afetam o runtime.
- **Estado das ferramentas:**
  - Validador: 0 erros e 0 avisos na demo.
  - Testes do validador: 112/112.
  - Vetores de conformidade: 105/105.

## Resumo

As regras do runtime estão completas no que é lógica: Scheduler, transações, eventos, saves, erros, números, texto e RNG. Os vetores cobrem essas regras, e o runtime pode ser escrito contra eles.

O que falta é o **caminho para a demo chegar ao runtime** e a **aparência padrão**:

1. Não existe um formato definido para o bundle que o runtime lê.
2. Não há como gerar esse bundle sem o Studio.
3. Não há como carregar o plugin de pesca sem o catálogo.
4. As telas que a demo não define (pausa, salvar, carregar, galeria e HUD) dependem de um preset que só tem nome.

Há 5 bloqueios (B), 8 lacunas que o runtime vai precisar no meio do caminho (L) e 6 inconsistências novas (I). Na seção 5, sugiro uma ordem de implementação que resolve os bloqueios sem esperar o Studio.

## 1. Bloqueios para rodar a demo no runtime

| # | Onde | Problema | Sugestão |
|---|---|---|---|
| B1 | RT §2, BS §5.1 | O runtime lê `narrative/bundle.json`, descrito só como "project + variables + characters + chapters + scenes + theme + ui + sets + assets". Não há schema nem exemplo: falta a forma das chaves (lista ou mapa por id), quais defaults vêm resolvidos e como ficam `locales/<lang>.json` e `plugins.json` do bundle. | Escrever `bundle.schema.json` e um exemplo gerado a partir da demo. Proposta: `{format_version, content_hash, project, variables: {id: def}, characters: {id: …}, chapters: {id: …}, scenes: {id: …}, theme, ui: {id: …}, sets: {id: …}, assets: {id: {path: "res://…", …}}}`, com todos os mapas ordenados por chave (RT §12.1). |
| B2 | RT §2, BS §3 | Só o Build System gera o bundle, e ele depende do Studio e do pipeline completo (staging, import, export). Para rodar a demo no editor do Godot é preciso um compilador de bundle independente. | Criar o compilador de referência em Python (`docs/specs/tools/compile_bundle.py`), reaproveitando o carregamento do validador. Ele seria a primeira peça do Build System. O runtime ganha a opção `--vn-bundle <pasta>`, aceita só em builds de debug e no editor. |
| B3 | Demo `plugin-lock.json`, spec 09 §3.1 | O lock da demo aponta para `github.com/vnstudio/official-plugins/releases/…/fishing-v1.0.0`, um repositório que não existe. O `integrity` é o de um arquivo vazio, e o catálogo ainda não existe. O runtime não teria como obter o plugin. | Para desenvolvimento, usar o vínculo (Plugin SDK §12.3) num caminho local: o runtime aceita `--vn-plugins <pasta>` com `vn_plugins/<namespace>/`. Corrigir o `resolved` para a tag do monorepo (`luisfernandosouza/gd-vn-studio`, `plugin-fishing-v1.0.0`), como a spec 09 define, e gerar o `integrity` real quando o pacote existir. |
| B4 | UI §2, Req §11, E8 | Toda tela ausente em `ui/` "vem do preset". A demo define título, configurações, créditos e extras. Pausa, salvar, carregar, galeria e HUD viriam do preset `classic`, que não tem nenhum valor escrito. O mesmo vale para os estilos padrão de cada tipo de elemento e para o layout padrão da caixa de texto, da plaquinha de nome e das escolhas. | Escrever o preset `classic` como arquivos reais: `runtime/presets/classic/ui/*.json` e `theme.json`, no mesmo formato do projeto e validados pelo mesmo schema. É o item E8, que passa a ser o primeiro documento a escrever. `modern` e `minimal` podem esperar. |
| B5 | `save.schema.json → PlayerSettings`, UI §8 | Os padrões que o runtime precisa no primeiro boot não estão definidos: `text_speed`, `auto_delay`, `vsync`, `display_mode` e os volumes por canal não têm `default`. Além disso, `fullscreen` (boolean) e `display_mode` existem ao mesmo tempo e podem se contradizer. | Pôr `default` em todos os campos (sugestão: `text_speed` 40 caracteres/s, `auto_delay` 1,5 s, volumes 0,8 e `voice` 1,0). Remover `fullscreen` em favor de `display_mode`, ou declarar `fullscreen` obsoleto e convertido na leitura. |

## 2. Lacunas que o runtime vai encontrar

| # | Onde | Problema | Sugestão |
|---|---|---|---|
| L1 | RT §3 | O ciclo de vida começa em `BOOT`, mas o boot não está descrito. Faltam a ordem (ler `settings.json`, `profile.json` e bundle; validar `content_hash`; carregar plugins com `_vn_init`/`_vn_ready`; abrir o título) e o que acontece se `profile.json` falhar. | Escrever RT §3.0 "Boot", com a ordem e os erros de cada passo. |
| L2 | SDK §5.7, UI §3.1 `shortcut` | A lista de ações de input tem só `vn_confirm`, `vn_cancel` e as direções, mas a UI usa `vn_quick_save` e o runtime precisa de avançar, pular, automático, esconder a caixa, histórico, menu, salvamento e carregamento rápidos. Faltam as teclas padrão e o mapeamento no gamepad. | Tabela fechada de ações `vn_*` com as teclas padrão, no RT ou na UI Spec. A tela de configurações pode permitir remapear depois do v1. |
| L3 | DM §10.2, RT §5.2 | A escala dos sprites é relativa a quê? `scale: 1.0` em pixels da resolução base é a leitura natural, mas não está escrito. Também não está escrita a ordem de desenho entre cenário, personagens, caixa de texto, HUD e overlays de plugin. | Uma frase no DM §10.2 (pixels da resolução base) e uma tabela de camadas (`CanvasLayer`) no RT §1 ou na UI §12. |
| L4 | RT §5.2 `line` | A velocidade do texto (caracteres por segundo) não diz se a marcação conta como caractere, nem o que o clique faz durante a digitação. O comportamento comum é completar a fala no primeiro clique e avançar no segundo. A pausa de pontuação também não está definida. | Definir: clique durante a digitação completa a fala; marcação não conta; sem pausa extra de pontuação no v1. |
| L5 | RT §8.5 | O formato da miniatura do save (320 × 180) está dado, mas não o que ela captura (com ou sem a caixa de texto e o menu aberto). | Capturar o quadro do jogo antes de abrir o menu, sem a UI. |
| L6 | BS §8.3, RT §8.5 | Em desenvolvimento (editor do Godot, `--vn-bundle`) não há `SAVE_KEY`. O BS diz que saves de debug caem em `flag`, mas não diz com que chave são assinados. | Chave fixa de desenvolvimento (32 bytes zero, a mesma do `demo-save.json`), com `save_key_id: "dev"`. |
| L7 | Spec 08 §1 | Os vetores não cobrem a execução de uma cena inteira (`kind: flow`). É justamente a primeira coisa que o runtime faz. | Escrever 5 a 10 casos `flow` a partir das cenas da demo e da referência em Python, junto com o compilador de B2. |
| L8 | Exemplo `fishing-plugin` | O plugin toca `res://vn_plugins/fishing/runtime/assets/rare_fish.ogg`, que não existe. A cena do minijogo é feita de `ColorRect`, o que basta para testar. | Gerar o som da mesma forma que os assets da demo, ou trocar por um asset do projeto. |

## 3. Inconsistências novas

| # | Sev. | Onde | Problema | Sugestão |
|---|---|---|---|---|
| I12 | A | Demo `plugins.json` × `fishing-plugin/plugin.json` | O plugin pede `runtime:profile.data`, mas a demo não concede. No runtime, `submit_record` e `set_data` recusariam com `PERMISSION_DENIED`, e o quadro de recordes da tela de extras ficaria sempre vazio. O validador não avisa sobre capacidade pedida e não concedida. | Conceder `runtime:profile.data` na demo. Criar um aviso (W-código novo) quando a tela usa `records_list` ou `play_activity` de um plugin sem a concessão de que esse recurso precisa. |
| I13 | M | Demo `plugin-lock.json` × spec 09 §1 | O `resolved` usa outro repositório e outro formato de tag (`fishing-v1.0.0`). | Ver B3. |
| I14 | M | SDK §5.7 × UI §3.1 | `vn_quick_save` é citado como exemplo de `shortcut`, mas não está na lista de ações padrão. | Ver L2. |
| I15 | M | `PlayerSettings` | `fullscreen` e `display_mode` existem ao mesmo tempo. | Ver B5. |
| I16 | B | RT §11 | O exemplo de `scheduler.evaluated` usa ids legíveis em vez de UUIDs. Já estava no I10 da 3ª rodada, mas pesa mais agora, porque o runtime vai gerar exatamente esse formato. | Trocar pelo exemplo da spec 07. |
| I17 | B | RT §2 × BS §4.2 | O RT chama a pasta do bundle de `narrative/`, e o BS a chama de `res://vn_content/`. Não está claro se o build de debug usa `narrative/` dentro de `vn_content/` ou na raiz. | Usar sempre `res://vn_content/` no jogo e `narrative/` só no Preview, e dizer isso nas duas specs. |

## 4. Itens da 3ª rodada que afetam o runtime

| # | Por que importa agora |
|---|---|
| I2 | O caminho de tradução dos sets: o runtime vai ler as traduções. |
| I3 | O demo grava as traduções fora do caminho do DM: o compilador de bundle (B2) precisa de uma regra só. |
| I4 / D5 | A galeria: a tela `gallery` do preset (B4) precisa saber o que mostrar. |
| I6 | Os valores `entry`/`start` de `scene.started`: o runtime emite essa notificação. |
| I7 | A ação de apagar o perfil. |
| M1 | O modo livre a partir de telas abertas na pausa. |
| M3 | O formato de exibição de `time_ms` e `number` nos recordes. |
| M7 | O resultado do modo livre ao voltar para a tela. |

## 5. Ordem sugerida para começar o runtime

1. **Specs, antes do código** (pequenas, resolvem B1, B4, B5, L1, L2 e I12):
   - `bundle.schema.json`.
   - Preset `classic` como arquivos.
   - Padrões de `PlayerSettings`.
   - RT §3.0 Boot.
   - Tabela de ações de input.
   - Concessão de `profile.data` na demo.
2. **Compilador de bundle em Python** (B2), com casos `flow` gerados a partir dele (L7).
3. **Runtime, núcleo sem tela:**
   - Condition Evaluator, State Manager, PCG32 e Scheduler.
   - Runner `--vn-test`, passando nos 105 vetores.
4. **Runtime, palco e UI:**
   - `--vn-bundle` carregando a demo.
   - Falas, escolhas, cenário, personagens, áudio e telas do preset.
5. **Plugins:** Plugin Host com `--vn-plugins` (B3) e o minijogo de pesca.
6. **Saves e perfil.**

Com os passos 1 a 4 já dá para jogar a demo no editor do Godot, sem o minijogo. O passo 5 acrescenta a pesca.

## 6. Decisões que dependem do Luis

| # | Decisão | Recomendação |
|---|---|---|
| D16 | Como a demo chega ao runtime antes do Studio existir (B2) | Compilador de bundle em Python e opção `--vn-bundle` no runtime, só em debug. |
| D17 | De onde o runtime carrega o plugin em desenvolvimento (B3) | Opção `--vn-plugins <pasta>`, apontando para `gd-vn-studio/plugins/` ou para o exemplo. |
| D5, D14, D15 | Da 3ª rodada | Continuam abertas, com as mesmas recomendações. |
