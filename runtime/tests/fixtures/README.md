# Fixtures do runtime

Bundles pequenos, um por recurso, para o Stage, o UI Manager, os saves e o Preview testarem sem esperar o núcleo nem a demo (tarefa M0-08). As imagens e os sons são gerados por script: cores sólidas, formas e tons senoidais. Não entra arte de terceiros nem arte gerada por IA, e os assets de teste não têm crédito, porque são internos e nunca entram num artefato ([spec 09 §1.1 e §1.2](../../../docs/specs/09-repositories-and-code-layout.md), decisão D22).

## Gerar

Da raiz do repositório, com Python 3 e `jsonschema>=4.18` (o mesmo das ferramentas das specs):

```bash
python3 runtime/tests/fixtures/generate.py           # grava runtime/tests/fixtures/bundles/
python3 runtime/tests/fixtures/generate.py --check   # também valida pelos schemas e confere que duas gerações dão os mesmos bytes
```

`bundles/` fica fora do Git e é apagada e refeita a cada execução. A workflow [`runtime-fixtures.yml`](../../../.github/workflows/runtime-fixtures.yml) roda o `--check` em todo pull request que toca estas pastas, as ferramentas, os schemas ou os presets das specs. Um teste do runtime que use as fixtures roda o mesmo comando antes de `godot --headless --path runtime --import`, para o Godot importar as imagens e os sons.

## O que sai

| Bundle | Recurso | O que exercita |
|---|---|---|
| `dialogue` | Fala | Cenário com transição, música em laço com fade, personagem com expressões e posições, fala com voz, narração com interpolação, legenda de efeito sonoro, `wait`, `hide`, parar a música; idiomas `en` e `pt-BR` |
| `choice` | Escolha | `record` num enum de cena, opção com efeito, `enabled_if`, `visible_if`, `branch` sobre a escolha |
| `set` | Set | Set com camadas, estado `night`, animação e hotspot com `toggle_state`, usado pela tela `title`; nó `interact` com áreas `rect`, `polygon` e `character`, `once` e saída |
| `gallery` | Galeria | As três seções, assets marcados com `gallery_order`, dois finais com imagem alcançados por `end` com `ending` |
| `stream` | Modo stream, edição normal | Pergunta na primeira abertura, `placeholder`, `censored_text`, `censored_prompt`, `censor: skip` e `only`, asset com `replace_with` e com `hide`, `censored_caption` |
| `stream_censored` | Modo stream, edição censurada | O mesmo projeto com `--edition censored` (Build System §5.4): textos trocados, passos `skip` viram desvios, o asset escondido não entra |
| `activity` | Atividade | Nó `plugin` com `params`, efeitos com `{"result": …}`, `outcomes` e `on_error`, com o plugin embutido de teste `fixture_activity.probe` |

Cada pasta tem a forma canônica do bundle (Runtime Spec §2): `bundle.json`, `locales/<idioma>.json`, `plugins.json`, `licenses.json` e `assets/`. `bundles/index.json` lista os bundles com o `content_hash` e o caminho `res://`.

Para abrir um deles no runtime em debug, use `--vn-bundle res://tests/fixtures/bundles/<nome>/`. Os caminhos de asset do bundle continuam `res://vn_content/assets/…`, e o runtime os procura em `<pasta>/assets/` (Runtime Spec §2.1).

O código do plugin de teste não é copiado para `bundles/`: o Godot analisaria os scripts dentro de `runtime/` sem o Runtime SDK instalado. Os testes de atividade usam o dublê do Plugin Host. O `plugins.json` do bundle traz o plugin com as concessões, como num jogo.

## Onde fica cada coisa

| Caminho | Conteúdo |
|---|---|
| `generate.py` | O gerador: receitas da mídia sintética, montagem dos projetos e chamada ao [`compile_bundle.py`](../../../docs/specs/tools/compile_bundle.py) |
| `src/common/` | `assets.json`, o personagem `probe`, `variables.json` e `theme.json`, comuns a todos os projetos |
| `src/projects/<nome>/` | O projeto de cada bundle, com os arquivos que somam ou substituem os comuns |
| `src/.gdignore` | Esconde as fontes do Godot: são projetos de VN, não recursos do runtime |
| `bundles/` | Saída, fora do Git |

Os projetos de `src/` são projetos de VN válidos (zero erros no validador das specs). Como os assets são comuns, o validador avisa U013 nos projetos sem galeria: a marca `gallery` é ignorada ali, como a spec manda.

Para acrescentar um asset, ponha a entrada em `src/common/assets.json` e a receita em `MEDIA`, no `generate.py`, com o mesmo caminho. Para acrescentar um bundle, crie `src/projects/<nome>/` com pelo menos `project.json`, um capítulo e uma cena.
