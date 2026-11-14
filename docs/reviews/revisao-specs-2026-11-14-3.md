# Revisão das especificações — 2026-11-14 (3ª rodada)

- **Escopo:** specs 00 a 09, README, os 17 schemas, `examples/` (demo-project, fishing-plugin, demo-save), `conformance/` e `tools/`.
- **Contexto:** esta rodada vem depois de três acréscimos: os minijogos no nível de repositório (spec 09), os dados de perfil e recordes dos minijogos (Plugin SDK §9.1) e o modo livre (Plugin SDK §6.1).
- **Estado das ferramentas:**
  - `tools/validate.py examples/demo-project`: 0 erros, 0 avisos.
  - `tools/test_validate.py`: 112/112.
  - `tools/conformance.py`: 105/105.
- **Formato:** cada item traz onde está, o problema e uma sugestão. As severidades seguem as rodadas anteriores:
  - **A:** quebra a implementação ou contradiz outra spec.
  - **M:** ambiguidade que dois implementadores resolveriam de jeitos diferentes.
  - **B:** redação, exemplo ou detalhe.

## Resumo

As specs estão coerentes entre si nos pontos centrais: modelo de dados, Scheduler, transações, plugins, build, UI e Preview. Esta rodada encontrou:

- **4 problemas de severidade A:**
  - O ADD descreve outra organização de repositórios.
  - O caminho dos textos de sets colide com uma tela chamada `sets`.
  - O demo grava as traduções num caminho diferente do Data Model.
  - A galeria promete imagens e músicas que o perfil não registra.
- **11 ambiguidades.** A maioria está nas partes novas: modo livre a partir de telas próprias, plugin removido do projeto, Godot do plugin embutido e repositório privado no GitHub.
- **8 detalhes de redação.**

O que mais falta continua sendo documento, não regra: o schema do manifesto de build (E1), os tipos do Editor SDK (E4), a referência do Runtime SDK (E5) e o ADD v0.2 (E13).

## 1. Inconsistências

| # | Sev. | Onde | Problema | Sugestão |
|---|---|---|---|---|
| I1 | A | ADD §12 × spec 09 §1 | O ADD lista cinco repositórios separados (`visual-novel-studio`, `visual-novel-runtime`, `visual-novel-sdk`, `visual-novel-cli`, `official-plugins`). A spec 09 define um monorepo `gd-vn-studio`. | Registrar o desvio no README (seção de desvios do ADD) e incorporá-lo ao ADD v0.2 (E13). O ADD §13 também lista como pendentes itens já resolvidos (algoritmo de seleção, persistência por escopo, protocolo do Preview, lock). |
| I2 | A | DM §9 e UI §3.3 | Os textos de hotspots de sets vão para `locales/<lang>/ui/sets.json`. Uma tela própria com id `sets`, que é válido pelo padrão `Id`, usaria o mesmo arquivo. | Mudar para `locales/<lang>/sets/<set>.json`, no mesmo padrão de `ui/<tela>.json`. Outra opção é reservar o id `sets` para telas (U-código novo), mas o arquivo por set é mais limpo. |
| I3 | A | DM §9 × `examples/demo-project/locales/en/` | O DM diz que as falas vão para `locales/<lang>/scenes/<cena>.json`, com o arquivo escolhido pelo UUID da cena. O demo tem `locales/en/scene_beach.json` na raiz, com o nome do arquivo da cena. O validador aceita os dois porque junta todos os arquivos. | Mover o arquivo do demo para `locales/en/scenes/<uuid>.json` e fazer o validador avisar sobre arquivos de tradução fora do caminho esperado. Vale também decidir se o nome é mesmo o UUID: é estável, mas ilegível para o tradutor, que recebe `.xlsx`/XLIFF de qualquer jeito (Req §9). |
| I4 | A | UI §3.1 `gallery_grid` × `save.schema.json → Profile` | `gallery_grid` aceita `source: images` e `music`, mas o perfil só guarda `endings` e `seen_text`. Não há campo que diga quais imagens ou músicas o jogador já viu. É a decisão D5, ainda aberta. | **Recomendação:** imagens e músicas no v1, com `assets.json → gallery: true` marcando o que entra, e `profile.seen_assets` (ids) gravado quando o asset aparece em cena. Se ficar fora do v1, tirar `images` e `music` do enum. |
| I5 | M | BS §4.5 × UI §3.1 | As licenças dos plugins vão para `vn_content/licenses.txt`, "exibido na tela de créditos". A tela de créditos agora é um arquivo `ui/credits.json` do autor, e nenhum elemento mostra esse arquivo. | Criar o elemento `licenses_list` (ou `label` com `source: "licenses"`) e incluí-lo nos créditos do preset. Avisar (U-código novo) quando o projeto tem plugins com licença e a tela de créditos não mostra as licenças. |
| I6 | M | Preview §4 `scene.started` × RT §4.3 | `scene.started.reason` aceita `entry` e `start` além dos motivos do Scheduler, mas nenhum dos dois está definido. Provavelmente significam a cena de entrada do capítulo e o `preview.start_at`. | Definir os dois valores no §4 do protocolo e no schema: `entry` para `entry_scene` de capítulo e `start` para início forçado pelo Preview. |
| I7 | M | SDK §9.1 × UI §8 | O SDK fala da opção "Apagar dados do jogo" nas configurações, e o RT §6.5 também ("só apagar dados"), mas a UI não tem ação nem `bind` para isso. | Adicionar a ação `reset_profile` (com `confirm` obrigatório, só no título) e definir o que ela apaga: o perfil inteiro, mas não `settings.json` nem os saves. Os saves continuam válidos, porque não dependem do perfil. |
| I8 | B | DM §6.1.1 e RT §12.2 | `weighted_random` aparece ao lado de `random_int` como se fosse função de expressão. É um valor de `chapter.tie_breaker`, não uma função. | Reescrever: "Os sorteios (`random_int` e o desempate `weighted_random` do capítulo)…". |
| I9 | B | DM §3 | "IDs de opção, dentro do nó de escolha". As opções têm UUID, e UUIDs são únicos no projeto inteiro (mesma frase). | Retirar a exceção: opções seguem a regra geral. |
| I10 | B | RT §11 (exemplo de `scheduler.evaluated`) | O exemplo usa `"chapter": "ch01"` e `"chosen": "scene_quiet_day"`. O protocolo e os vetores usam UUIDs. | Trocar por UUIDs, ou marcar como abreviação. |
| I11 | B | `examples/fishing-plugin/` × spec 09 §2 | A spec 09 diz que um plugin avulso é um projeto Godot com o plugin em `vn_plugins/fishing/`. O exemplo tem só o conteúdo dessa pasta (`plugin.json`, `runtime/`, `editor/`), sem `project.godot` nem `sandbox/`. | Dizer no README do exemplo que ele é a pasta `vn_plugins/fishing/`. Quando o código começar, gerar o exemplo a partir de `plugins/fishing/`, como a spec 09 já prevê. |

## 2. Ambiguidades

| # | Sev. | Onde | Pergunta em aberto | Sugestão |
|---|---|---|---|---|
| M1 | M | UI §4 `play_activity` | A ação vale "fora do jogo (título e telas abertas a partir dele)". Uma tela própria (`extras`) pode ser aberta tanto do título quanto da pausa. O validador só recusa `pause` e `hud`. O que o runtime faz se o jogador abre `extras` pela pausa e clica no minijogo? | No runtime, esconder ou desabilitar automaticamente o botão quando há partida em andamento (`sys.ui.in_game`). No validador, avisar quando uma tela com `play_activity` é alcançável a partir da pausa. Rodar o modo livre durante uma partida (suspendendo a história) fica para depois do v1. |
| M2 | M | SDK §9.1 | O plugin foi removido do projeto (ou trocado por outro com o mesmo namespace). O que acontece com `profile.plugins.<ns>` e com os recordes? | Manter os dados órfãos por pelo menos uma versão (o jogador pode reinstalar o plugin) e descartá-los quando o `id` do plugin mudar no mesmo namespace. Registrar no log. |
| M3 | M | SDK §9.1 `format: time_ms` | O formato de exibição não está definido (`1:02.345`? `62,3 s`?), nem o arredondamento por idioma. `number` também não diz quantas casas mostra. | Fixar `time_ms` como `m:ss.cc` (centésimos), com o separador decimal do idioma, e `number` com até 2 casas pela regra de formatação do RT §12.1. Acrescentar casos `text` aos vetores. |
| M4 | M | Spec 09 §3.2 | Um plugin embutido tem a própria pasta `.vnplugin/` com a versão do Godot. Se ela for diferente da que o projeto fixa (BS §2.1), qual vale? E quem compila `editor/src` → `editor/dist`: o dev, à mão, ou o Studio? | O embutido herda a versão do runtime e do Godot do projeto (`.vnplugin/` fica opcional ou é gerado). O Studio compila `editor/dist` ao salvar, com o mesmo bundler de `vnplugin build`, e avisa quando `dist` está velho. |
| M5 | M | Spec 09 §3.1 `github:` | Um estúdio com vários jogos quer compartilhar um minijogo privado. Embutir duplica o código. Guardar o pacote funciona, mas `github:` com repositório privado não diz de onde vem o token. | Aceitar `github:` privado com token guardado no chaveiro do sistema (nunca no projeto) e na CI por variável de ambiente (`VNSTUDIO_GITHUB_TOKEN`). Documentar o fluxo "um repositório de plugin, vários jogos". |
| M6 | M | UI §11 U007 | O aviso só confere elementos na resolução base. Com `anchor: edge`, ou em resoluções com outra proporção (ultrawide, 4:3, Steam Deck 16:10), um elemento pode sair da tela ou se sobrepor a outro. | Conferir U007 também nas proporções de `settings.display.resolutions`, e mostrar no Menu Editor uma pré-visualização com seletor de proporção. |
| M7 | M | SDK §6.1 × RT §5.3 | No modo livre, o que acontece com `handle.complete(outcome, payload)`? O `outcome` não leva a lugar nenhum. A tela de origem pode reagir a ele (por exemplo, mostrar "Novo recorde!")? | Definir que o runtime liga `sys.ui.last_activity_outcome` e `sys.ui.last_record_rank` ao voltar à tela, para que o autor mostre a mensagem com `visible_if`. |
| M8 | M | RT §8.5 × BS §8.3 | O perfil é rejeitado (`save_tamper: reject`) e vira `profile.rejected.json`. Os recordes somem sem aviso ao jogador. | Mostrar a mensagem `runtime/message/…` também para o perfil e dizer que finais e recordes foram zerados. |
| M9 | M | Spec 08 §1 | O formato `flow` (execução de uma cena inteira) está reservado, e sem ele as diferenças mais prováveis entre GDScript e TypeScript não são cobertas: ordem dos eventos, `on_result`, interpolação com marcação. | Prioridade da próxima leva de vetores, antes de o interpretador TS existir, ou junto com a decisão D2 (um interpretador só). |
| M10 | M | Spec 09 §1 × repositório atual | A spec diz que as specs ficam em `docs/specs/`, e o repositório tinha os arquivos na raiz. | **Aplicado nesta rodada:** o repositório foi reorganizado em `docs/specs/` e `docs/reviews/`, com um README curto na raiz. |
| M11 | B | SDK §9.1 | A data `at` do recorde vem do relógio do sistema, que o jogador pode mudar. Em modo `reject` isso não é adulteração detectável. | Aceitar e registrar como limitação: recordes locais não são competitivos. Placares online ficam fora do v1. |

## 3. Lacunas

| # | O que falta | Por que importa | Sugestão |
|---|---|---|---|
| G1 | `build-manifest.schema.json` (E1) | O Build Reporter e a CI leem o manifesto. O exemplo do BS §9.2 já usa `embedded: true`, ainda sem schema. | Escrever o schema a partir do exemplo e validar o manifesto no teste de build. |
| G2 | Cobertura dos minijogos no validador e nos vetores | `submit_record` (ordem, `keep`, empate) e a migração de `profile.data_version` têm regra, mas não têm vetor nem teste de referência. | Acrescentar o grupo `records.json` aos vetores, com `submit_record` puro (entrada: quadro, marcas, nova marca; saída: lista e posição). |
| G3 | Plugin embutido no demo | O demo só usa o fishing do catálogo. Nada exercita `path:plugins/…` de ponta a ponta. | Acrescentar ao demo um embutido mínimo (`seaside_story.quiz`, já citado no BS §9.2), com teste positivo no `test_validate.py`. |
| G4 | Telas de minijogos no preset | O preset não traz uma tela "Minijogos" com `play_activity` e `records_list`. O autor precisa montar do zero. | Criar a tela opcional `minigames` no preset, gerada a partir das atividades com `free_play`. |
| G5 | Documentos E4–E15 | Continuam pendentes desde a 2ª rodada. | Ordem sugerida: E13 (ADD v0.2, que resolve I1), E5, E4, E6, E8. Os outros podem esperar o código. |

## 4. Decisões que dependem do Luis

| # | Decisão | Recomendação |
|---|---|---|
| D5 | Galeria de imagens e músicas no v1 (I4) | Sim, com `gallery: true` no `assets.json` e `seen_assets` no perfil. |
| D14 | Modo livre durante uma partida (M1) | Não no v1. O botão só aparece fora da partida. |
| D15 | Repositório privado do GitHub como origem de plugin (M5) | Sim, com token no chaveiro do sistema. |
| D11, D13 | Operação do catálogo, nome e domínio | Continuam abertas. |

## 5. Correções feitas nesta rodada

- O repositório `gd-vn-studio` foi reorganizado para o layout da spec 09: `docs/specs/` (specs, schemas, exemplos, vetores e ferramentas) e `docs/reviews/`. A raiz ganhou um README curto. Os links relativos entre specs e relatórios continuam funcionando.

As demais sugestões ficam para aplicar depois da aprovação, como nas rodadas anteriores.
