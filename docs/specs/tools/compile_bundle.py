#!/usr/bin/env python3
"""Compilador de bundle de referência (Build System §5.1, bundle.schema.json).

Uso: python3 compile_bundle.py <pasta-do-projeto> <saída> [<pasta-de-plugin>...] [--stage] [--edition standard|censored]
     python3 compile_bundle.py <pasta-do-projeto> --godot <projeto-godot> [<pasta-de-plugin>...]

Valida o projeto (tools/validate.py, zero erros), resolve os padrões, aplica o
preset do tema e grava a forma canônica que o runtime lê:

  <saída>/bundle.json
  <saída>/locales/<lang>.json   (um por idioma do jogo)
  <saída>/plugins.json

Com --stage, também copia os assets para <saída>/assets/ e cada plugin para
<saída>/vn_plugins/<namespace>/.

Com --edition censored (ou project.json → build.edition), gera a edição
censurada do modo stream (Build System §5.4): o filtro fica sempre ligado, os
textos censurados substituem os originais, os passos censor: skip viram desvios
e os assets originais com versão censurada não entram no staging.

Com --godot <projeto-godot>, grava o bundle e os assets em
<projeto-godot>/vn_content/ e cada plugin em <projeto-godot>/vn_plugins/<namespace>/,
os mesmos caminhos res:// do jogo exportado. O editor do Godot importa os assets
e o runtime roda a demo sem o Studio (Runtime Spec §2.1).

É a primeira peça do Build System e a referência para o compilador do Studio:
para o mesmo projeto, os dois DEVEM gerar os mesmos bytes (JCS) e o mesmo
content_hash.
"""
import base64, copy, hashlib, json, shutil, sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import validate                                              # noqa: E402
from conformance import jcs                                   # noqa: E402

PRESETS = TOOLS.parent / "presets"
PRODUCT_LOCALES = ["en", "pt-BR", "es", "fr", "it", "de", "ja", "zh-Hans", "zh-Hant"]   # Req §9.1
PRESET_ASSETS = {                                            # ids reservados, fornecidos pelo runtime
    "preset/font_body": ("font", "res://vn_runtime/presets/fonts/NotoSans-Regular.ttf"),
    "preset/font_ja": ("font", "res://vn_runtime/presets/fonts/NotoSansJP-Regular.ttf"),
    "preset/font_zh_hans": ("font", "res://vn_runtime/presets/fonts/NotoSansSC-Regular.ttf"),
    "preset/font_zh_hant": ("font", "res://vn_runtime/presets/fonts/NotoSansTC-Regular.ttf"),
    "preset/font_ko": ("font", "res://vn_runtime/presets/fonts/NotoSansKR-Regular.ttf"),
}


# JCS (RFC 8785): implementação única em conformance.py, conferida pelos vetores canonical.json


def sri(data: bytes): return "sha256-" + base64.b64encode(hashlib.sha256(data).digest()).decode()


def load(p): return json.loads(Path(p).read_text(encoding="utf-8"))


def strip(d):
    d = dict(d); d.pop("$schema", None); return d


def deep_merge(base, over):
    """Tema do projeto sobre o do preset: objetos fundem, listas e valores substituem."""
    out = copy.deepcopy(base)
    for k, v in over.items():
        out[k] = deep_merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else copy.deepcopy(v)
    return out


# ------------------------------------------------------------------ compilação

def compile_project(root, plugin_dirs=(), edition=None):
    root = Path(root)
    errs, _ = validate.run(root, plugin_dirs)
    if errs:
        raise SystemExit("O projeto tem erros de validação; corrija antes de compilar:\n  " + "\n  ".join(errs))

    project = load(root / "project.json")
    variables = load(root / "variables.json")
    assets = load(root / "assets.json")["assets"]
    chars = {c["id"]: strip(c) for c in (load(p) for p in sorted((root / "characters").glob("*.json")))}
    chapters_src = {c["id"]: c for c in (load(p) for p in sorted((root / "chapters").glob("*.json")))}
    scenes_src = {s["id"]: s for s in (load(p) for p in sorted((root / "scenes").rglob("*.json")))}
    screens = {p.stem: strip(load(p)) for p in sorted((root / "ui").glob("*.json"))} if (root / "ui").is_dir() else {}
    sets = {p.stem: strip(load(p)) for p in sorted((root / "sets").glob("*.json"))} if (root / "sets").is_dir() else {}
    theme_file = root / project.get("theme", "theme.json")
    theme = strip(load(theme_file)) if theme_file.exists() else {}
    plugins_cfg = load(root / "plugins.json")["plugins"] if (root / "plugins.json").exists() else {}
    lock = load(root / "plugin-lock.json")["plugins"] if (root / "plugin-lock.json").exists() else {}

    # manifestos: os passados na linha de comando e os embutidos (spec 09 §3.2)
    manifests, plugin_roots = {}, {}
    dirs = [Path(d) for d in plugin_dirs]
    for pid, cfg in plugins_cfg.items():
        if cfg["source"].startswith("path:") and not cfg["source"].endswith(".vnplugin"):
            dirs += [p.parent for p in (root / cfg["source"][5:]).glob("vn_plugins/*/plugin.json")]
    for d in dirs:
        m = load(d / "plugin.json"); manifests[m["id"]] = m; plugin_roots[m["id"]] = d

    # --- projeto e padrões (Data Model e schemas: os default declarados)
    st = project.get("settings", {})
    disp = st.get("display", {})
    base = st.get("resolution", [1920, 1080])
    settings = {
        "resolution": base, "text_speed": st.get("text_speed", 40), "auto_delay": st.get("auto_delay", 1.5),
        "autosave": st.get("autosave", "selection_point"), "reproducible_rng": st.get("reproducible_rng", False),
        "display": {
            "resolutions": disp.get("resolutions") or [r for r in ([1280, 720], [1600, 900], [1920, 1080], [2560, 1440])
                                                       if r[0] * base[1] == r[1] * base[0]] or [base],
            "display_mode": disp.get("display_mode", "windowed"), "vsync": disp.get("vsync", True),
            "fps_limit_vn": disp.get("fps_limit_vn", 60), "fps_limit_activity": disp.get("fps_limit_activity", 0)},
        "number_formats": st.get("number_formats", {}),
    }
    if "activity_timeout_seconds" in st: settings["activity_timeout_seconds"] = st["activity_timeout_seconds"]
    proj_sched = {"tie_breaker": "deterministic", "include_global_scenes": True, **project.get("scheduler", {})}
    locales = project.get("locales") or [project["default_locale"]]
    if project["default_locale"] not in locales: locales = [project["default_locale"]] + locales
    proj = {k: v for k, v in strip(project).items() if k not in ("theme", "build")}
    proj.update({"settings": settings, "scheduler": proj_sched, "locales": locales,
                 "chapters": project.get("chapters") or sorted(chapters_src),
                 "exclusive_groups": [{"max_plays": 1, **g} for g in project.get("exclusive_groups", [])],
                 "endings": project.get("endings", []), "events": project.get("events", [])})
    # modo stream (Data Model §10.4, Build System §5.4): edição da linha de comando > project.json → build.edition
    edition = edition or project.get("build", {}).get("edition", "standard")
    censored_ed = edition == "censored"
    proj["content_filter"] = {"default": True if censored_ed else project.get("content_filter", {}).get("default", False),
                              "ask_on_first_launch": False if censored_ed else project.get("content_filter", {}).get("ask_on_first_launch", False),
                              **({"placeholder": project["content_filter"]["placeholder"]} if project.get("content_filter", {}).get("placeholder") else {}),
                              "edition": edition}

    # --- variáveis de escopo de jogo
    def var(d, **extra):
        out = {k: v for k, v in d.items() if k not in ("characters",)}
        if "derived" not in out: out.setdefault("persistence", "save")
        out.update(extra); return out
    char_keys = {c["key"]: c for c in chars.values()}
    bvars, aliases = {}, {}
    for d in variables.get("global", []):
        bvars[f"global.{d['key']}"] = var(d)
    for d in variables.get("character", []):
        for ck in d.get("characters", sorted(char_keys)):
            init = char_keys[ck].get("initial_values", {})
            bvars[f"character.{ck}.{d['key']}"] = var(d, **({"default": init[d["key"]]} if d["key"] in init else {}))
    for pid, m in manifests.items():
        if pid not in plugins_cfg or not plugins_cfg[pid].get("enabled", True): continue
        for d in m.get("variables", []): bvars[f"plugin.{m['namespace']}.{d['key']}"] = var(d)
    for qid, d in bvars.items():
        scope = qid.rsplit(".", 1)[0]
        for old in d.get("renamed_from", []): aliases[old if "." in old else f"{scope}.{old}"] = qid

    # --- capítulos e cenas
    chapters = {}
    for cid, c in chapters_src.items():
        c = strip(c)
        c["scheduler"] = {**proj_sched, **c.get("scheduler", {})}
        c["completion"] = {"on_exhausted": "advance", **c.get("completion", {})}
        c["exclusive_groups"] = [{"max_plays": 1, **g} for g in c.get("exclusive_groups", [])]
        c["next"] = [{"priority": 100, **n} for n in c.get("next", [])]
        c.setdefault("variables", [])
        for d in c["variables"]: d.setdefault("persistence", "save")
        chapters[cid] = c
    scenes = {}
    for sid, s in scenes_src.items():
        s = strip(s)
        sc = s.get("scheduling", {})
        s["chapter"] = s.get("chapter")
        s["scheduling"] = {"mode": sc.get("mode", "scheduled"), "priority": sc.get("priority", 100),
                           "max_plays": sc.get("max_plays", 1), "cooldown": sc.get("cooldown", 0),
                           "exclusive_groups": sc.get("exclusive_groups", []), "weight": sc.get("weight", 1),
                           **({"order": sc["order"]} if "order" in sc else {}),
                           **({"conditions": sc["conditions"]} if "conditions" in sc else {})}
        s["start"] = s.get("start") or s["nodes"][0]["id"]
        s.setdefault("variables", [])
        for d in s["variables"]: d.setdefault("persistence", "save")
        if censored_ed: s["nodes"] = censor_nodes(s["nodes"])
        scenes[sid] = s

    # --- preset: tema, telas e textos
    preset_name = theme.get("preset", "classic")
    pdir = PRESETS / preset_name
    if not pdir.is_dir(): raise SystemExit(f"preset {preset_name} não existe em {PRESETS}")
    btheme = deep_merge(strip(load(pdir / "theme.json")), theme); btheme["preset"] = preset_name
    bui = {p.stem: strip(load(p)) for p in sorted((pdir / "ui").glob("*.json"))}
    free_play = [(pid, m, a) for pid, m in sorted(manifests.items()) if pid in plugins_cfg
                 for a in m.get("activities", []) if "free_play" in a]
    game_title = project["title"]
    def title_sub(o):
        if isinstance(o, dict): return {k: (game_title if v == "$project.title" else title_sub(v)) for k, v in o.items()}
        if isinstance(o, list): return [title_sub(x) for x in o]
        return o
    bui = {k: title_sub(v) for k, v in bui.items()}
    if free_play and "minigames" not in screens:            # tela gerada (UI Spec §4, play_activity)
        games = bui["minigames"]["elements"][1]["children"]
        for pid, m, a in free_play:
            games.append({"id": f"btn_{m['namespace']}_{a['id']}", "type": "button", "text": a["name"],
                          "actions": [{"do": "play_activity", "activity": f"{m['namespace']}.{a['id']}"}]})
        for pid, m, a in free_play[:1]:
            for b in m.get("records", []):
                games.append({"id": f"rec_{m['namespace']}_{b['id']}", "type": "records_list",
                              "board": f"{m['namespace']}.{b['id']}", "max_items": 5})
    elif not free_play and "minigames" not in screens:
        bui.pop("minigames")
    bui.update(screens)                                      # telas do projeto substituem as do preset

    # --- assets
    bassets = {aid: {**a, "path": "res://vn_content/assets/" + a["path"]} for aid, a in assets.items()}
    for aid, (t, path) in PRESET_ASSETS.items():
        bassets.setdefault(aid, {"type": t, "path": path})
        for old in assets.get(aid, {}).get("renamed_from", []): aliases[old] = aid
    for aid, a in assets.items():
        for old in a.get("renamed_from", []): aliases[old] = aid
    if censored_ed:                                          # o original não entra no pacote (Build System §5.4)
        for aid, a in assets.items():
            c = a.get("censored") or {}
            if c.get("replace_with"):                        # arquivo e palco da substituta; lugar na galeria do original
                rep = {k: v for k, v in bassets[c["replace_with"]].items() if k not in ("gallery", "gallery_order", "renamed_from")}
                bassets[aid] = {**rep, **{k: a[k] for k in ("type", "gallery", "gallery_order", "renamed_from") if k in a}}

    bundle = {"bundle_version": 1, "format_version": project["format_version"], "project": proj,
              "variables": bvars, "aliases": aliases, "characters": chars, "chapters": chapters,
              "scenes": scenes, "theme": btheme, "ui": bui, "sets": sets, "assets": bassets}
    raw = json.loads(jcs(bundle))                            # normaliza (ordem e números) antes do hash
    bundle["content_hash"] = sri(jcs(raw).encode("utf-8"))

    # --- traduções: preset (idiomas do produto) < plugins < projeto
    censored_paths = {f"{sid}/{n['id']}" for sid, s in scenes_src.items() for n in s["nodes"]
                      if n.get("censored_text") or n.get("censored_prompt")} | \
                     {f"{sid}/{n['id']}/{o['id']}" for sid, s in scenes_src.items() for n in s["nodes"]
                      for o in n.get("options", []) if o.get("censored_text")}
    out_locales = {}
    for lang in locales:
        strings = {}
        pl = pdir / "locales" / f"{lang}.json"
        if not pl.exists(): pl = pdir / "locales" / f"{lang.split('-')[0]}.json"
        if not pl.exists(): pl = pdir / "locales" / "en.json"
        if pl.exists(): strings.update({k: v for k, v in load(pl)["strings"].items()})
        for pid, m in sorted(manifests.items()):
            if pid not in plugins_cfg: continue
            pls = m.get("plugin_locales", {})
            src = pls.get(lang) or pls.get(m.get("default_locale", "en"), {})
            for k, v in src.items(): strings[f"plugin/{m['namespace']}/{k}"] = v
            for _, m2, a in free_play:
                if m2 is m and f"activity/{a['id']}/name" in src:
                    strings[f"ui/minigames/btn_{m['namespace']}_{a['id']}"] = src[f"activity/{a['id']}/name"]
        if (root / "locales" / lang).is_dir():
            for p in sorted((root / "locales" / lang).rglob("*.json")):
                for k, v in load(p)["strings"].items():
                    strings[k] = v["text"] if isinstance(v, dict) else v
        if censored_ed:                                      # o texto censurado ocupa o lugar do original
            for k in censored_paths: strings.pop(k, None)    # sem tradução censurada, cai no texto-fonte censurado
            for k in [k for k in strings if k.endswith("/censored")]: strings[k[:-len("/censored")]] = strings.pop(k)
        out_locales[lang] = {"locale": lang, "strings": strings}

    # --- plugins: permissão efetiva = pedido ∩ concessão (o aceite já foi conferido pelo validador)
    bplugins = {}
    for pid, cfg in sorted(plugins_cfg.items()):
        if not cfg.get("enabled", True) or pid not in manifests: continue
        m = manifests[pid]; lk = lock.get(pid, {})
        asked = {f"runtime:{c}" for c in m.get("capabilities", {}).get("runtime", [])} | \
                {f"editor:{c}" for c in m.get("capabilities", {}).get("editor", [])}
        grants = cfg.get("grants", {})
        conf = {k: v["default"] for k, v in m.get("config_schema", {}).get("properties", {}).items() if "default" in v}
        conf.update(cfg.get("config", {}))
        bplugins[pid] = {"id": pid, "namespace": m["namespace"], "version": m["version"],
                         "path": f"res://vn_plugins/{m['namespace']}/", "trust": lk.get("trust", "local"),
                         "embedded": bool(lk.get("embedded", False)),
                         "capabilities": sorted(asked & set(grants.get("capabilities", []))),
                         "variables": {"read": sorted(grants.get("variables", {}).get("read", [])),
                                       "write": sorted(grants.get("variables", {}).get("write", []))},
                         "scenes": sorted(grants.get("scenes", [])), "config": conf}
    return bundle, out_locales, {"plugins": bplugins}, plugin_roots


def censor_nodes(nodes):
    """Edição censurada: aplica o filtro uma vez, no build. Passos skip viram um desvio para o próximo
    (o id fica, para saves e caminhos de texto continuarem válidos); o texto censurado substitui o original."""
    out = []
    for i, n in enumerate(nodes):
        nxt = n.get("next") or (nodes[i + 1]["id"] if i + 1 < len(nodes) else None)
        if n.get("censor") == "skip":
            out.append({"id": n["id"], "type": "jump", "goto": nxt} if nxt else {"id": n["id"], "type": "end", "then": "schedule"})
            continue
        n = {k: v for k, v in n.items() if k != "censor"}
        if "censored_text" in n: n["text"] = n.pop("censored_text")
        if "censored_prompt" in n: n["prompt"] = n.pop("censored_prompt")
        if "options" in n:
            n["options"] = [{**{k: v for k, v in o.items() if k != "censored_text"}, **({"text": o["censored_text"]} if "censored_text" in o else {})} for o in n["options"]]
        out.append(n)
    return out


def write(out, bundle, locales, plugins):
    out = Path(out); (out / "locales").mkdir(parents=True, exist_ok=True)
    (out / "bundle.json").write_text(jcs(bundle), encoding="utf-8")
    for lang, doc in locales.items(): (out / "locales" / f"{lang}.json").write_text(jcs(doc), encoding="utf-8")
    (out / "plugins.json").write_text(jcs(plugins), encoding="utf-8")


def stage(root, out, bundle, plugin_roots, manifests_ids):
    root, out = Path(root), Path(out)
    censored_ed = bundle["project"]["content_filter"]["edition"] == "censored"
    for aid, a in bundle["assets"].items():
        if not a["path"].startswith("res://vn_content/assets/"): continue
        if censored_ed and a.get("censored", {}).get("hide"): continue   # nunca aparece nesta edição
        rel = a["path"][len("res://vn_content/assets/"):]
        src = root / "assets" / rel
        if src.exists():
            dst = out / "assets" / rel; dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src, dst)
    for pid in manifests_ids:
        d = plugin_roots[pid]; ns = load(d / "plugin.json")["namespace"]
        dst = out / "vn_plugins" / ns
        if dst.exists(): shutil.rmtree(dst)
        shutil.copytree(d, dst, ignore=shutil.ignore_patterns("editor", "tests", "docs", "node_modules", "*.md"))


if __name__ == "__main__":
    args = sys.argv[1:]
    do_stage = "--stage" in args
    if do_stage: args.remove("--stage")
    edition = None
    if "--edition" in args:
        i = args.index("--edition")
        if i + 1 >= len(args) or args[i + 1] not in ("standard", "censored"): raise SystemExit(__doc__)
        edition = args[i + 1]; del args[i:i + 2]
    godot = None
    if "--godot" in args:
        i = args.index("--godot")
        if i + 1 >= len(args): raise SystemExit(__doc__)
        godot = Path(args[i + 1]); del args[i:i + 2]
        if not (godot / "project.godot").exists(): raise SystemExit(f"{godot} não é um projeto Godot (falta project.godot)")
        args.insert(1, str(godot / "vn_content"))
    if len(args) < 2: raise SystemExit(__doc__)
    out = Path(args[1])
    if godot:                                                # recomeça do zero: nada velho fica no projeto
        for d in (out, godot / "vn_plugins"):
            if d.exists(): shutil.rmtree(d)
    b, l, p, roots = compile_project(args[0], args[2:], edition)
    write(out, b, l, p)
    if do_stage or godot: stage(args[0], out, b, roots, list(p["plugins"]))
    if godot:
        if (out / "vn_plugins").exists(): shutil.move(str(out / "vn_plugins"), str(godot / "vn_plugins"))
    print(f"bundle gravado em {out} ({b['content_hash']}; {len(b['scenes'])} cenas, "
          f"{len(l)} idioma(s), {len(p['plugins'])} plugin(s))")
