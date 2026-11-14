# Fishing Minigame (`vnstudio.fishing`)

Plugin de referência do Visual Novel Studio. Esta pasta é só o conteúdo de `vn_plugins/fishing/` do projeto de desenvolvimento (Plugin SDK §2.4, spec 09 §2): não tem `project.godot` nem `sandbox/`. Quando o código começar, o exemplo passa a ser gerado a partir de `plugins/fishing/` do monorepo.

## Para o autor da VN

Insira o passo **Minigame → Fishing session** (em pt-BR, *Sessão de pesca*) numa cena, escolha a dificuldade e diga para onde ir em **Won** e **Lost** (*Ganhou* e *Perdeu*). Em "O que muda na história", as sugestões prontas são: guardar se venceu, somar a pontuação ÷ 100 e somar moedas (10 por peixe).

Como plugin oficial, os textos-fonte estão em inglês (`default_locale: en`) e a tradução pt-BR vem em `plugin_locales` (Req §9.1).

O plugin não altera nenhuma variável do projeto. Ele mantém duas variáveis próprias, que aparecem no Studio como "do plugin Fishing Minigame" e podem ser usadas em condições: *Fish caught (total)* e *Best fishing score* (em pt-BR, *Peixes pescados (total)* e *Melhor pontuação de pesca*).

## Permissões e por quê

| Capacidade | Motivo |
| --- | --- |
| `ui.overlay` | Desenhar o lago sobre a cena |
| `input.capture` | Receber o "fisgar" do jogador durante a pescaria |
| `audio.play` | Som do peixe raro (o asset escolhido em *Rare fish sound* na configuração) |
| `profile.data` | Quadro de recordes *High scores* do modo livre |
| `events.emit` | Avisar a história com `fishing.completed` e `fishing.rare_fish_caught` |
| `save.data` | Guardar o nível da vara e se o tutorial já foi visto |
| `editor:preview` | Desenhar o substituto do minijogo no Preview no Studio |

## Desenvolvimento

```bash
vnplugin godot install      # editor do Godot na versão exata do runtime
vnplugin godot open         # abre o projeto; F5 roda o sandbox
vnplugin test               # tests/runtime com relógio virtual
vnplugin link ../seaside-story   # depurar dentro de uma VN (modo desenvolvedor do Studio)
```

`editor/dist/` é gerado a partir de `editor/src/`. O plugin não traz assets de áudio: o som do peixe raro é um asset do projeto escolhido na configuração (`rare_fish_sound`, formato `vn-asset`).
