#!/usr/bin/env python3
"""Casos de teste do validador de referência.

Cada caso copia examples/demo-project e examples/fishing-plugin para uma pasta
temporária, quebra uma coisa de propósito e confere se o validador acusa o
código esperado. O demo sem alterações precisa passar sem erros nem avisos.

Uso: python3 tools/test_validate.py
"""
import json, shutil, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import validate  # noqa: E402

DEMO = HERE.parent / "examples" / "demo-project"
PLUGIN = HERE.parent / "examples" / "fishing-plugin"

CH01 = "019a7a00-03e8-7e8e-9f34-b5a38f4a780b"
CH02 = "019a7a00-07d0-79cc-8832-8bb38a8122f3"
BEACH = "scenes/ch01/scene_beach.json"
MASTER = "scenes/ch01/scene_fishing_master.json"
QUIET = "scenes/ch01/scene_quiet_day.json"
FESTIVAL_ID = "019a7a00-1f40-7bda-a77e-3d949dc6efb2"
ALICE = "019a7a00-0bb8-7dc0-b468-e39508f1443d"
TITLE = "ui/title.json"
SETTINGS = "ui/settings.json"
SET = "sets/beach_title.json"
EXTRAS = "ui/extras.json"


class Workspace:
    def __init__(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.proj = self.tmp / "demo"; self.plug = self.tmp / "fishing"
        shutil.copytree(DEMO, self.proj); shutil.copytree(PLUGIN, self.plug)

    def edit(self, rel, fn, plugin=False):
        p = (self.plug if plugin else self.proj) / rel
        d = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
        fn(d)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")

    def text(self, rel, fn, plugin=True):
        p = (self.plug if plugin else self.proj) / rel
        p.write_text(fn(p.read_text(encoding="utf-8")), encoding="utf-8")


def nodes_of(scene, t):
    return [n for n in scene["nodes"] if n["type"] == t]

def uid(n):  # UUIDs novos, válidos e únicos para os casos
    return f"019a7aff-{n:04x}-7000-8000-000000000000"


CASES = [
    # (código, descrição, mutação, export)
    ("S000", "campo desconhecido no projeto", lambda w: w.edit("project.json", lambda d: d.update(xyz=1)), False),
    ("S000", "namespace de plugin reservado", lambda w: w.edit("plugin.json", lambda d: d.update(namespace="story"), plugin=True), False),
    ("R001", "UUID repetido entre cena e capítulo", lambda w: w.edit(QUIET, lambda d: d.update(id=CH02)), False),
    ("R002", "variável global duplicada", lambda w: w.edit("variables.json", lambda d: d["global"].append(dict(d["global"][0]))), False),
    ("R003", "initial_values de variável inexistente", lambda w: w.edit("characters/alice.json", lambda d: d["initial_values"].update(nada=1)), False),
    ("R004", "asset não registrado", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "background")[0].update(asset="bg/nao_existe")), False),
    ("R005", "variável inexistente em condição", lambda w: w.edit(MASTER, lambda d: d["scheduling"]["conditions"][0].update(variable="global.nao_existe")), False),
    ("R005", "sys.scenes de cena inexistente", lambda w: w.edit(MASTER, lambda d: d["scheduling"]["conditions"][0].update(variable=f"sys.scenes.{uid(1)}.plays", value=1)), False),
    ("R005", "derivada lê variável inexistente", lambda w: w.edit("variables.json", lambda d: d["global"][3]["derived"]["if"][0].update(variable="global.nao_existe")), False),
    ("R006", "then.scene inexistente", lambda w: w.edit(MASTER, lambda d: nodes_of(d, "end")[0].update(then={"scene": uid(2)})), False),
    ("R007", "start_chapter inexistente", lambda w: w.edit("project.json", lambda d: d.update(start_chapter=uid(3))), False),
    ("R008", "grupo de exclusividade não definido", lambda w: w.edit(MASTER, lambda d: d["scheduling"].update(exclusive_groups=["nada"])), False),
    ("R009", "goto para nó inexistente", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "choice")[0]["options"][0].update(goto=uid(4))), False),
    ("R009", "start inexistente", lambda w: w.edit(QUIET, lambda d: d.update(start=uid(5))), False),
    ("R010", "speaker inexistente", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "line")[0].update(speaker=uid(6))), False),
    ("R011", "expressão inexistente", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "show")[0].update(expression="angry")), False),
    ("R012", "final não declarado", lambda w: w.edit("scenes/ch02/scene_festival.json", lambda d: nodes_of(d, "end")[0].update(ending="nenhum")), False),
    ("R013", "build.locales sem default_locale", lambda w: w.edit("project.json", lambda d: d["build"].update(locales=["en"])), False),
    ("R014", "then.scene para cena de outro capítulo", lambda w: w.edit(MASTER, lambda d: nodes_of(d, "end")[0].update(then={"scene": FESTIVAL_ID})), False),
    ("R015", "grupo no projeto e no capítulo", lambda w: w.edit("project.json", lambda d: d.update(exclusive_groups=[{"id": "evening_event"}])), False),
    ("R016", "record com valor fora do enum", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "choice")[0]["options"][0].update(value="outro")), False),
    ("R016", "record em variável inteira", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "choice")[0].update(record="global.player_money")), False),
    ("R017", "profile em variável de personagem", lambda w: w.edit("variables.json", lambda d: d["character"][0].update(persistence="profile")), False),
    ("R018", "marcação desequilibrada", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "line")[0].update(text="[b]Oi!")), False),
    ("R018", "marcação desconhecida", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "line")[0].update(text="[shake]Oi![/shake]")), False),
    ("R018", "parâmetro de marcação inválido", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "line")[0].update(text="[color=azul]Oi![/color]")), False),
    ("R019", "interpolação de variável inexistente", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "line")[0].update(text="Tenho {global.nao_existe}")), False),
    ("R019", "interpolação de chapter.* em display_name", lambda w: w.edit("characters/alice.json", lambda d: d.update(display_name="Alice ({chapter.days_passed})")), False),
    ("R020", "emit fora de story.*", lambda w: w.edit(MASTER, lambda d: nodes_of(d, "emit")[0].update(event="fishing.completed")), False),
    ("R021", "exportação sem version", lambda w: w.edit("project.json", lambda d: d.pop("version")), True),
    ("R011", "default_expression inexistente", lambda w: w.edit("characters/alice.json", lambda d: d.update(default_expression="angry")), False),
    ("R007", "project.chapters com capítulo inexistente", lambda w: w.edit("project.json", lambda d: d["chapters"].append(uid(10))), False),
    ("T001", "literal de tipo errado", lambda w: w.edit(MASTER, lambda d: d["scheduling"]["conditions"][0].update(value=3)), False),
    ("T001", "comparação entre variáveis de tipos diferentes", lambda w: w.edit(MASTER, lambda d: d["scheduling"]["conditions"][0].update(value={"var": "global.player_money"})), False),
    ("T002", "efeito em variável de plugin", lambda w: w.edit(QUIET, lambda d: nodes_of(d, "effects")[0]["effects"].append({"op": "add", "variable": "plugin.fishing.total_caught", "value": 1})), False),
    ("T003", "add em booleana", lambda w: w.edit(QUIET, lambda d: nodes_of(d, "effects")[0]["effects"].append({"op": "add", "variable": "global.fishing_won", "value": 1})), False),
    ("T004", "ciclo entre derivadas", lambda w: w.edit("variables.json", lambda d: d["global"].append({"key": "a", "type": "integer", "derived": {"var": "global.b"}}) or d["global"].append({"key": "b", "type": "integer", "derived": {"var": "global.a"}})), False),
    ("T005", "{result} fora de on_result", lambda w: w.edit(QUIET, lambda d: nodes_of(d, "effects")[0]["effects"].append({"op": "set", "variable": "global.fishing_skill", "value": {"result": "score"}})), False),
    ("T005", "{result} com campo fora do result_schema", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "plugin")[0]["on_result"]["effects"][0].update(value={"result": "nada"})), False),
    ("T006", "set de inteiro com variável booleana", lambda w: w.edit(QUIET, lambda d: nodes_of(d, "effects")[0]["effects"].append({"op": "set", "variable": "global.fishing_skill", "value": {"var": "global.fishing_won"}})), False),
    ("T006", "{result} booleano somado a inteiro", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "plugin")[0]["on_result"]["effects"][1].update(value={"result": "won"})), False),
    ("T006", "derivada que calcula outro tipo", lambda w: w.edit("variables.json", lambda d: d["global"][3].update(type="integer")), False),
    ("T007", "clamp com um argumento", lambda w: w.edit(QUIET, lambda d: nodes_of(d, "effects")[0]["effects"].append({"op": "set", "variable": "global.fishing_skill", "value": {"fn": "clamp", "args": [1]}})), False),
    ("T007", "mod com número real", lambda w: w.edit(QUIET, lambda d: nodes_of(d, "effects")[0]["effects"].append({"op": "set", "variable": "global.fishing_skill", "value": {"fn": "mod", "args": [7.5, 2]}})), False),
    ("T008", "random_int em derivada", lambda w: w.edit("variables.json", lambda d: d["global"].append({"key": "dado", "type": "integer", "derived": {"fn": "random_int", "args": [1, 6]}})), False),
    ("P001", "dois plugins com o mesmo namespace", None, False),  # tratado em run_case
    ("P002", "atividade inexistente", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "plugin")[0].update(activity="fishing.nada")), False),
    ("P003", "plugin fora de plugins.json", lambda w: w.edit("plugins.json", lambda d: d.update(plugins={})), False),
    ("P004", "params inválidos", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "plugin")[0]["params"].update(difficulty="impossivel")), False),
    ("P005", "outcome não declarado", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "plugin")[0]["on_result"]["outcomes"].update(empate=nodes_of(d, "end")[0]["id"])), False),
    ("P006", "capacidade concedida sem pedido", lambda w: w.edit("plugins.json", lambda d: d["plugins"]["vnstudio.fishing"]["grants"]["capabilities"].append("runtime:variables.write")), False),
    ("P007", "variável concedida sem pedido", lambda w: w.edit("plugins.json", lambda d: d["plugins"]["vnstudio.fishing"]["grants"]["variables"]["read"].append("global.player_money")), False),
    ("P008", "escrita concedida em variável que não aceita", lambda w: (w.edit("plugin.json", lambda d: d.update(variable_permissions={"write": ["global.fishing_skill"]}), plugin=True), w.edit("plugins.json", lambda d: d["plugins"]["vnstudio.fishing"]["grants"]["variables"]["write"].append("global.fishing_skill"))), False),
    ("P009", "evento fora do namespace", lambda w: w.edit("plugin.json", lambda d: d["events"]["emits"][0].update(name="pesca.completed"), plugin=True), False),
    ("P010", "outcome_labels de outcome inexistente", lambda w: w.edit("plugin.json", lambda d: d["activities"][0]["outcome_labels"].update(empate="Empate"), plugin=True), False),
    ("P011", "class_name sem prefixo", lambda w: w.text("runtime/scenes/fishing_game.gd", lambda s: s.replace("class_name FishingGame", "class_name LakeGame")), False),
    ("P012", "caminho res:// fora do plugin", lambda w: w.text("runtime/src/fishing_plugin.gd", lambda s: s.replace('preload("res://vn_plugins/fishing/', 'preload("res://outro/')), False),
    ("P013", "vínculo de desenvolvimento na exportação", lambda w: w.edit(".vnstudio/plugin-lock.local.json", lambda d: d.update(lock_version=1, plugins={"vnstudio.fishing": {"version": "1.0.0", "namespace": "fishing", "resolved": "path:../fishing-dev/vn_plugins/fishing", "enabled": True, "trust": "local", "link": True}})), True),
    ("P014", "leitura concedida em variável que não aceita", lambda w: (w.edit("plugin.json", lambda d: d.update(variable_permissions={"read": ["global.fishing_skill"]}), plugin=True), w.edit("plugins.json", lambda d: d["plugins"]["vnstudio.fishing"]["grants"]["variables"]["read"].append("global.fishing_skill"))), False),
    ("P015", "lock fora da faixa de plugins.json", lambda w: w.edit("plugins.json", lambda d: d["plugins"]["vnstudio.fishing"].update(version="^2.0.0")), False),
    ("P016", "network pedida por plugin não oficial", lambda w: w.edit("plugin.json", lambda d: d.update(id="fulano.fishing") or d["capabilities"]["editor"].append("network"), plugin=True), False),
    ("P017", "variável de plugin com access", lambda w: w.edit("plugin.json", lambda d: d["variables"][0].update(access={"plugins_read": "all"}), plugin=True), False),
    ("P017", "escrita em variável de outro plugin", lambda w: w.edit("plugin.json", lambda d: d.update(variable_permissions={"write": ["plugin.inventory.items"]}), plugin=True), False),
    ("P018", "asset inexistente em campo vn-asset da config", lambda w: (w.edit("plugin.json", lambda d: d["config_schema"]["properties"].update(lake_bg={"type": "string", "format": "vn-asset", "title": "Fundo do lago"}), plugin=True), w.edit("plugins.json", lambda d: d["plugins"]["vnstudio.fishing"]["config"].update(lake_bg="bg/nao_existe"))), False),
    ("W001", "nó inalcançável", lambda w: w.edit(QUIET, lambda d: d["nodes"].extend([{"id": uid(7), "type": "end"}, {"id": uid(8), "type": "line", "text": "nunca"}])), False),
    ("W002", "outcome sem destino", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "plugin")[0]["on_result"]["outcomes"].pop("lost")), False),
    ("W003", "tradução órfã", lambda w: w.edit("locales/en/scene_beach.json", lambda d: d["strings"].update({f"019a7a00-1388-7f6b-b667-94bbd1305982/{uid(9)}": "orphan"})), False),
    ("W004", "manifesto não fornecido", None, False),  # tratado em run_case
    ("W006", "todas as opções com visible_if", lambda w: w.edit(BEACH, lambda d: [o.update(visible_if=[]) for o in nodes_of(d, "choice")[0]["options"]]), False),
    ("W007", "parâmetro sem title", lambda w: w.edit("plugin.json", lambda d: d["activities"][0]["params_schema"]["properties"]["target_fish"].pop("title"), plugin=True), False),
    ("W008", "plataforma fora do plugin", lambda w: w.edit("plugin.json", lambda d: d["compatibility"].update(platforms=["web"]), plugin=True), False),
    ("W009", "API vetada", lambda w: w.text("runtime/src/fishing_plugin.gd", lambda s: s + "\nfunc _x() -> void:\n\tOS.execute(\"ls\", [])\n"), False),
    ("W010", "fallback que não progride", lambda w: w.edit(QUIET, lambda d: nodes_of(d, "effects")[0]["effects"].__setitem__(0, {"op": "add", "variable": "global.player_money", "value": 1})), False),
    ("W011", "ending sem end_game", lambda w: w.edit("scenes/ch02/scene_festival.json", lambda d: nodes_of(d, "end")[0].update(then="schedule")), False),
    ("W012", "subscribes sem capacidade", lambda w: w.edit("plugin.json", lambda d: d["events"].update(subscribes=["story.*"]), plugin=True), False),
    ("W013", "passo incompleto", lambda w: w.edit(QUIET, lambda d: d["nodes"][0].update(unresolved={"reason": "cenário não encontrado"})), False),
    ("W013", "passo incompleto bloqueia exportação", lambda w: w.edit(QUIET, lambda d: d["nodes"][0].update(unresolved={"reason": "cenário não encontrado"})), True),
    ("W014", "fonte usada como cenário", lambda w: w.edit(BEACH, lambda d: nodes_of(d, "background")[0].update(asset="font/body")), False),
    ("W015", "evento story não declarado", lambda w: w.edit(MASTER, lambda d: nodes_of(d, "emit")[0].update(event="story.outro")), False),
    ("W017", "div gravado em inteiro", lambda w: w.edit(QUIET, lambda d: nodes_of(d, "effects")[0]["effects"].append({"op": "add", "variable": "global.fishing_skill", "value": {"fn": "div", "args": [7, 2]}})), False),
    ("W018", "capítulo fora de project.chapters", lambda w: w.edit("project.json", lambda d: d["chapters"].pop()), False),
    ("W019", "event_since_last_selection com sys.*", lambda w: w.edit(MASTER, lambda d: d["scheduling"]["conditions"].append({"event_since_last_selection": "sys.scene_ended"})), False),
    ("W016", "chave runtime/ sem texto-fonte", lambda w: w.edit("plugin.json", lambda d: d["plugin_locales"]["en"].pop("runtime/hud/time_left"), plugin=True), False),
    # UI Spec §11: telas, sets, estilos e nó interact
    ("U001", "open_screen para tela inexistente", lambda w: w.edit(TITLE, lambda d: d["elements"][1]["children"][3]["actions"][0].update(screen="nada")), False),
    ("U001", "estado inexistente em camada do set", lambda w: w.edit(TITLE, lambda d: d["on_open"][0].update(state="tarde")), False),
    ("U001", "focus_start inexistente", lambda w: w.edit(TITLE, lambda d: d.update(focus_start="btn_nada")), False),
    ("U001", "set inexistente no fundo da cena", lambda w: w.edit(QUIET, lambda d: nodes_of(d, "background")[0].update(set="nada")), False),
    ("U001", "interact com camada que a cena não mostra", lambda w: w.edit(QUIET, lambda d: nodes_of(d, "interact")[0]["hotspots"][1].update(area={"layer": "barco"})), False),
    ("U002", "estilo inexistente", lambda w: w.edit(TITLE, lambda d: d["elements"][1]["children"][0].update(style="prata")), False),
    ("U002", "ciclo em extends", lambda w: w.edit("theme.json", lambda d: d["styles"]["button"].update(extends="gold")), False),
    ("U003", "título lê variável que não é profile", lambda w: w.edit(TITLE, lambda d: d["elements"][1]["children"][0].update(visible_if=[{"variable": "global.player_money", "operator": "greater_than", "value": 0}])), False),
    ("U004", "ação narrativa em hotspot de set", lambda w: w.edit(SET, lambda d: d["hotspots"][0]["on_press"].append({"do": "open_screen", "screen": "settings"})), False),
    ("U004", "save na tela de título", lambda w: w.edit(TITLE, lambda d: d["elements"][1]["children"][2]["actions"].append({"do": "quick_save"})), False),
    ("U005", "toggle ligado a volume", lambda w: w.edit(SETTINGS, lambda d: d["elements"][2]["children"][3].update(type="toggle", bind="volume.music")), False),
    ("U005", "opção de FPS com tipo errado", lambda w: w.edit(SETTINGS, lambda d: d["elements"][2]["children"][4]["options"][0].update(value="30")), False),
    ("U006", "título sem new_game", lambda w: w.edit(TITLE, lambda d: d["elements"][1]["children"].pop(1)), False),
    ("U007", "elemento fora da tela", lambda w: w.edit(SETTINGS, lambda d: d["elements"][3].update(size=[400, 300], position=[0.5, 0.98])), False),
    ("U008", "botão só com ícone e sem tooltip", lambda w: w.edit(TITLE, lambda d: d["elements"][2].pop("tooltip")), False),
    ("R009", "interact com goto inexistente", lambda w: w.edit(QUIET, lambda d: nodes_of(d, "interact")[0]["hotspots"][0].update(goto=uid(40))), False),
    ("R016", "record de interact em variável inteira", lambda w: w.edit(QUIET, lambda d: nodes_of(d, "interact")[0].update(record="global.player_money")), False),
    ("W006", "interact pode ficar sem hotspots", lambda w: w.edit(QUIET, lambda d: [h.update(visible_if=[{"variable": "global.fishing_won", "operator": "equals", "value": True}]) for h in nodes_of(d, "interact")[0]["hotspots"]] and nodes_of(d, "interact")[0].pop("exit")), False),
    ("W003", "tradução órfã de tela", lambda w: w.edit("locales/en/ui/title.json", lambda d: d["strings"].update({"ui/title/btn_nada": "Nothing"})), False),
    ("W014", "som de estilo com asset de imagem", lambda w: w.edit("theme.json", lambda d: d["styles"]["button"]["sounds"].update(press="ui/logo")), False),
    # Plugin SDK §6.1 e §9.1: modo livre, perfil e recordes
    ("P019", "records sem a capacidade profile.data", lambda w: w.edit("plugin.json", lambda d: d["capabilities"]["runtime"].remove("profile.data"), plugin=True), False),
    ("P020", "play_activity para atividade sem free_play", lambda w: w.edit("plugin.json", lambda d: d["activities"][0].pop("free_play"), plugin=True), False),
    ("P020", "play_activity para atividade inexistente", lambda w: w.edit(EXTRAS, lambda d: d["elements"][1]["actions"][0].update(activity="fishing.nada")), False),
    ("P004", "params do modo livre inválidos", lambda w: w.edit(EXTRAS, lambda d: d["elements"][2]["actions"][0].update(params={"difficulty": "insana"})), False),
    ("U001", "quadro de recordes inexistente", lambda w: w.edit(EXTRAS, lambda d: d["elements"][3].update(board="fishing.nada")), False),
    ("U004", "play_activity na tela de pausa", lambda w: w.edit(EXTRAS, lambda d: d.update(kind="pause")), False),
    # spec 09: fontes path:
    ("P021", "plugin embutido sem pasta", lambda w: w.edit("plugins.json", lambda d: d["plugins"].update({"seaside_story.quiz": {"version": "^0.1.0", "source": "path:plugins/quiz"}})), False),
    ("P021", "pacote guardado inexistente", lambda w: w.edit("plugins.json", lambda d: d["plugins"]["vnstudio.fishing"].update(source="path:vendor/plugins/vnstudio.fishing-1.0.0.vnplugin")), False),
]


def run_case(code, mutate, export):
    w = Workspace()
    plugins = [w.plug]
    if code == "P001":
        twin = w.tmp / "twin"; shutil.copytree(w.plug, twin)
        t = json.loads((twin / "plugin.json").read_text(encoding="utf-8")); t["id"] = "outro.fishing"
        (twin / "plugin.json").write_text(json.dumps(t), encoding="utf-8"); plugins.append(twin)
    elif code == "W004":
        plugins = []
    else:
        mutate(w)
    errs, warns = validate.run(w.proj, plugins, export)
    shutil.rmtree(w.tmp)
    return errs, warns


def main():
    errs, warns = validate.run(DEMO, [PLUGIN])
    failures = 0
    if errs or warns:
        print("FALHOU  demo sem alterações deveria passar limpo:", *(errs + warns), sep="\n  "); failures += 1
    for code, desc, mutate, export in CASES:
        errs, warns = run_case(code, mutate, export)
        bucket = errs if (export or not (code.startswith("W") or code in ("U007", "U008"))) else warns
        hit = any(m.startswith(f"[{code}]") for m in bucket)
        print(f"{'ok     ' if hit else 'FALHOU '} {code} {desc}{' (--export)' if export else ''}")
        if not hit:
            failures += 1
            for m in (errs + warns)[:5]: print("         ", m)
    print(f"\n{len(CASES) + 1 - failures}/{len(CASES) + 1} casos passaram.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
