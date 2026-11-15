# Requisitos de autoria do Studio — v1.0.0-draft

- **Status:** rascunho para revisão
- **Base:** ADD v0.1 §3 e §13.2; Data Model, Runtime Spec e Plugin SDK Spec
- **Origem:** análise da jornada de um roteirista ou artista sem conhecimento de programação, do download ao jogo exportado

Este documento define o que o Studio DEVE oferecer para que uma pessoa que não programa crie uma visual novel inteira sem ver JSON, IDs, códigos de erro, Git ou o Godot. Ele não desenha telas; define comportamentos e os dados que as telas usam. As palavras **DEVE**, **DEVERIA** e **PODE** seguem a RFC 2119.

---

## 1. Princípios

1. **O autor vê títulos, nunca IDs.** Toda referência (cena, personagem, variável, asset) é escolhida numa lista pelo nome exibido.
2. **Frases, não expressões.** Condições, efeitos e agendamento aparecem como frases em português ("Dinheiro é pelo menos 50").
3. **Todo erro tem conserto à vista.** Mensagem em linguagem simples e um botão que leva ao ponto exato.
4. **Nada se perde.** Salvamento contínuo, histórico de versões e recuperação após travamento, sem exigir Git.

## 2. IDs e nomes

- O Studio gera o UUIDv7 de cenas, capítulos, personagens, nós e opções no momento da criação (Data Model §3). O autor edita só `title`/`name`.
- Ao criar um personagem, o Studio gera a `key` a partir do nome (sem acento, minúsculas, `_` no lugar de espaço; sufixo numérico se já existir) e a mostra uma vez, editável enquanto nenhuma variável do personagem for usada. Depois disso fica fixa; trocar o nome não a altera.
- Chaves de variável seguem a mesma regra: geradas do nome na criação, fixas depois do primeiro uso. Renomear uma variável já usada é um comando explícito ("Renomear em todo o projeto") que atualiza todas as referências num único passo de undo e grava a chave antiga em `renamed_from`, para que saves de jogadores continuem valendo (Data Model §12). Se o projeto já teve um build de release, o diálogo avisa: "Jogadores que já têm saves não perdem nada, mas plugins de terceiros que citam o nome antigo precisam ser atualizados". O mesmo vale para a `key` de personagem e para IDs de asset.
- Nomes de arquivo de cenas, capítulos e personagens são derivados do título; o Studio os renomeia quando o título muda.

## 3. Condition Editor e agendamento

### 3.1. Condições como frases

Cada folha de condição é uma linha com três campos: **variável** (lista agrupada por escopo, com nomes curtos), **comparação** (texto adaptado ao tipo) e **valor** (campo adequado ao tipo: caixa de seleção, número com os limites da variável, lista do enum).

| Operador | Texto exibido (integer/number) | Texto exibido (boolean) | Texto exibido (string/enum) |
|---|---|---|---|
| `equals` | é igual a | é verdadeiro / é falso | é |
| `not_equals` | é diferente de | — | não é |
| `greater_than` | é maior que | — | — |
| `greater_than_or_equal` | é pelo menos | — | — |
| `less_than` | é menor que | — | — |
| `less_than_or_equal` | é no máximo | — | — |
| `in` / `not_in` | é um destes / não é nenhum destes | — | é um destes / não é nenhum destes |
| `contains` | — | — | contém (só string) |
| `is_default` | está no valor inicial | está no valor inicial | está no valor inicial |

Grupos aparecem como blocos "**Todas** estas são verdadeiras" (`all`), "**Pelo menos uma** é verdadeira" (`any`) e "**Não** é verdade que" (`not`). Ao comparar com outra variável, o seletor só oferece variáveis do mesmo tipo. Atalhos prontos: "a cena X já aconteceu" (`sys.scenes.<uuid>.plays > 0`), "o capítulo X foi concluído", "o minigame X terminou desde a última cena" (`event_since_last_selection`).

### 3.2. Predefinições de agendamento

O autor escolhe uma predefinição; os campos de `scheduling` ficam num painel "Avançado".

| Predefinição | `mode` | `max_plays` | `cooldown` | `priority` | Uso |
|---|---|---|---|---|---|
| Só quando outra cena chamar | `manual` | — | — | — | Sequências roteirizadas |
| Evento único | `scheduled` | 1 | 0 | 100 | Padrão |
| Evento importante | `scheduled` | 1 | 0 | 500 | Passa na frente dos comuns |
| Pode repetir | `scheduled` | `null` | 2 | 50 | Rotinas, dias tranquilos |
| Recheio de baixa prioridade | `scheduled` | `null` | 0 | 10 | Só toca se nada mais estiver disponível |

A prioridade é exibida como "Mínima / Baixa / Normal / Alta / Muito alta" (10 / 50 / 100 / 500 / 900), com valor numérico livre no painel Avançado; um valor fora da lista aparece como o rótulo mais próximo seguido do número ("Normal (120)"). Grupos de exclusividade aparecem como "Só uma destas cenas pode acontecer" com a lista das cenas do grupo.

## 4. "Por que esta cena não apareceu?"

- Em qualquer cena, o Studio DEVE oferecer o painel **Disponibilidade**, que mostra para o estado atual do preview se a cena pode ser escolhida e, se não, o motivo em frase: "Habilidade de pesca precisa ser pelo menos 10, mas está em 3", "Já tocou 1 de 1 vez", "Outra cena do grupo *Evento noturno* já aconteceu", "*O mestre pescador* tem prioridade maior".
- Os dados vêm de `preview.explain_selection` e da notificação `scheduler.evaluated` (Runtime Spec §11), produzidos pelo runtime nos dois modos do Preview, painel e janela.
- A linha do tempo do preview DEVERIA listar cada ponto de seleção com a cena escolhida e as candidatas descartadas, clicáveis.
- Botão "Tornar esta cena disponível" ajusta as variáveis do preview para satisfazer as condições, quando possível, e reinicia daquele ponto.

## 5. Plugins

- **Instalação em um diálogo** (Plugin SDK §4.1): pedido em frases, uma caixa por item, e o ajuste do `access` das variáveis feito no mesmo diálogo.
- **Formulários** gerados de `params_schema` e `config_schema` usam `title`, `description` e `plugin_locales`; outcomes usam `outcome_labels`. Campos com `format` `vn-variable`, `vn-asset`, `vn-scene` ou `vn-character` viram seletores pelo nome (Plugin SDK §4.4), nunca campos de texto com IDs.
- **Resultado do minigame**: o inspetor do nó plugin mostra "Para onde ir" (um seletor de passo por outcome) e "O que muda na história", com os `suggested_effects` do manifesto como frases. O autor escolhe a variável; efeitos livres ficam no painel Avançado. Se a atividade pode ser pulada, o inspetor avisa: "Se o jogador pular, a história vai para *{rótulo do default_outcome}* e nada disto muda".
- **Efeitos que podem falhar.** Quando um efeito pode violar uma restrição com `reject` (ex.: tirar dinheiro), o Studio sugere a condição correspondente em `enabled_if` da opção ou um destino "Se não der certo" (`on_fail`) no passo de efeitos.
- **Edições de plugins** passam pelo undo/redo e nunca mudam permissões, configuração de outros plugins nem dados de exportação (Plugin SDK §10.4.1).
- **Plugins locais** (`trust: local`) mostram aviso claro antes de executar: "Este plugin não foi revisado pela equipe. Ele pode fazer qualquer coisa no jogo."
- **Variáveis de plugin aparecem como "do plugin".** Em todo lugar onde o autor vê variáveis (Variable Manager, seletor do Condition Editor, interpolação de texto, painel Disponibilidade, preview), as variáveis `plugin.<ns>.*` ficam num grupo próprio com o nome e o ícone do plugin, e cada uma leva o selo "do plugin *Fishing Minigame*". O nome exibido vem de `name` (traduzido por `plugin_locales`, `variable/<key>/name`) e a descrição aparece ao passar o mouse, com a frase "Esta variável é controlada pelo plugin *Fishing Minigame* e muda quando o minijogo roda". A definição é somente leitura; o autor não renomeia, não apaga e não escolhe essas variáveis como alvo de efeitos (o seletor de efeitos não as lista). Nas frases de condição o selo também aparece: "*Peixes pescados* (do plugin *Fishing Minigame*) é pelo menos 10".
- **Variáveis do projeto que um plugin acessa** mostram o selo inverso no Variable Manager: "*Fishing Minigame* pode ler" ou "pode alterar", com link para o diálogo de permissões.
- **Plugin removido.** Ao remover um plugin cujas variáveis são usadas, o Studio lista os usos antes de confirmar; depois, a mensagem de R005 diz "*{onde}* usa *Peixes pescados*, que era do plugin *Fishing Minigame*, removido do projeto".
- **Plugin vinculado em desenvolvimento** (Plugin SDK §12.3) aparece no Plugin Manager com o selo "Em desenvolvimento" e o caminho da pasta.

## 6. Mensagens de erro

Todo código do Content Validator (Data Model §11) DEVE ter uma mensagem modelo em linguagem simples, por idioma do Studio, com os parâmetros preenchidos por títulos e nomes curtos, e uma ação "Ir até lá".

| Código | Mensagem modelo (pt-BR) |
|---|---|
| R004 | A imagem ou som *{asset}* usado em *{onde}* não está mais no projeto. |
| R005 | *{onde}* usa a variável *{variável}*, que não existe ou não vale aqui. |
| R006 | *{onde}* aponta para uma cena que foi apagada. |
| R009 | Um passo em *{cena}* leva a outro passo que foi apagado. |
| R012 | O final *{final}* não está na lista de finais do jogo. |
| T001 | *{variável}* guarda {tipo}, mas recebeu *{valor}*. |
| P008 | O plugin *{plugin}* pode alterar *{variável}*, mas a variável não aceita alterações de plugins. |
| W001 | Este passo nunca é alcançado. |
| W005 | O capítulo *{capítulo}* pode ficar sem nenhuma cena disponível. |
| W007 | O plugin *{plugin}* não deu nome legível a *{campo}*. |
| W008 | O plugin *{plugin}* não foi testado para *{plataforma}*. O jogo pode funcionar mal nessa plataforma. |
| P013 | O plugin *{plugin}* está ligado a uma pasta de desenvolvimento. Peça ao desenvolvedor o arquivo .vnplugin antes de exportar. |
| R014 | *{onde}* leva a uma cena de outro capítulo. Para mudar de capítulo, termine este capítulo e escolha o próximo. |
| R015 | O grupo *{grupo}* existe no jogo inteiro e também no capítulo *{capítulo}*. Use nomes diferentes. |
| W010 | A cena de reserva do capítulo *{capítulo}* não muda nada que faça o capítulo terminar. O jogo pode ficar repetindo essa cena. |
| W013 | Este passo está incompleto: *{motivo}*. |
| R019 | O texto de *{onde}* mostra *{variável}*, que não existe ou não vale aqui. O jogador veria o texto quebrado. |
| R020 | *{onde}* anuncia um acontecimento que não é da história (*{evento}*). Só acontecimentos da história podem ser anunciados pelas cenas. |
| T006 | *{variável}* guarda {tipo}, mas recebe aqui um valor de outro tipo. |
| U001 | *{onde}* usa *{alvo}*, que não existe mais nesta tela ou cenário. |
| U003 | O botão *{elemento}* do menu inicial depende de *{variável}*, que só existe durante uma partida. Use uma variável de perfil ou de finais. |
| U004 | O objeto *{hotspot}* do cenário faz *{ação}*, mas objetos do cenário só podem mudar a aparência do cenário e tocar sons. Para mudar a história, use um passo "Clicar no cenário" na cena. |
| U006 | O menu inicial não tem botão de "Novo jogo". O jogador não conseguiria começar. |
| W017 | *{variável}* guarda números inteiros; o resultado da conta será cortado (ex.: 3,7 vira 3). Use "arredondar" para deixar claro. |

Os demais códigos seguem o mesmo padrão. O texto técnico original fica disponível em "Detalhes".

## 7. Exportação

### 7.1. Assistente

Clicar em **Exportar** abre um assistente que:

1. Mostra o resultado da validação; erros bloqueiam com as mensagens do §6.
2. Pede o que faltar em `project.json` (`version`, R021) e em `build`: nome do executável, ícone (PNG ≥ 512×512), empresa, plataformas.
3. Verifica pré-requisitos por plataforma e explica o que falta, sem jargão:

| Plataforma | Pré-requisitos | Observação para o autor |
|---|---|---|
| Windows | Nenhum | Sem assinatura, o Windows mostra "Editor desconhecido"; o assistente explica como continuar ou como configurar um certificado |
| Linux | Nenhum | — |
| macOS | Nenhum para gerar; Mac + conta Apple Developer para assinar e notarizar | Sem notarização, o jogador precisa liberar o app nas configurações |
| Web | Nenhum | Viável porque o runtime só usa GDScript |

4. Mostra a etapa **Proteção**: o que fazer com saves modificados (`build.protection.save_tamper`) e, em "Avançado", a criptografia do PCK (Build System §8). Se o projeto já teve build de release (`build.protection.save_key_id` preenchido, o que vale para qualquer pessoa da equipe porque está no Git) e a chave de saves não está neste computador, o assistente **para** e pede para importar a chave (Build System §8.1), em vez de gerar outra.
5. Baixa os templates de exportação da versão fixada do Godot, se necessário, com verificação de hash.
6. Executa o build ([Build System](05-build-system-specification.md) §3) e mostra o relatório.

Credenciais de assinatura ficam no cofre do sistema operacional; `build.signing` guarda só o nome do perfil.

### 7.2. Relatório de build

O Build Reporter DEVE produzir, para cada plataforma: sucesso ou falha, tamanho final, duração, local do arquivo (botão "Mostrar na pasta"), versões usadas (Studio, runtime, Godot, plugins do lock) e avisos. Falhas do Godot são traduzidas para as mensagens do §6 quando a causa é conhecida; o log completo fica em "Detalhes".

## 8. Histórico, backup e colaboração

- **Salvamento contínuo:** toda edição é gravada em disco em até 2 s. Não existe botão "Salvar".
- **Recuperação:** após travamento, o Studio reabre o projeto no último estado gravado e oferece o histórico.
- **Histórico de versões** dentro do Studio: pontos automáticos (a cada sessão e antes de migrações, instalações de plugin e builds) e pontos nomeados pelo autor ("Versão enviada para revisão"). Restaurar cria um novo ponto; nada é apagado pelo autor.
- **Onde fica:** `.vnstudio/history/`, fora do Git, com armazenamento por conteúdo (cada arquivo guardado uma vez por hash), então pontos seguidos custam pouco. Retenção: pontos nomeados e pontos de build ficam para sempre; os automáticos ficam 30 dias, e depois só um por semana. O espaço usado aparece nas preferências do projeto.
- **Git opcional:** se o projeto estiver num repositório Git, os pontos nomeados viram commits e o Studio oferece "Enviar" e "Receber" com resolução de conflitos por entidade (cena, personagem). Quem não usa Git nunca vê Git.
- Colaboração em tempo real continua fora do v1 (Data Model §13).

## 9. Tradução com tradutor externo

- **Exportar para tradução** gera uma planilha (XLSX ou CSV UTF-8) por idioma com as colunas: `chave`, `contexto` (capítulo › cena › personagem), `texto original`, `tradução`, `status`, `source_hash`. As linhas seguem a ordem de leitura das cenas e incluem os textos fora das cenas (títulos de capítulo, finais, créditos) e os textos de plugins (Data Model §9).
- O `status` da planilha pode ser `rascunho`, `revisada` ou `desatualizada`. Os dois primeiros vêm de `status` no arquivo de tradução; `desatualizada` é calculado na hora pelo `source_hash` e nunca é gravado.
- **Importar tradução** lê a mesma planilha, grava em `locales/<lang>/`, ignora linhas cujo `source_hash` não bate com o texto atual (marcando-as como desatualizadas), confere se as marcas de texto (Data Model §9.1) estão equilibradas e mostra um resumo: novas, alteradas, desatualizadas, órfãs, com marcação inválida.
- A chave contém UUIDs (Data Model §3); a coluna `contexto` é o que o tradutor lê.

### 9.1. Idiomas do produto

Decisão de 2026-11-14. Há dois conjuntos de idiomas, independentes:

- **Idiomas do jogo:** de 1 a *n*, escolhidos pelo autor em cada projeto (`default_locale` e as traduções em `locales/`). Qualquer tag BCP 47 vale, inclusive idiomas que o Studio não tem na própria interface (coreano, russo, árabe, tupi…). O Studio não limita nem sugere uma lista: o autor acrescenta um idioma no projeto e passa a ter a coluna dele na planilha de tradução (§9).
- **Idiomas do produto:** a lista fixa da tabela abaixo. Vale só para os textos que **o produto** escreve (a interface do Studio, as mensagens do validador e os textos prontos do runtime), e não restringe os idiomas do jogo.

| Onde | Idioma principal | Idiomas secundários no v1 |
|---|---|---|
| Interface do Studio, mensagens do validador (§6), assistentes e documentação de uso | inglês (`en`) | `pt-BR`, `es`, `fr`, `it`, `de`, `ja`, `zh-Hans`, `zh-Hant` |
| Textos prontos do runtime no jogo exportado: telas do preset (botões "New game", "Load"…), caixas de confirmação, mensagens ao jogador (`runtime/message/*`, BS §13.1), nomes das configurações | inglês (`en`) | os mesmos |
| Plugins oficiais (`vnstudio.*`) | inglês (`default_locale: en`) | os mesmos, em `plugin_locales` |

- O inglês é a fonte: todo texto do produto nasce em inglês, e falta de tradução cai no inglês. Uma string só entra numa versão quando existe em inglês.
- Os idiomas secundários do produto são arquivos de tradução, no mesmo formato de `locales/` (Data Model §9). Acrescentar um idioma ao produto é só acrescentar um arquivo, sem mudar código. A **interface do Studio** em idiomas da direita para a esquerda fica fora do v1, porque exige espelhar os layouts do editor.
- **Jogo em idioma da direita para a esquerda.** O texto do jogo (falas, opções, botões) em árabe ou hebraico é desenhado na direção certa pelo motor de texto do Godot. O que não é automático no v1 é espelhar as telas: o autor posiciona os elementos no Menu Editor para esse idioma, ou usa o mesmo layout.
- O Studio abre no idioma do sistema, se estiver na lista; senão em inglês. O jogador escolhe o idioma do jogo em Configurações (`locale`); o jogo começa no idioma do sistema, se o build o tiver, senão em `default_locale`.
- Textos prontos do runtime vêm traduzidos para os idiomas do jogo que estiverem na lista acima. Para os demais idiomas do jogo, a planilha de tradução (§9) inclui as chaves `runtime/…` com o texto em inglês como fonte, e o autor as traduz como o resto. Chave `runtime/…` sem tradução cai no inglês, e o validador avisa (W021).
- Números seguem a tabela por idioma do Runtime Spec §12.1. Um idioma do jogo fora da tabela usa o formato do inglês, a menos que o projeto declare o formato dele em `settings.number_formats`.
- Fontes: o tema declara fontes de reserva por sistema de escrita (UI Spec §7.2). Idioma do jogo cujo alfabeto nenhuma fonte cobre gera o aviso W020.
- As specs deste repositório continuam em português; os identificadores e o código, em inglês.

## 10. Importar roteiro

Roteiristas costumam escrever antes em Word ou Google Docs. **Importar roteiro** aceita texto simples (colado ou `.txt`/`.docx`) neste formato e gera uma cena:

```text
# Encontro na praia
[cenário: praia de dia]
[música: ondas]
[mostrar: Alice feliz centro]
Alice: Oi! Você é novo por aqui?
O vento sopra do mar.
? Vamos pescar!
? Só quero conversar.
```

- `# título` inicia uma cena; linhas `Nome: fala` viram `line` com `speaker` (personagem criado se não existir, com confirmação); linhas sem nome viram narração.
- `[cenário: …]`, `[música: …]`, `[mostrar: …]`, `[esconder: …]` viram nós `background`, `audio`, `show`, `hide`, procurando assets e expressões pelo nome; o que não for encontrado vira um nó com `unresolved: { reason }` ("Cenário 'praia de dia' não encontrado"), que o validador mostra como aviso W013 e bloqueia na exportação.
- Linhas `? texto` consecutivas viram um nó `choice` com opções sem `goto` (seguem o passo seguinte até o autor ligá-las no editor), o que é válido no schema.
- Formato Fountain PODE ser aceito numa versão futura.

## 11. Aparência do jogo

O **Menu Editor** edita `theme.json`, as telas de `ui/` e os cenários de `sets/` (Data Model §10.3), com preview ao vivo de cada tela: título, caixa de diálogo com uma fala de exemplo, escolhas, pausa, salvar/carregar, configurações, galeria, créditos e HUD. A artista parte de um preset, arrasta botões para onde quiser, troca imagens arrastando arquivos, cria estilos de botão e torna objetos do cenário clicáveis. O comportamento completo está na UI Spec ([06-ui-menus-and-interaction-specification.md](06-ui-menus-and-interaction-specification.md)) §9. A galeria de finais usa `project.json → endings`.

### 11.1. Modo stream (versão censurada)

Decisão de 2026-11-15: o modo stream mostra a mesma cena com outra apresentação, e só a apresentação muda (Data Model §10.4). O Studio oferece, sem código:

- **Asset Manager.** Em cada imagem, sprite ou som, o campo "Versão censurada": arrastar a substituta ou marcar "Esconder no modo stream". O asset ganha um selo, e a substituta é importada com o mesmo tipo e tamanho de tela. Marcar uma vez vale para todas as cenas, telas, galeria e minijogos.
- **Editor de cenas.** Cada fala, pergunta e opção tem "Adicionar versão censurada", que abre um segundo campo de texto logo abaixo do original. Passos de apresentação (fala, cenário, personagem, áudio, pausa) podem ser marcados "Só sem censura" ou "Só com censura", um a um ou vários de uma vez; o passo ganha uma faixa colorida no roteiro e no grafo. Os outros tipos de passo nem mostram a opção, para o autor não precisar conhecer a regra R023.
- **Painel "Modo stream".** Lista tudo que está marcado (assets, falas, passos), com atalho para cada um, e um interruptor "Ver como modo stream" que troca o roteiro, as miniaturas e o Menu Editor para a versão censurada. O botão do Preview que liga o modo no jogo em execução entra no Protocolo do Preview (spec 07) na próxima revisão dele.
- **Tradução.** A planilha (§9) traz as versões censuradas como linhas próprias, logo abaixo do original, com a coluna "versão censurada" marcada.
- **Exportação.** O assistente (§7.1) pergunta a edição: "Completa (o jogador escolhe)" ou "Só a versão censurada" (Build System §5.4), e pode gerar as duas de uma vez.

## 12. Acessibilidade

Decisão de 2026-11-14: o v1 garante este mínimo no jogo exportado, sem trabalho do autor.

| Recurso | Onde fica | Observação |
|---|---|---|
| Tamanho do texto ajustável (80% a 200%) | `PlayerSettings.text_scale` | O tema define o tamanho base; a caixa de diálogo cresce ou rola |
| Velocidade do texto e texto instantâneo | `PlayerSettings.text_speed` (0 = instantâneo) | Já existia |
| Desligar animações (transições, tremidas, `[speed]`) | `PlayerSettings.reduce_motion` | Transições viram corte seco; `[pause]` continua valendo |
| Legendas de voz e de sons com significado | `PlayerSettings.subtitles` | Falas com `voice` já têm texto; `audio` de `sfx` ganha `caption` opcional |
| Menus e escolhas só por teclado ou gamepad | Runtime, ações `vn_*` (Plugin SDK §5.7) | Foco visível em todos os botões; o tema define `colors.focus` |
| Alto contraste na caixa de diálogo | `PlayerSettings.high_contrast` | Fundo opaco e cor de texto de contraste ≥ 4,5:1 |

O Menu Editor avisa quando a cor do texto sobre o painel tem contraste abaixo de 4,5:1. Leitor de tela fica fora do v1.

## 13. Fora de escopo do v1

Edição colaborativa em tempo real; editor de animações e câmera (vem por plugin); importação de Fountain; leitor de tela; telas com código próprio (o que as ações da UI Spec §4 não cobrem exige um plugin); voltar falas (rollback) no jogo.

## 14. Validador

O Studio implementa as regras do Content Validator (Data Model §11) em TypeScript. `tools/validate.py` é a implementação de referência: os dois DEVEM dar o mesmo resultado nos casos de `tools/test_validate.py`.
