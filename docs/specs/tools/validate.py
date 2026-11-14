#!/usr/bin/env python3
"""Validador de referência do Narrative Data Model v1 (protótipo).

Uso: python3 validate.py [--export] <pasta-do-projeto> [<pasta-de-plugin>...]

--export aplica também as regras de exportação (P013; W013 vira erro).

1. Valida cada arquivo contra seu JSON Schema.
2. Aplica as regras semânticas da seção 11 do Narrative Data Model
   (integridade de referências, tipos, alcance de nós, permissões).

É a implementação de referência: o validador do Studio DEVE dar o mesmo
resultado nos casos de tools/test_validate.py (Req §13).
"""
import json, sys, re, fnmatch
from pathlib import Path
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

SCHEMAS = Path(__file__).resolve().parent.parent / "schemas"
BASE = "https://schemas.vnstudio.dev/1/"

def load(p): return json.loads(Path(p).read_text(encoding="utf-8"))

registry = Registry()
for f in SCHEMAS.glob("*.schema.json"):
    registry = registry.with_resource(BASE + f.name, Resource.from_contents(load(f)))

def validator(name):
    return Draft202012Validator({"$ref": BASE + name}, registry=registry)

# chave do tema/projeto → tipos de asset aceitos (R004 e W014)
IMG = {"image", "background"}
ASSET_KEYS = {"image": IMG, "background": IMG, "overlay": IMG, "logo": IMG, "icon": {"image"}, "splash": IMG,
              "button": {"image"}, "button_hover": {"image"}, "button_disabled": {"image"}, "advance_indicator": {"image"},
              "locked_image": IMG, "music": {"audio_music"}, "click": {"audio_sfx"}, "hover": {"audio_sfx"},
              "choice": {"audio_sfx"}, "dialogue": {"font"}, "name": {"font"}, "ui": {"font"},
              "font": {"font"}, "cursor": IMG, "locked_asset": IMG, "asset": IMG | {"sprite", "video"}}
# subárvores do tema/telas em que toda string é asset de um tipo fixo (chave da string não importa)
ASSET_CTX = {"sounds": {"audio_sfx"}, "fonts": {"font"}, "fallbacks": {"font"}}
CURSORS = {"default", "look", "talk", "use", "walk"}
AUDIO_TYPES = {"music": {"audio_music"}, "ambient": {"audio_music", "audio_sfx"}, "sfx": {"audio_sfx"}, "voice": {"audio_voice"}}
MARKUP = re.compile(r"\[\[|\]\]|\[(/?)([a-z]+)(=[^\]]*)?\]")
PAIRED, SINGLE = {"b", "i", "color", "speed"}, {"pause"}
SYS_FIXED = {"sys.chapter.id": "string", "sys.scene.id": "string", "sys.selection_count": "integer",
             "sys.locale": "string", "sys.save_modified": "boolean",
             "sys.ui.has_save": "boolean", "sys.ui.in_game": "boolean", "sys.ui.platform": "string", "sys.ui.activity": "boolean"}
# UI Spec §4, §5.1, §8
COSMETIC = {"set_state", "toggle_state", "play_animation", "play_sfx", "show", "hide", "toggle_visible"}
TITLE_ONLY = {"new_game", "continue"}
GAME_ONLY = {"return_to_title", "save", "quick_save", "toggle_auto", "toggle_skip", "hide_textbox", "open_backlog", "emit"}
FIXED_SCREENS = {"title", "pause", "save", "load", "settings", "gallery", "credits", "hud"}
DEFAULT_STYLES = {"button", "choice", "slot", "slider", "toggle", "select", "hotspot", "label"}
SETTING_TYPES = {"volume.master": "number", "volume.music": "number", "volume.ambient": "number", "volume.sfx": "number",
                 "volume.voice": "number", "display_mode": "string", "resolution": "list", "vsync": "boolean",
                 "fps_limit_vn": "integer", "fps_limit_activity": "integer", "text_speed": "number", "auto_delay": "number",
                 "skip_unread": "boolean", "locale": "string", "text_scale": "number", "reduce_motion": "boolean",
                 "subtitles": "boolean", "high_contrast": "boolean", "show_hotspots": "boolean"}

errors, warnings = [], []
EXPORT = False
def err(code, where, msg): errors.append(f"[{code}] {where}: {msg}")
def warn(code, where, msg): warnings.append(f"[{code}] {where}: {msg}")

def check_schema(path, schema):
    data = load(path)
    for e in sorted(validator(schema).iter_errors(data), key=lambda e: list(e.path)):
        err("S000", path, f"{'/'.join(map(str, e.path)) or '<raiz>'}: {e.message[:200]}")
    return data

# ---------- SemVer mínimo (faixas no estilo node-semver) ----------
def parse_ver(v):
    m = re.match(r"^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?", v.strip().lstrip("v="))
    if not m: return None
    return (int(m.group(1)), int(m.group(2) or 0), int(m.group(3) or 0), m.group(4))
def ver_key(v): return (v[0], v[1], v[2], 0 if v[3] else 1, v[3] or "")
def satisfies(version, rng):
    v = parse_ver(version)
    if v is None: return False
    for alt in rng.split("||"):
        ok = True
        for comp in alt.split():
            m = re.match(r"^(\^|~|>=|<=|>|<|=)?(.+)$", comp)
            op, b = m.group(1) or "=", parse_ver(m.group(2))
            if b is None: ok = False; break
            kv, kb = ver_key(v), ver_key(b)
            if op == "^":
                hi = (b[0] + 1, 0, 0, 0, "") if b[0] else ((0, b[1] + 1, 0, 0, "") if b[1] else (0, 0, b[2] + 1, 0, ""))
                ok = kb <= kv < hi
            elif op == "~": ok = kb <= kv < (b[0], b[1] + 1, 0, 0, "")
            else: ok = {"=": kv == kb, ">=": kv >= kb, "<=": kv <= kb, ">": kv > kb, "<": kv < kb}[op]
            if not ok: break
        if ok: return True
    return False

# ---------- código dos plugins (P011, P012, W009, W016) ----------
BANNED_API = re.compile(r"\b(OS\.(execute|create_process|create_instance|shell_open|kill)|HTTPRequest|HTTPClient|StreamPeerTCP|TCPServer|PacketPeerUDP|UDPServer|WebSocketPeer|Engine\.get_singleton|ProjectSettings\.set_setting|JavaScriptBridge)\b")
ABS_FS = re.compile(r"\b(FileAccess|DirAccess)\.\w+\(\s*\"(?!user://|res://)")
I18N_KEY = re.compile(r"\.text\(\s*\"(runtime/[^\"]+)\"")
def check_plugin_code(pid, m, root):
    ns = m["namespace"]; pascal = "".join(w.capitalize() for w in ns.split("_"))
    allowed = [f"res://vn_plugins/{ns}/", "res://addons/vn_runtime_sdk/"]
    allowed += [f"res://vn_plugins/{d.split('.', 1)[1]}/" for d in m.get("dependencies", {})]  # aproximação: nome ≈ namespace
    base_texts = m.get("plugin_locales", {}).get(m.get("default_locale", ""), {})
    for f in sorted(root.rglob("*")):
        if f.suffix not in (".gd", ".tscn", ".tres") or not f.is_file(): continue
        rel = f"{pid}/{f.relative_to(root)}"
        for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            where = f"{rel}:{i}"
            for path in re.findall(r"res://[^\"' )]+", line):
                if not any(path.startswith(a) for a in allowed): err("P012", where, f"caminho {path} fora de res://vn_plugins/{ns}/")
            if f.suffix != ".gd" or line.lstrip().startswith("#"): continue
            cm = re.match(r"\s*class_name\s+(\w+)", line)
            if cm and not cm.group(1).startswith(pascal): err("P011", where, f"class_name {cm.group(1)} sem o prefixo {pascal}")
            for name in re.findall(r"(?:add_to_group|InputMap\.add_action)\(\s*&?\"([^\"]+)\"", line):
                if not name.startswith(ns + "_"): err("P011", where, f"grupo/ação {name} sem o prefixo {ns}_")
            if BANNED_API.search(line) or ABS_FS.search(line): warn("W009", where, "API do Godot vetada em plugins")
            for key in I18N_KEY.findall(line):
                if key not in base_texts: warn("W016", where, f"{key} sem texto em plugin_locales[{m.get('default_locale')}]")

def walk(o, fn):
    if isinstance(o, dict):
        fn(o)
        for v in o.values(): walk(v, fn)
    elif isinstance(o, list):
        for v in o: walk(v, fn)

def written_vars(o):
    out = set()
    walk(o, lambda d: out.add(d["variable"]) if "op" in d and isinstance(d.get("variable"), str) else None)
    walk(o, lambda d: out.add(d["record"]) if isinstance(d.get("record"), str) else None)
    return out

def read_vars(o):
    out = set()
    def f(d):
        if "operator" in d and isinstance(d.get("variable"), str): out.add(d["variable"])
        if isinstance(d.get("var"), str): out.add(d["var"])
    walk(o, f)
    return out

def markup_param_ok(tag, p):
    if tag in ("b", "i"): return p is None
    if tag == "color": return p is not None and re.fullmatch(r"#[0-9a-fA-F]{6}", p) is not None
    try: v = float(p)
    except (TypeError, ValueError): return False
    return 0 <= v <= 10 if tag == "pause" else 0.1 <= v <= 10

INTERP = re.compile(r"\{\{|\}\}|\{([^{}]*)\}")
def interp_refs(text):
    return [m.group(1).strip() for m in INTERP.finditer(text or "") if m.group(1) is not None]

# tipos de resultado das funções (DM §6.1.1): (mín, máx, tipo dos argumentos)
FN_ARITY = {"add": (2, 2, "num"), "sub": (2, 2, "num"), "mul": (2, 2, "num"), "div": (2, 2, "num"), "mod": (2, 2, "int"),
            "min": (2, 8, "num"), "max": (2, 8, "num"), "clamp": (3, 3, "num"), "round": (1, 1, "num"), "floor": (1, 1, "num"),
            "ceil": (1, 1, "num"), "abs": (1, 1, "num"), "concat": (1, 8, "any"), "random_int": (2, 2, "int")}

def check_markup(text, where):
    stack = []
    for m in MARKUP.finditer(text):
        if m.group(0) in ("[[", "]]"): continue
        close, tag = m.group(1), m.group(2)
        if tag not in PAIRED | SINGLE: err("R018", where, f"marcação desconhecida [{close}{tag}]"); continue
        param = (m.group(3) or "")[1:] if m.group(3) else None
        if not close and not markup_param_ok(tag, param): err("R018", where, f"parâmetro inválido em [{tag}{'=' + param if param is not None else ''}]")
        if tag in SINGLE: continue
        if not close: stack.append(tag)
        elif not stack or stack.pop() != tag: err("R018", where, f"[/{tag}] sem abertura correspondente")
    for tag in stack: err("R018", where, f"[{tag}] sem fechamento")

def ui_elements(elements):
    """Todos os elementos de uma tela, inclusive dentro de containers."""
    for e in elements:
        yield e
        if e.get("type") == "container": yield from ui_elements(e.get("children", []))

def ui_actions(lst):
    """Todas as ações de uma lista, inclusive em else e then."""
    for a in lst or []:
        yield a
        yield from ui_actions(a.get("else"))
        yield from ui_actions(a.get("then"))

def check_ui(root, project, theme, theme_file, screens, sets, assets, resolve, check_style, set_parts, text_paths, vars_, endings, activities, manifests):
    """UI Spec §11: U001–U008."""
    stage_parts = set()
    for st_id in sets:
        layers, hs = set_parts(st_id); stage_parts |= set(layers) | hs
    known_screens = set(screens) | FIXED_SCREENS
    base = project.get("settings", {}).get("resolution", [1920, 1080])

    def profile_ok(ref):
        if ref.startswith("sys.ui.") or ref.startswith("sys.endings."): return True
        d = vars_.get(ref)
        return d is not None and d.get("persistence") == "profile"

    def check_conds(conds, where, title):
        for c in walk_conds(conds):
            for ref in [c.get("variable"), (c.get("value") or {}).get("var") if isinstance(c.get("value"), dict) else None]:
                if not isinstance(ref, str): continue
                if resolve(ref, None, None) is None: err("R005", where, f"variável inexistente ou fora de escopo: {ref}")
                elif title and not profile_ok(ref): err("U003", where, f"{ref}: no título só valem variáveis profile, sys.endings.* e sys.ui.*")

    def check_target(target, where, elem_ids, own_set, in_set):
        """Devolve o conjunto de estados válidos do alvo, ou None se não for camada."""
        kind, _, name = target.rpartition(":")
        if in_set or kind == "set":
            layers, hs = set_parts(own_set) if own_set else ({}, set())
            if own_set is None: err("U001", where, f"{target}: a tela não tem set"); return None
            if name not in layers and name not in hs: err("U001", where, f"{target}: camada ou hotspot inexistente no set {own_set}")
            return layers.get(name)
        if kind == "stage":
            if name not in stage_parts: err("U001", where, f"{target}: nenhum set tem essa camada ou hotspot")
            return None
        if name not in elem_ids: err("U001", where, f"{target}: elemento inexistente na tela")
        return None

    def check_actions(lst, where, ctx):
        """ctx: dict com kind, elem_ids, set, in_set (hotspot de set), title, conf (contador de confirm), path."""
        for a in ui_actions(lst):
            do = a["do"]
            if "if" in a: check_conds(a["if"], where, ctx["title"])
            if ctx["in_set"] and do not in COSMETIC: err("U004", where, f"ação {do} não é cosmética (hotspots de set só aceitam {', '.join(sorted(COSMETIC))})")
            if do in TITLE_ONLY and ctx["kind"] != "title": err("U004", where, f"{do} só vale na tela de título")
            if do in GAME_ONLY and ctx["kind"] == "title": err("U004", where, f"{do} só vale durante o jogo")
            if do == "open_screen" and a["screen"] not in known_screens: err("U001", where, f"tela {a['screen']} não existe")
            if "target" in a:
                states = check_target(a["target"], where, ctx["elem_ids"], ctx["set"], ctx["in_set"])
                for stn in ([a["state"]] if "state" in a else a.get("states", [])):
                    if states is not None and stn not in states: err("U001", where, f"estado {stn} não existe em {a['target']}")
                if do in ("set_state", "toggle_state") and states is None and ":" not in a["target"] and not ctx["in_set"]:
                    err("U001", where, f"{a['target']}: só camadas de set têm estados")
            if do == "effects":
                for e in a["effects"]:
                    d = resolve(e.get("variable", ""), None, None)
                    if d is None: err("R005", where, f"variável inexistente ou fora de escopo: {e.get('variable')}")
                    elif ctx["title"] and d.get("persistence") != "profile": err("U004", where, f"{e['variable']}: no título, effects só em variáveis profile")
            if do == "emit" and not a["event"].startswith("story."): err("R020", where, f"emit de {a['event']}: só eventos story.*")
            if do == "set_setting": check_setting_value(a["setting"], a["value"], where)
            if do == "play_activity":
                if ctx["kind"] in ("pause", "hud"): err("U004", where, "play_activity só vale fora do jogo (título e telas abertas a partir dele)")
                act = activities.get(a["activity"])
                if act is None or "free_play" not in act[1]: err("P020", where, f"atividade {a['activity']} inexistente ou sem free_play")
                else:
                    merged = {**act[1]["free_play"].get("params", {}), **a.get("params", {})}
                    for e in Draft202012Validator(act[1].get("params_schema", {})).iter_errors(merged): err("P004", where, f"params do modo livre: {e.message}")
            if do == "confirm":
                ctx["conf"] += 1; text_paths.add(f"{ctx['path']}/confirm{ctx['conf']}")
                check_markup(a["text"], where)

    def check_setting_value(setting, value, where):
        t = SETTING_TYPES[setting]
        ok = {"number": isinstance(value, (int, float)) and not isinstance(value, bool),
              "integer": isinstance(value, int) and not isinstance(value, bool),
              "boolean": isinstance(value, bool), "string": isinstance(value, str), "list": isinstance(value, list)}[t]
        if not ok: err("U005", where, f"{setting} espera {t}, recebeu {value!r}")
        elif setting == "locale" and value not in project.get("locales", []): err("U005", where, f"idioma {value} fora de project.json → locales")

    for scr_id, scr in screens.items():
        where = f"ui/{scr_id}.json"
        title = scr["kind"] == "title"
        if scr.get("set") and scr["set"] not in sets: err("U001", where, f"set {scr['set']} não existe em sets/")
        elems = list(ui_elements(scr["elements"]))
        ids = [e["id"] for e in elems]
        for dup in sorted({i for i in ids if ids.count(i) > 1}): err("U001", where, f"id de elemento duplicado {dup}")
        elem_ids = set(ids)
        if scr.get("focus_start") and scr["focus_start"] not in elem_ids: err("U001", where, f"focus_start {scr['focus_start']} não existe")
        for k in ("on_open", "on_close", "back"):
            check_actions(scr.get(k), f"{where}/{k}", {"kind": scr["kind"], "elem_ids": elem_ids, "set": scr.get("set"),
                                                        "in_set": False, "title": title, "conf": 0, "path": f"ui/{scr_id}/{k}"})
        all_do = {a["do"] for k in ("on_open", "on_close", "back") for a in ui_actions(scr.get(k))}
        for e in elems:
            ew = f"{where}#{e['id']}"; tp = f"ui/{scr_id}/{e['id']}"
            for k in ("visible_if", "enabled_if"):
                if k in e: check_conds(e[k], ew, title)
            for nb in (e.get("focus") or {}).values():
                if nb not in elem_ids: err("U001", ew, f"vizinho de foco {nb} não existe")
            for k in ("style", "slot_style"):
                if e.get(k): check_style(e[k], ew)
            for k in ("actions", "on_hover"):
                check_actions(e.get(k), ew, {"kind": scr["kind"], "elem_ids": elem_ids, "set": scr.get("set"),
                                             "in_set": False, "title": title, "conf": 0, "path": tp})
                all_do |= {a["do"] for a in ui_actions(e.get(k))}
            for k in ("text", "label"):
                if e.get(k):
                    text_paths.add(tp); check_markup(e[k], ew)
                    for ref in interp_refs(e[k]):
                        if resolve(ref, None, None) is None: err("R019", ew, f"interpolação {{{ref}}}: variável inexistente ou fora de escopo")
                        elif title and not profile_ok(ref): err("U003", ew, f"{{{ref}}}: no título só valem variáveis profile, sys.endings.* e sys.ui.*")
            if e.get("tooltip"): text_paths.add(f"{tp}/tooltip")
            if e.get("empty_text"): text_paths.add(f"{tp}/empty")
            if e["type"] == "records_list":
                ns, _, board = e["board"].partition(".")
                m = next((m for m in manifests.values() if m["namespace"] == ns), None)
                if m is None or board not in {r["id"] for r in m.get("records", [])}: err("U001", ew, f"quadro de recordes {e['board']} não existe")
            for o in e.get("options", []):
                text_paths.add(f"{tp}/option/{o['value']}")
                check_setting_value(e["bind"], o["value"], ew)
            if e["type"] in ("button", "hotspot") and not (e.get("text") or e.get("label") or e.get("tooltip")):
                warn("U008", ew, "elemento clicável sem texto nem tooltip (sem nome para teclado e acessibilidade)")
            if e["type"] == "hotspot" and "layer" in e["area"]:
                check_target(f"set:{e['area']['layer']}", ew, elem_ids, scr.get("set"), False)
            if e["type"] == "hotspot" and "character" in e["area"]:
                err("U001", ew, "área character só vale em nós interact")
            if "bind" in e:
                t = SETTING_TYPES[e["bind"]]
                if e["type"] == "slider" and t not in ("number", "integer"): err("U005", ew, f"slider não serve para {e['bind']} ({t})")
                if e["type"] == "toggle" and t != "boolean": err("U005", ew, f"toggle não serve para {e['bind']} ({t})")
                if e["bind"] == "locale" and e.get("options"):
                    pass
            pos, size = e.get("position"), e.get("size")
            if pos and size:
                piv = e.get("pivot", [0.5, 0.5])
                x0 = pos[0] * base[0] - piv[0] * size[0]; y0 = pos[1] * base[1] - piv[1] * size[1]
                if x0 < 0 or y0 < 0 or x0 + size[0] > base[0] or y0 + size[1] > base[1]:
                    warn("U007", ew, f"elemento sai da tela na resolução base {base[0]}x{base[1]}")
        if scr["kind"] == "title" and "new_game" not in all_do: err("U006", where, "tela de título sem ação new_game")
        if scr["kind"] == "pause" and not ({"close_screen", "back"} & all_do) and "back" not in scr:
            err("U006", where, "tela de pausa sem close_screen nem back")

    for st_id, st in sets.items():
        where = f"sets/{st_id}.json"
        layers, hs = set_parts(st_id)
        ids = [l["id"] for l in st["layers"]] + [h["id"] for h in st.get("hotspots", [])]
        for dup in sorted({i for i in ids if ids.count(i) > 1}): err("U001", where, f"id duplicado {dup} (camadas e hotspots dividem o espaço de ids)")
        for h in st.get("hotspots", []):
            hw = f"{where}#{h['id']}"
            if "character" in h["area"]: err("U001", hw, "área character só vale em nós interact")
            if "layer" in h["area"] and h["area"]["layer"] not in layers: err("U001", hw, f"camada {h['area']['layer']} não existe")
            if h.get("label"): text_paths.add(f"sets/{st_id}/{h['id']}")
            else: warn("U008", hw, "hotspot sem label (sem nome para teclado e acessibilidade)")
            for k in ("on_hover", "on_press", "on_release"):
                check_actions(h.get(k), hw, {"kind": "set", "elem_ids": set(), "set": st_id, "in_set": True,
                                             "title": False, "conf": 0, "path": f"sets/{st_id}/{h['id']}"})

def walk_conds(conds):
    """Condições simples de uma ConditionList (com all/any/not aninhados)."""
    out = []
    walk(conds, lambda o: out.append(o) if "variable" in o and "operator" in o else None)
    return out

def main(root, plugin_dirs):
    root = Path(root)
    project = check_schema(root / "project.json", "project.schema.json")
    variables = check_schema(root / "variables.json", "variables.schema.json")
    assets = check_schema(root / "assets.json", "assets.schema.json")["assets"]
    chars = {c["id"]: c for c in (check_schema(p, "character.schema.json") for p in sorted((root / "characters").glob("*.json")))}
    chapters = {c["id"]: c for c in (check_schema(p, "chapter.schema.json") for p in sorted((root / "chapters").glob("*.json")))}
    scenes, scene_paths = {}, {}
    for p in sorted((root / "scenes").rglob("*.json")):
        s = check_schema(p, "scene.schema.json")
        if s.get("id") in scenes: err("R001", p, f"id de cena duplicado {s['id']}")
        scenes[s.get("id")] = s; scene_paths[s.get("id")] = p
    for p in sorted((root / "locales").rglob("*.json")):
        check_schema(p, "locale.schema.json")
    sets, screens = {}, {}
    for folder, schema, table in (("sets", "set.schema.json", sets), ("ui", "ui-screen.schema.json", screens)):
        for p in sorted((root / folder).glob("*.json")):
            d = check_schema(p, schema)
            if d.get("id") != p.stem: err("U001", f"{folder}/{p.name}", f"id {d.get('id')} difere do nome do arquivo")
            table[p.stem] = d
    plugins_cfg = check_schema(root / "plugins.json", "plugins.schema.json") if (root / "plugins.json").exists() else {"plugins": {}}
    if (root / "plugin-lock.json").exists(): check_schema(root / "plugin-lock.json", "plugin-lock.schema.json")
    local_lock_file = root / ".vnstudio" / "plugin-lock.local.json"
    if local_lock_file.exists(): check_schema(local_lock_file, "plugin-lock.schema.json")
    theme_file = root / project.get("theme", "theme.json")
    theme = check_schema(theme_file, "theme.schema.json") if theme_file.exists() else {}
    lock = load(root / "plugin-lock.json") if (root / "plugin-lock.json").exists() else {"plugins": {}}
    local_lock = load(local_lock_file) if local_lock_file.exists() else {"plugins": {}}
    manifests, plugin_roots = {}, {}
    # fontes path: (spec 09 §3): pacote guardado ou plugin embutido, cujo manifesto é carregado sozinho
    plugin_dirs = list(plugin_dirs)
    for pid, cfg in plugins_cfg["plugins"].items():
        if not cfg["source"].startswith("path:"): continue
        target = root / cfg["source"][5:]
        if target.suffix == ".vnplugin":
            if not target.is_file(): err("P021", f"plugins.json/{pid}", f"pacote {cfg['source'][5:]} não existe")
            continue
        found = sorted(target.glob("vn_plugins/*/plugin.json")) if target.is_dir() else []
        if len(found) != 1:
            err("P021", f"plugins.json/{pid}", f"{cfg['source'][5:]}: esperado exatamente um vn_plugins/<namespace>/plugin.json, achei {len(found)}")
        elif found[0].parent.resolve() not in {Path(x).resolve() for x in plugin_dirs}:
            plugin_dirs.append(found[0].parent)
    for d in plugin_dirs:
        m = check_schema(Path(d) / "plugin.json", "plugin.schema.json")
        manifests[m["id"]] = m; plugin_roots[m["id"]] = Path(d)

    endings = {e["id"] for e in project.get("endings", [])}
    story_events = {e["name"] for e in project.get("events", [])}

    # --- R001: UUIDs únicos no projeto inteiro ---
    seen_ids = {}
    def claim(uid, where):
        if uid in seen_ids: err("R001", where, f"UUID {uid} já usado em {seen_ids[uid]}")
        else: seen_ids[uid] = where
    for cid in chapters: claim(cid, f"chapters/{cid}")
    for cid in chars: claim(cid, f"characters/{cid}")
    for sid, s in scenes.items():
        claim(sid, f"scenes/{sid}")
        for n in s.get("nodes", []):
            claim(n["id"], f"scenes/{sid}#{n['id']}")
            for o in n.get("options", []) + n.get("hotspots", []): claim(o["id"], f"scenes/{sid}#{o['id']}")

    char_keys = {}
    for cid, c in chars.items():
        if c["key"] in char_keys: err("R001", f"characters/{cid}", f"key de personagem duplicada {c['key']}")
        char_keys[c["key"]] = cid

    # --- tabela de variáveis (ID qualificado -> definição) ---
    vars_ = {}
    def define(qid, d, where):
        if qid in vars_: err("R002", where, f"variável duplicada {qid}")
        vars_[qid] = d
    for d in variables.get("global", []): define(f"global.{d['key']}", d, "variables.json")
    for d in variables.get("character", []):
        if d.get("persistence") == "profile": err("R017", "variables.json", f"character.*.{d['key']}: profile só em variáveis globais e de plugin")
        for ck in d.get("characters", list(char_keys)):
            if ck not in char_keys: err("R010", "variables.json", f"personagem {ck} não existe (characters usa a key do personagem)")
            define(f"character.{ck}.{d['key']}", d, "variables.json")
    chapter_vars = {cid: {f"chapter.{d['key']}": d for d in c.get("variables", [])} for cid, c in chapters.items()}
    for cid, c in chapters.items():
        for d in c.get("variables", []):
            if d.get("persistence") == "profile": err("R017", f"chapters/{cid}", f"chapter.{d['key']}: profile só em variáveis globais e de plugin")
    namespaces = {}
    for pid, m in manifests.items():
        if m["namespace"] in namespaces: err("P001", pid, f"namespace {m['namespace']} já usado por {namespaces[m['namespace']]}")
        namespaces[m["namespace"]] = pid
        for d in m.get("variables", []): define(f"plugin.{m['namespace']}.{d['key']}", d, pid)

    def resolve(ref, chapter_id, scene):
        if ref.startswith("sys."):
            if ref in SYS_FIXED: return {"type": SYS_FIXED[ref]}
            parts = ref.split(".")
            if len(parts) == 4 and parts[1] == "scenes" and parts[3] in ("plays", "last_selection"):
                return {"type": "integer"} if parts[2] in scenes else None
            if len(parts) == 4 and parts[1] == "chapters" and parts[3] == "completed":
                return {"type": "boolean"} if parts[2] in chapters else None
            if len(parts) == 3 and parts[1] == "endings":
                return {"type": "boolean"} if parts[2] in endings else None
            return None
        if ref.startswith("chapter."):
            if chapter_id is None: return None
            return chapter_vars.get(chapter_id, {}).get(ref)
        if ref.startswith("scene."):
            return {f"scene.{d['key']}": d for d in (scene or {}).get("variables", [])}.get(ref)
        return vars_.get(ref)

    def literal_type_ok(defn, value):
        t = defn.get("type")
        if t in (None, "any") or isinstance(value, dict): return True
        if isinstance(value, list): return all(literal_type_ok(defn, v) for v in value)
        return {"boolean": isinstance(value, bool),
                "integer": isinstance(value, int) and not isinstance(value, bool),
                "number": isinstance(value, (int, float)) and not isinstance(value, bool),
                "string": isinstance(value, str),
                "enum": isinstance(value, str) and value in defn.get("constraints", {}).get("values", [])}[t]
    def family(t): return "number" if t in ("integer", "number") else ("string" if t in ("string", "enum") else t)

    # defaults e enums
    for qid, d in vars_.items():
        if "default" in d and not literal_type_ok(d, d["default"]): err("T001", qid, f"default {d['default']!r} incompatível com {d['type']}")
    for cid, c in chars.items():
        for k, v in c.get("initial_values", {}).items():
            d = vars_.get(f"character.{c['key']}.{k}")
            if d is None: err("R003", f"characters/{cid}", f"initial_values.{k} não é variável de personagem")
            elif not literal_type_ok(d, v): err("T001", f"characters/{cid}", f"initial_values.{k} tipo incompatível")
        de = c.get("default_expression")
        if de and de not in c.get("expressions", {}): err("R011", f"characters/{cid}", f"default_expression {de} não existe")
        blip = c.get("voice", {}).get("blip")
        if blip and blip not in assets: err("R004", f"characters/{cid}", f"asset {blip} não registrado (voice.blip)")
        for e, a in c.get("expressions", {}).items():
            if a not in assets: err("R004", f"characters/{cid}", f"asset {a} não registrado")
            elif assets[a]["type"] != "sprite": warn("W014", f"characters/{cid}", f"expressão {e} usa asset {a} do tipo {assets[a]['type']} (esperado sprite)")

    activities = {f"{m['namespace']}.{a['id']}": (m, a) for m in manifests.values() for a in m.get("activities", [])}
    used_plugin_ns = {manifests[p]["namespace"] for p in plugins_cfg["plugins"] if p in manifests}

    def infer(e, chapter_id, scene, rschema=None, where=""):
        """Tipo de uma expressão de valor: boolean/integer/number/string/enum, ou None (desconhecido)."""
        if isinstance(e, bool): return "boolean"
        if isinstance(e, int): return "integer"
        if isinstance(e, float): return "number"
        if isinstance(e, str): return "string"
        if not isinstance(e, dict): return None
        if "var" in e:
            d = resolve(e["var"], chapter_id, scene); return d.get("type") if d else None
        if "result" in e:
            node = rschema or {}
            for part in e["result"].split("."):
                node = (node.get("properties") or {}).get(part) if isinstance(node, dict) else None
            t = node.get("type") if isinstance(node, dict) else None
            return t if t in ("boolean", "integer", "number", "string") else None
        if "if" in e:
            a, b = infer(e["then"], chapter_id, scene, rschema, where), infer(e["else"], chapter_id, scene, rschema, where)
            if a == b: return a
            return "number" if {a, b} == {"integer", "number"} else None
        if "fn" in e:
            fn, args = e["fn"], e.get("args", [])
            lo, hi, kind = FN_ARITY[fn]
            ts = [infer(a, chapter_id, scene, rschema, where) for a in args]
            if not lo <= len(args) <= hi: err("T007", where, f"{fn} recebe de {lo} a {hi} argumentos, não {len(args)}")
            for t in ts:
                if t is None: continue
                if kind == "num" and t not in ("integer", "number"): err("T007", where, f"{fn} exige números, recebeu {t}")
                if kind == "int" and t != "integer": err("T007", where, f"{fn} exige inteiros, recebeu {t}")
            if fn == "concat": return "string"
            if fn in ("div",): return "number"
            if fn in ("round", "floor", "ceil", "mod", "random_int"): return "integer"
            if fn == "abs": return ts[0] if ts else None
            if any(t is None for t in ts): return None
            return "integer" if all(t == "integer" for t in ts) else "number"
        return None

    def check_value_type(target, op, value, where, chapter_id, scene, rschema=None):
        d = resolve(target, chapter_id, scene)
        if d is None: return
        t = infer(value, chapter_id, scene, rschema, where)
        if t is None or isinstance(value, (bool, int, float, str)) and op == "set": return  # literais: T001 já cobre
        dt = d.get("type")
        if op in ("add", "subtract", "multiply"):
            if t not in ("integer", "number"): err("T006", where, f"{op} em {target} com valor do tipo {t}")
            elif dt == "integer" and t == "number": warn("W017", where, f"resultado number gravado em {target} (integer) será truncado")
        elif op == "set":
            if family(t) != family(dt): err("T006", where, f"{target} ({dt}) recebe valor do tipo {t}")
            elif dt == "integer" and t == "number": warn("W017", where, f"resultado number gravado em {target} (integer) será truncado")

    def schema_has_path(schema, path):
        node = schema
        for part in path.split("."):
            node = (node.get("properties") or {}).get(part) if isinstance(node, dict) else None
            if node is None: return False
        return True

    def check_text(text, where, chapter_id, scene):
        for ref in interp_refs(text):
            if resolve(ref, chapter_id, scene) is None: err("R019", where, f"interpolação {{{ref}}}: variável inexistente ou fora de escopo")

    def check_refs(obj, where, chapter_id, scene, result_fields=None):
        """result_fields: None = {result} proibido aqui (T005); dict = result_schema da atividade; True = qualquer campo."""
        def visit(o):
            if "result" in o and len(o) <= 2 and isinstance(o.get("result"), str) and ("default" in o or len(o) == 1):
                if result_fields is None: err("T005", where, f"{{\"result\": \"{o['result']}\"}} só vale em on_result.effects")
                elif result_fields is not True and not schema_has_path(result_fields, o["result"]):
                    err("T005", where, f"campo {o['result']} não está no result_schema da atividade")
            if "variable" in o and isinstance(o["variable"], str):
                d = resolve(o["variable"], chapter_id, scene)
                if d is None: err("R005", where, f"variável inexistente ou fora de escopo: {o['variable']}")
                else:
                    if "op" in o and d.get("derived") is not None: err("T002", where, f"{o['variable']} é derivada (somente leitura)")
                    if "op" in o and o["variable"].startswith("plugin."): err("T002", where, f"{o['variable']} é de plugin (somente leitura para o projeto)")
                    if "operator" in o and "value" in o:
                        if isinstance(o["value"], dict) and isinstance(o["value"].get("var"), str):
                            d2 = resolve(o["value"]["var"], chapter_id, scene)
                            if d2 and family(d2.get("type")) != family(d.get("type")) and "any" not in (d.get("type"), d2.get("type")):
                                err("T001", where, f"{o['variable']} ({d.get('type')}) comparada com {o['value']['var']} ({d2.get('type')})")
                        elif not literal_type_ok(d, o["value"]):
                            err("T001", where, f"{o['variable']} {o['operator']} {o['value']!r}: tipo incompatível")
                    if o.get("op") in ("add", "subtract", "multiply") and d.get("type") not in ("integer", "number"):
                        err("T003", where, f"{o['op']} exige variável numérica ({o['variable']})")
                    if o.get("op") == "toggle" and d.get("type") != "boolean":
                        err("T003", where, f"toggle exige booleana ({o['variable']})")
                    if o.get("op") == "set" and "value" in o and not literal_type_ok(d, o["value"]):
                        err("T001", where, f"set {o['variable']} = {o['value']!r}: tipo incompatível")
            if "var" in o and isinstance(o["var"], str) and resolve(o["var"], chapter_id, scene) is None:
                err("R005", where, f"variável inexistente ou fora de escopo: {o['var']}")
            ev = o.get("event_since_last_selection")
            if isinstance(ev, str) and ev.startswith("story.") and ev not in story_events:
                warn("W015", where, f"evento {ev} não declarado em project.json → events")
            if isinstance(ev, str) and ev.startswith("sys."):
                warn("W019", where, f"{ev}: eventos sys.* não são registrados; a condição é sempre falsa")
            if "op" in o and isinstance(o.get("variable"), str) and "value" in o and result_fields is None:
                check_value_type(o["variable"], o["op"], o["value"], where, chapter_id, scene)  # on_result: ver nó plugin
        walk(obj, visit)

    # --- variáveis derivadas: referências (R005) e ciclos (T004) ---
    derived = {q: d for q, d in vars_.items() if d.get("derived") is not None}
    for q, d in derived.items():
        check_refs(d["derived"], f"variables/{q}", None, None)
        t = infer(d["derived"], None, None, None, f"variables/{q}")
        if t is not None and family(t) != family(d.get("type")): err("T006", f"variables/{q}", f"derivada declarada {d.get('type')} mas calcula {t}")
        rnd = []
        walk(d["derived"], lambda o: rnd.append(1) if o.get("fn") == "random_int" else None)
        if rnd: err("T008", f"variables/{q}", "random_int numa variável derivada (recalculada a cada leitura)")
    def dfs(q, path):
        for r in read_vars(derived[q]["derived"]):
            if r in path: err("T004", f"variables/{q}", f"ciclo entre derivadas: {' → '.join(path + [r])}"); return True
            if r in derived and dfs(r, path + [r]): return True
        return False
    for q in derived: dfs(q, [q])

    # --- grupos (R015) ---
    groups = {g["id"] for g in project.get("exclusive_groups", [])}
    for cid, c in chapters.items():
        for g in c.get("exclusive_groups", []):
            if g["id"] in groups: err("R015", f"chapters/{cid}", f"grupo {g['id']} também existe em project.json")

    def check_vn_formats(schema, data, where):
        for prop, ps in (schema.get("properties") or {}).items():
            if prop not in (data or {}): continue
            v, fmt = data[prop], ps.get("format")
            vals = v if isinstance(v, list) else [v]
            for x in vals:
                if not isinstance(x, str): continue
                if fmt == "vn-asset":
                    if x not in assets: err("P018", where, f"{prop}: asset {x} não existe")
                    elif ps.get("vn-asset-type") and assets[x]["type"] != ps["vn-asset-type"]: warn("W014", where, f"{prop}: {x} é {assets[x]['type']}, esperado {ps['vn-asset-type']}")
                elif fmt == "vn-scene" and x not in scenes: err("P018", where, f"{prop}: cena {x} não existe")
                elif fmt == "vn-character" and x not in chars: err("P018", where, f"{prop}: personagem {x} não existe")
                elif fmt == "vn-variable" and resolve(x, None, None) is None: err("R005", where, f"{prop}: variável {x} não existe")

    def same_chapter(target, chapter_id):
        return target in scenes and scenes[target].get("chapter") in (chapter_id, None) if chapter_id is not None else \
            (target in scenes and scenes[target].get("chapter") is None)

    for cid, c in chapters.items():
        check_refs(c.get("completion", {}), f"chapters/{cid}", cid, None)
        for n in c.get("next", []):
            check_refs(n.get("conditions", []), f"chapters/{cid}/next", cid, None)  # chapter.* ainda vale (RT §3.3)
            if n["chapter"] not in chapters: err("R007", f"chapters/{cid}", f"capítulo {n['chapter']} não existe")
        for k, target in (("entry_scene", c.get("entry_scene")), ("fallback_scene", c.get("completion", {}).get("fallback_scene"))):
            if target is None: continue
            if target not in scenes: err("R006", f"chapters/{cid}", f"{k} {target} não existe")
            elif not same_chapter(target, cid): err("R014", f"chapters/{cid}", f"{k} é de outro capítulo")
        fb = c.get("completion", {}).get("fallback_scene")
        conds = c.get("completion", {}).get("conditions")
        if fb in scenes and conds:
            if not (written_vars(scenes[fb]) & read_vars(conds)):
                warn("W010", f"chapters/{cid}", "fallback_scene não altera nenhuma variável de completion.conditions")
    if project["start_chapter"] not in chapters: err("R007", "project.json", "start_chapter não existe")
    if "chapters" in project:
        for cid in project["chapters"]:
            if cid not in chapters: err("R007", "project.json/chapters", f"capítulo {cid} não existe")
        for cid in chapters:
            if cid not in project["chapters"]: warn("W018", f"chapters/{cid}", "capítulo fora de project.chapters")
    if EXPORT and not project.get("version"): err("R021", "project.json", "version é obrigatória na exportação")
    for ch in chars.values():
        for k in ("name", "display_name"):
            check_text(ch.get(k), f"characters/{ch['id']}/{k}", None, None)
    for e in project.get("endings", []):
        for k in ("title", "description"): check_text(e.get(k), f"project.json/endings/{e['id']}/{k}", None, None)

    def set_parts(set_id):
        """(camadas → estados, ids de hotspots) de um set."""
        st = sets.get(set_id, {})
        return ({l["id"]: {"default"} | set(l.get("states", {})) for l in st.get("layers", [])},
                {h["id"] for h in st.get("hotspots", [])})
    def scene_sets(scene):
        return [n["set"] for n in scene.get("nodes", []) if n.get("type") == "background" and n.get("set")]
    styles = theme.get("styles", {})
    def check_style(name, where):
        if name not in styles and name not in DEFAULT_STYLES: err("U002", where, f"estilo {name} não existe no tema")
    for name, st in styles.items():
        seen_st, cur = [name], st
        while cur.get("extends"):
            check_style(cur["extends"], f"{theme_file.name}/styles/{name}")
            if cur["extends"] in seen_st: err("U002", f"{theme_file.name}/styles/{name}", f"ciclo em extends: {' → '.join(seen_st + [cur['extends']])}"); break
            seen_st.append(cur["extends"]); cur = styles.get(cur["extends"], {})
    for k, v in (("choices.style", theme.get("choices", {}).get("style")), ("dialog.button_style", theme.get("dialog", {}).get("button_style"))):
        if v: check_style(v, f"{theme_file.name}/{k}")

    text_paths = set()
    for sid, s in scenes.items():
        where = str(scene_paths[sid].relative_to(root))
        cid = s.get("chapter")
        if cid is not None and cid not in chapters: err("R007", where, f"capítulo {cid} não existe")
        cgroups = groups | {g["id"] for g in chapters.get(cid, {}).get("exclusive_groups", [])}
        for g in s.get("scheduling", {}).get("exclusive_groups", []):
            if g not in cgroups: err("R008", where, f"grupo de exclusividade {g} não definido")
        check_refs(s.get("scheduling", {}), where, cid, None)  # scene.* não existe antes da cena começar
        for d in s.get("variables", []):
            if "default" in d and not literal_type_ok(d, d["default"]): err("T001", where, f"default de scene.{d['key']}")
            if d.get("persistence") == "profile": err("R017", where, f"scene.{d['key']}: profile só em variáveis globais e de plugin")
        nodes = s["nodes"]; ids = [n["id"] for n in nodes]
        idx = {n["id"]: i for i, n in enumerate(nodes)}
        def following(i): return ids[i + 1] if i + 1 < len(ids) else None
        def succ(i):
            n = nodes[i]; t = n["type"]; nxt = n.get("next") or following(i)
            if t == "choice": out = [o.get("goto") or nxt for o in n["options"]] + [nxt]  # sem opção visível: next (A4)
            elif t == "interact": out = [h.get("goto") or nxt for h in n["hotspots"]] + [n.get("exit", {}).get("goto") or nxt, nxt]
            elif t == "jump": out = [n["goto"]]
            elif t == "end": out = []
            elif t == "branch": out = [c["goto"] for c in n["cases"]] + [n.get("else") or nxt]
            elif t == "plugin": out = list(n.get("on_result", {}).get("outcomes", {}).values()) + [n.get("on_error"), nxt]
            elif t == "effects": out = [n.get("on_fail"), nxt]
            else: out = [nxt]
            return [x for x in out if x is not None]
        for i, n in enumerate(nodes):
            nw = f"{where}#{n['id']}"
            for t in succ(i):
                if t not in idx: err("R009", nw, f"destino {t} não existe")
            rf = None
            if n["type"] == "plugin":
                act = activities.get(n["activity"])
                props = (act[1].get("result_schema") or {}).get("properties") if act else None
                rf = act[1]["result_schema"] if props is not None else True
                check_refs({k: v for k, v in n.items() if k != "on_result"}, nw, cid, s)
                rs = act[1].get("result_schema") if act else None
                for eff in n.get("on_result", {}).get("effects", []):
                    if "value" in eff: check_value_type(eff["variable"], eff["op"], eff["value"], nw, cid, s, rs)
                check_refs(n.get("on_result", {}), nw, cid, s, result_fields=rf)
            else:
                check_refs(n, nw, cid, s)
            if n.get("unresolved"):
                (err if EXPORT else warn)("W013", nw, f"passo incompleto: {n['unresolved'].get('reason')}")
            if n.get("speaker") and n["speaker"] not in chars: err("R010", nw, f"personagem {n['speaker']} não existe")
            if n["type"] in ("show", "hide") and n["character"] != "*" and n["character"] not in chars: err("R010", nw, f"personagem {n['character']} não existe")
            if n.get("expression"):
                c = chars.get(n.get("speaker") or n.get("character"), {})
                if c and n["expression"] not in c.get("expressions", {}): err("R011", nw, f"expressão {n['expression']} não existe")
            for key in ("asset", "voice"):
                a = n.get(key)
                if a is None: continue
                if a not in assets: err("R004", nw, f"asset {a} não registrado"); continue
                ok = {"background": IMG, "audio": AUDIO_TYPES.get(n.get("channel"), set())}.get(n["type"], {"audio_voice"} if key == "voice" else None)
                if ok and assets[a]["type"] not in ok: warn("W014", nw, f"asset {a} é {assets[a]['type']}, não {'/'.join(sorted(ok))}")
            if n["type"] == "end":
                then = n.get("then", "schedule")
                if n.get("ending") and n["ending"] not in endings: err("R012", nw, f"final {n['ending']} não declarado em project.json → endings")
                if n.get("ending") and then != "end_game": warn("W011", nw, "ending só tem efeito com then: end_game")
                if isinstance(then, dict):
                    if then["scene"] not in scenes: err("R006", nw, f"cena {then['scene']} não existe")
                    elif not same_chapter(then["scene"], cid): err("R014", nw, "then.scene aponta para cena de outro capítulo")
            if n["type"] == "emit" and not n["event"].startswith("story."):
                err("R020", nw, f"emit de {n['event']}: cenas só emitem eventos story.*")
            if n["type"] == "emit" and n["event"].startswith("story.") and n["event"] not in story_events:
                warn("W015", nw, f"evento {n['event']} não declarado em project.json → events")
            if n["type"] in ("line", "choice"):
                text_paths.add(f"{sid}/{n['id']}")
                for t in ([n.get("text")] if n["type"] == "line" else [n.get("prompt")] + [o["text"] for o in n["options"]]):
                    if t: check_markup(t, nw); check_text(t, nw, cid, s)
            if n["type"] == "interact":
                if n.get("prompt"): text_paths.add(f"{sid}/{n['id']}")
                texts = [n.get("prompt"), n.get("exit", {}).get("label")] + [h.get("label") for h in n["hotspots"]]
                if "exit" in n: text_paths.add(f"{sid}/{n['id']}/exit")
                for h in n["hotspots"]:
                    if h.get("label"): text_paths.add(f"{sid}/{n['id']}/{h['id']}")
                    else: warn("U008", nw, f"hotspot {h['id']} sem label (sem nome para teclado e acessibilidade)")
                    a = h["area"]
                    if "character" in a and a["character"] not in chars: err("R010", nw, f"personagem {a['character']} não existe")
                    if "layer" in a and not any(a["layer"] in set_parts(x)[0] for x in scene_sets(s)):
                        err("U001", nw, f"camada {a['layer']} não existe em nenhum set mostrado pela cena")
                for t in texts:
                    if t: check_markup(t, nw); check_text(t, nw, cid, s)
                if all("visible_if" in h for h in n["hotspots"]) and "exit" not in n:
                    warn("W006", nw, "o interact pode ficar sem hotspots visíveis")
                if n.get("exit", {}).get("style"): check_style(n["exit"]["style"], nw)
                if "record" in n:
                    d = resolve(n["record"], cid, s)
                    if d is not None and d.get("type") not in ("string", "enum"):
                        err("R016", nw, f"record exige variável string/enum ({n['record']} é {d.get('type')})")
                    elif d is not None and d.get("type") == "enum":
                        vals = d.get("constraints", {}).get("values", [])
                        for h in n["hotspots"]:
                            if h.get("value", h["id"]) not in vals: err("R016", nw, f"valor {h.get('value', h['id'])} do hotspot não está no enum de {n['record']}")
            if n["type"] == "background" and n.get("set") and n["set"] not in sets:
                err("U001", nw, f"set {n['set']} não existe em sets/")
            if n["type"] == "audio" and n.get("caption"):
                text_paths.add(f"{sid}/{n['id']}"); check_text(n["caption"], nw, cid, s)
            if n["type"] == "choice":
                for o in n["options"]: text_paths.add(f"{sid}/{n['id']}/{o['id']}")
                if all("visible_if" in o for o in n["options"]): warn("W006", nw, "a escolha pode ficar sem opções visíveis")
                if "record" in n:
                    d = resolve(n["record"], cid, s)
                    if d is not None and d.get("type") not in ("string", "enum"):
                        err("R016", nw, f"record exige variável string/enum ({n['record']} é {d.get('type')})")
                    elif d is not None and d.get("type") == "enum":
                        vals = d.get("constraints", {}).get("values", [])
                        for o in n["options"]:
                            if o.get("value", o["id"]) not in vals: err("R016", nw, f"valor {o.get('value', o['id'])} da opção não está no enum de {n['record']}")
            if n["type"] == "plugin":
                act = activities.get(n["activity"])
                if act is None: err("P002", nw, f"atividade {n['activity']} não declarada por nenhum plugin")
                else:
                    m, a = act
                    if m["namespace"] not in used_plugin_ns: err("P003", nw, f"plugin {m['id']} não está em plugins.json")
                    for e in Draft202012Validator(a.get("params_schema", {})).iter_errors(n.get("params", {})):
                        err("P004", nw, f"params: {e.message}")
                    check_vn_formats(a.get("params_schema", {}), n.get("params", {}), nw)
                    for oc in n.get("on_result", {}).get("outcomes", {}):
                        if oc not in a["outcomes"]: err("P005", nw, f"outcome {oc} não declarado")
                    missing = set(a["outcomes"]) - set(n.get("on_result", {}).get("outcomes", {}))
                    if missing: warn("W002", nw, f"outcomes sem destino (seguem 'next'): {sorted(missing)}")
        start = s.get("start", ids[0])
        if start not in idx: err("R009", where, f"start {start} não existe"); continue
        seen, stack = set(), [idx[start]]
        while stack:
            i = stack.pop()
            if i in seen: continue
            seen.add(i); stack += [idx[t] for t in succ(i) if t in idx]
        for i, n in enumerate(nodes):
            if i not in seen: warn("W001", f"{where}#{n['id']}", "nó inalcançável")

    check_ui(root, project, theme, theme_file, screens, sets, assets, resolve, check_style, set_parts, text_paths, vars_, endings, activities, manifests)
    for p in sorted((root / "locales").rglob("*.json")):
        for k, v in load(p)["strings"].items():
            if k.count("/") >= 1 and (k.split("/")[0] in scenes or k.split("/")[0] in ("ui", "sets")) and k not in text_paths:
                warn("W003", p.relative_to(root), f"tradução órfã {k}")
            t = v if isinstance(v, str) else v.get("text", "")
            check_markup(t, f"{p.relative_to(root)}/{k}")
            sc = scenes.get(k.split("/")[0])
            check_text(t, f"{p.relative_to(root)}/{k}", sc.get("chapter") if sc else None, sc)

    # assets referenciados por tema, finais e build (R004, W014)
    def asset_refs(o, where, ctx=None):
        """ctx: tipos aceitos para toda string da subárvore (sounds, fonts, image de estilo)."""
        if isinstance(o, dict):
            for k, v in o.items():
                if k in ("$schema", "id", "description") or k.startswith("_"): continue
                sub = ctx or ASSET_CTX.get(k) or (IMG if k == "image" and isinstance(v, dict) else None)
                if k == "asset" and o.get("do") == "play_sfx": sub = {"audio_sfx"}
                if isinstance(v, str):
                    ok = sub if sub else ASSET_KEYS.get(k)
                    if ok is None or v.startswith("#") or (k == "cursor" and v in CURSORS): continue
                    if v not in assets: err("R004", where, f"asset {v} não registrado ({k})")
                    elif assets[v]["type"] not in ok | {"other"}: warn("W014", where, f"{k} usa {v} do tipo {assets[v]['type']}")
                elif k not in ("if", "visible_if", "enabled_if", "effects", "payload", "value", "options", "text", "label", "tooltip"):
                    asset_refs(v, where, sub)
        elif isinstance(o, list):
            for v in o: asset_refs(v, where, ctx)
    asset_refs(theme, theme_file.name)
    for sid_, sc in screens.items(): asset_refs(sc, f"ui/{sid_}.json")
    for sid_, st in sets.items(): asset_refs(st, f"sets/{sid_}.json")
    asset_refs(project.get("endings", []), "project.json/endings")
    asset_refs(project.get("build", {}), "project.json/build")

    # textos de plugin exibidos no Studio (W007), outcome_labels (P010), capacidades (W012, P016)
    for pid, m in manifests.items():
        for a in m.get("activities", []):
            for prop, ps in a.get("params_schema", {}).get("properties", {}).items():
                if "title" not in ps: warn("W007", f"{pid}/{a['id']}", f"parâmetro {prop} sem 'title'; o Studio mostrará o nome técnico")
            for oc in a.get("outcome_labels", {}):
                if oc not in a["outcomes"]: err("P010", f"{pid}/{a['id']}", f"outcome_labels.{oc} não está em outcomes")
            for oc in a["outcomes"]:
                if oc not in a.get("outcome_labels", {}): warn("W007", f"{pid}/{a['id']}", f"outcome {oc} sem rótulo em outcome_labels")
            if a.get("default_outcome") and a["default_outcome"] not in a["outcomes"]:
                err("P005", f"{pid}/{a['id']}", f"default_outcome {a['default_outcome']} não está em outcomes")
        ns = m["namespace"]; deps = set(m.get("dependencies", {})) | set(m.get("optional_dependencies", {}))
        dep_ns = {manifests[x]["namespace"] for x in deps if x in manifests} | {x.split(".", 1)[1] for x in deps if x not in manifests}
        for d in m.get("variables", []):
            for bad in ("access", "characters"):
                if bad in d: err("P017", f"{pid}/variables", f"plugin.{ns}.{d['key']}: '{bad}' não vale em variável de plugin")
            if d.get("derived") is not None:
                for r in read_vars(d["derived"]):
                    if not r.startswith(f"plugin.{ns}."): err("P017", f"{pid}/variables", f"derivada plugin.{ns}.{d['key']} lê {r}, fora do próprio namespace")
        for mode in ("read", "write"):
            for pat in m.get("variable_permissions", {}).get(mode, []):
                if pat.startswith("plugin."):
                    other = pat.split(".")[1]
                    if other == ns: continue
                    if mode == "write": err("P017", pid, f"{pat}: variáveis de outro plugin nunca são graváveis")
                    elif other not in dep_ns: err("P017", pid, f"{pat}: leitura de outro plugin exige dependência declarada")
        for d in m.get("variables", []):
            if "name" not in d: warn("W007", f"{pid}/variables", f"variável plugin.{m['namespace']}.{d['key']} sem 'name'; o Studio mostrará o nome técnico")
        caps = m.get("capabilities", {})
        if (m.get("records") or m.get("profile")) and "profile.data" not in caps.get("runtime", []):
            err("P019", pid, "records/profile exigem a capacidade profile.data")
        for a in m.get("activities", []):
            if "free_play" in a:
                for e in Draft202012Validator(a.get("params_schema", {})).iter_errors(a["free_play"].get("params", {})):
                    err("P004", f"{pid}/{a['id']}", f"free_play.params: {e.message}")
        if m.get("events", {}).get("subscribes") and "events.subscribe" not in caps.get("runtime", []):
            warn("W012", pid, "events.subscribes sem a capacidade events.subscribe")
        if "network" in caps.get("editor", []) and not pid.startswith("vnstudio."):
            err("P016", pid, "a capacidade network é só para plugins oficiais no v1")
        plats = m.get("compatibility", {}).get("platforms")
        if plats is not None:
            for pl in project.get("build", {}).get("platforms", []):
                if pl not in plats: warn("W008", pid, f"projeto exporta para {pl}, fora de compatibility.platforms")
        check_plugin_code(pid, m, plugin_roots[pid])

    # idiomas do build (R013, Build System §5.3)
    bl = project.get("build", {}).get("locales")
    if bl is not None:
        if project["default_locale"] not in bl: err("R013", "project.json/build", f"build.locales não contém {project['default_locale']}")
        for l in bl:
            if l not in project.get("locales", []): err("R013", "project.json/build", f"idioma {l} fora de locales")

    # vínculos de desenvolvimento (P013, só na exportação)
    for pid, e in list(lock.get("plugins", {}).items()) + list(local_lock.get("plugins", {}).items()):
        if e.get("link"):
            (err if EXPORT else warn)("P013", "plugin-lock", f"{pid} está vinculado a uma pasta de desenvolvimento")

    # coerência do lock (P015)
    for pid, cfg in plugins_cfg["plugins"].items():
        e = lock.get("plugins", {}).get(pid)
        if e is None: err("P015", "plugin-lock.json", f"{pid} está em plugins.json mas não no lock"); continue
        if not satisfies(e["version"], cfg["version"]): err("P015", "plugin-lock.json", f"{pid} {e['version']} fora da faixa {cfg['version']}")
        if pid in manifests and manifests[pid]["namespace"] != e["namespace"]: err("P015", "plugin-lock.json", f"{pid}: namespace {e['namespace']} ≠ {manifests[pid]['namespace']} do manifesto")
        if pid in manifests and manifests[pid]["version"] != e["version"]: err("P015", "plugin-lock.json", f"{pid}: lock fixa {e['version']}, manifesto é {manifests[pid]['version']}")

    # permissões: concessão ⊆ pedido; variáveis concedidas devem aceitar plugins
    for pid, cfg in plugins_cfg["plugins"].items():
        m = manifests.get(pid)
        if m is None: warn("W004", "plugins.json", f"manifesto de {pid} não fornecido; permissões não verificadas"); continue
        req_caps = {f"runtime:{c}" for c in m.get("capabilities", {}).get("runtime", [])} | {f"editor:{c}" for c in m.get("capabilities", {}).get("editor", [])}
        for c in cfg.get("grants", {}).get("capabilities", []):
            if c not in req_caps: err("P006", f"plugins.json/{pid}", f"capacidade {c} concedida mas não pedida")
        for mode in ("read", "write"):
            asked = [cfg.get("config", {}).get(pat[8:], "") if pat.startswith("$config.") else pat
                     for pat in m.get("variable_permissions", {}).get(mode, [])]
            for v in cfg.get("grants", {}).get("variables", {}).get(mode, []):
                if not any(fnmatch.fnmatchcase(v, pat) for pat in asked): err("P007", f"plugins.json/{pid}", f"{mode} {v} concedido mas não pedido")
                d = vars_.get(v)
                if d is None: err("R005", f"plugins.json/{pid}", f"variável {v} não existe")
                elif mode == "write" and d.get("access", {}).get("plugins_write", "none") == "none": err("P008", f"plugins.json/{pid}", f"{v} não aceita escrita de plugins")
                elif mode == "read" and d.get("access", {}).get("plugins_read", "none") == "none": err("P014", f"plugins.json/{pid}", f"{v} não aceita leitura de plugins")
        for sc in cfg.get("grants", {}).get("scenes", []):
            if sc not in scenes: err("R006", f"plugins.json/{pid}", f"cena {sc} não existe")
        conf_schema = m.get("config_schema")
        if conf_schema:
            for e in Draft202012Validator(conf_schema).iter_errors(cfg.get("config", {})): err("P004", f"plugins.json/{pid}", f"config: {e.message}")
            check_vn_formats(conf_schema, cfg.get("config", {}), f"plugins.json/{pid}/config")
        for ev in m.get("events", {}).get("emits", []):
            if not ev["name"].startswith(m["namespace"] + "."): err("P009", pid, f"evento {ev['name']} fora do namespace")

def run(root, plugin_dirs=(), export=False):
    """Roda o validador e devolve (erros, avisos). Usado por test_validate.py."""
    global EXPORT
    errors.clear(); warnings.clear(); EXPORT = export
    main(root, list(plugin_dirs))
    return list(errors), list(warnings)

if __name__ == "__main__":
    args = sys.argv[1:]
    export = "--export" in args
    if export: args.remove("--export")
    errs, warns = run(args[0], args[1:], export)
    for w in warns: print("AVISO", w)
    for e in errs: print("ERRO ", e)
    print(f"\n{len(errs)} erro(s), {len(warns)} aviso(s).")
    sys.exit(1 if errs else 0)
