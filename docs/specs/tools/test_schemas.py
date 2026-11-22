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


def bundle_asset(path):
    return "bundle.schema.json#/properties/assets", {"bg/x": {"type": "background", "path": path}}


def rpc(method, params):
    return "preview-protocol.schema.json", {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}


SCENE = "019a7a00-1388-7f6b-b667-94bbd1305982"


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
    (True, "RT §2: asset do build em res://", *bundle_asset("res://vn_content/assets/backgrounds/x.png")),
    (True, "PP §1.3: asset do bundle do Preview, relativo a assets/", *bundle_asset("backgrounds/noraneko/Train_beach.png")),
    (False, "PP §1.3: URL com esquema no bundle", *bundle_asset("file:///C:/jogo/assets/x.png")),
    (False, "PP §1.3: URL vnpreview no bundle", *bundle_asset("vnpreview://localhost/assets/x.png")),
    (False, "PP §1.3: caminho absoluto no bundle", *bundle_asset("/home/autor/x.png")),
    (False, "PP §1.3: caminho que sai da pasta de assets", *bundle_asset("../segredo.png")),
    (True, "REPO §3.2 / BS §9.2: id de plugin do jogo com _", *plugins("seaside_story.quiz")),
    (True, "SDK §3: id oficial", *plugins("vnstudio.fishing")),
    (True, "REPO §3.2 no lock", *lock("seaside_story.quiz")),
    (False, "id de plugin sem ponto", *plugins("seaside_story")),
    (False, "id de plugin com maiúscula", *plugins("Seaside.quiz")),
    (True, "PP §1.1: hello no painel, sem token", *rpc("session.hello", {"protocol": "1.0"})),
    (True, "PP §3: load no painel", *rpc("preview.load", {"bundle_url": "vnpreview://localhost/narrative", "assets_base": "vnpreview://localhost/assets/"})),
    (True, "PP §1.3: load no painel no Windows (WebView2)",
     *rpc("preview.load", {"bundle_url": "http://vnpreview.localhost/narrative", "assets_base": "http://vnpreview.localhost/assets/"})),
    (True, "PP §1.3: load na janela", *rpc("preview.load", {"bundle_path": "C:/Users/autor/jogo/.vnstudio/preview/narrative", "assets_base": "C:/Users/autor/jogo/assets"})),
    (False, "PP §1.3: load sem assets_base", *rpc("preview.load", {"bundle_url": "vnpreview://localhost/narrative"})),
    (False, "PP §3: load com caminho e URL ao mesmo tempo",
     *rpc("preview.load", {"bundle_path": ".vnstudio/preview/narrative", "bundle_url": "vnpreview://localhost/narrative"})),
    (True, "PP §3: recarga incremental de uma cena",
     *rpc("preview.reload", {"patch": [{"file": "bundle.json", "pointer": f"/scenes/{SCENE}", "value": {}}]})),
    (True, "PP §3: recarga incremental de um texto (barra escrita ~1) e remoção",
     *rpc("preview.reload", {"patch": [{"file": "locales/pt-BR.json", "pointer": "/strings/ui~1title~1btn_continue", "value": "Continuar"},
                                       {"file": "bundle.json", "pointer": "/ui/extras"}]})),
    (True, "PP §3: recarga completa na janela", *rpc("preview.reload", {"bundle_path": ".vnstudio/preview/narrative", "changed": ["ui/title.json"]})),
    (False, "PP §3: patch misturado com recarga completa",
     *rpc("preview.reload", {"patch": [{"file": "bundle.json", "pointer": "/theme", "value": {}}], "bundle_path": "x", "changed": []})),
    (False, "PP §3: patch em arquivo fora da forma canônica",
     *rpc("preview.reload", {"patch": [{"file": "scenes/x.json", "pointer": "/x", "value": {}}]})),
    (True, "PP §3: concluir atividade pelo formulário do Studio",
     *rpc("preview.input", {"action": "complete_activity", "outcome": "won", "payload": {"fish_count": 3}})),
    (False, "PP §3: complete_activity sem outcome", *rpc("preview.input", {"action": "complete_activity"})),
    (True, "PP §1.4: load guardando os saves do Preview no projeto",
     *rpc("preview.load", {"bundle_url": "vnpreview://localhost/narrative", "assets_base": "vnpreview://localhost/assets/", "user_data": "project"})),
    (False, "PP §1.4: user_data desconhecido", *rpc("preview.load", {"bundle_path": "x", "user_data": "disk"})),
    (True, "PP §3: start com o modo stream ligado", *rpc("preview.start", {"content_filter": True, "paused": True})),
    (True, "PP §3: botão Modo stream do Preview", *rpc("preview.set_setting", {"setting": "content_filter", "value": True})),
    (False, "PP §3: set_setting sem valor", *rpc("preview.set_setting", {"setting": "content_filter"})),
    (True, "PP §3: galeria desbloqueada e fim de minijogo simulados",
     *rpc("preview.show_screen", {"screen": "gallery", "simulate": {"gallery_unlock_all": True, "seen_assets": ["bg/train_beach"],
                                                                     "content_filter": True, "last_activity_outcome": "won", "last_record_rank": 1}})),
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
