#!/usr/bin/env python3
"""Confere os padrões dos schemas contra os formatos que as specs mandam gravar.

Cada caso monta um documento mínimo com um valor tirado do texto das specs e
confere se o schema aceita (ou recusa) esse valor. Serve para pegar padrões
mais estreitos (ou mais largos) que a regra escrita.

Uso: python3 tools/test_schemas.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate import validator  # noqa: E402


def locale(key):
    return "locale.schema.json", {"locale": "pt-BR", "strings": {key: "texto"}}


def plugins(pid):
    return "plugins.schema.json", {"plugins": {pid: {"version": "^1.0.0", "source": "path:plugins/quiz"}}}


def lock(pid):
    entry = {"version": "1.0.0", "namespace": "quiz", "resolved": "plugins/quiz", "enabled": True,
             "integrity": "sha256-" + "A" * 43 + "="}
    return "plugin-lock.schema.json", {"lock_version": 1, "plugins": {pid: entry}}


CASES = [
    # (aceita?, origem na spec, schema, documento)
    (True, "DM §9: rótulo de valor de enum (id qualificado tem ponto)", *locale("variable/global.mood/value/calm")),
    (True, "DM §9: rótulo de variável de personagem", *locale("variable/character.alice.trust/name")),
    (True, "UI §3.3: opção de select de idioma (tag BCP 47)", *locale("ui/settings/sel_lang/option/pt-BR")),
    (True, "UI §3.3: opção com subtag de escrita", *locale("ui/settings/sel_lang/option/zh-Hans")),
    (True, "DM §9: fala de cena (como no demo)", *locale("019a7a00-1388-7f6b-b667-94bbd1305982/019a7a00-3a98-732b-89dd-170487226b34")),
    (True, "UI §3.3: botão de tela (como no demo)", *locale("ui/title/btn_continue")),
    (False, "chave sem barra", *locale("variable")),
    (False, "primeiro segmento com maiúscula", *locale("UI/settings/title")),
    (False, "segmento vazio", *locale("ui//title")),
    (True, "REPO §3.2 / BS §9.2: id de plugin do jogo com _", *plugins("seaside_story.quiz")),
    (True, "SDK §3: id oficial", *plugins("vnstudio.fishing")),
    (True, "REPO §3.2 no lock", *lock("seaside_story.quiz")),
    (False, "id de plugin sem ponto", *plugins("seaside_story")),
    (False, "id de plugin com maiúscula", *plugins("Seaside.quiz")),
]


def main():
    failures = 0
    for accept, desc, schema, doc in CASES:
        errs = list(validator(schema).iter_errors(doc))
        ok = (not errs) == accept
        print(f"{'ok     ' if ok else 'FALHOU '} {'aceita' if accept else 'recusa'}: {desc}")
        if not ok:
            failures += 1
            for e in errs[:3]:
                print("         ", e.message[:160])
    print(f"\n{len(CASES) - failures}/{len(CASES)} casos passaram.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
