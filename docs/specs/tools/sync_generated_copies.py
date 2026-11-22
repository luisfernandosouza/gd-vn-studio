#!/usr/bin/env python3
"""Gera as cópias de schemas e presets que os componentes usam no build (spec 09 §1 e §1.2, tarefa M0-03).

`docs/specs/schemas/` e `docs/specs/presets/` são a fonte única. Nenhum componente guarda cópia no Git:
as pastas abaixo são geradas por este script, ficam no .gitignore e nunca são editadas à mão.

  runtime  runtime/vn_runtime/presets/          cópia de docs/specs/presets/ + fonts/ (os ids preset/font_*)
           runtime/vn_runtime/licenses/         MIT do runtime, licença e copyright do Godot, OFL de cada fonte
  studio   studio/src-tauri/resources/specs/    schemas/ e presets/ (o instalador do Studio os embute, §1.2)
  cli      cli/schemas/                         schemas/ (vão no pacote npm da CLI)

Cada pasta gerada leva um `.generated.json` com o sha256 de cada arquivo. `--check` confere, sem rede, que
cada cópia é igual à fonte (ou, para as fontes e as licenças externas, ao sha256 fixado em
generated_sources.json), que nada sobrou ou foi editado, e que nenhuma cópia está no Git.

As fontes vêm de google/fonts num commit fixo, conferidas pelo sha256, e viram fontes estáticas Regular
com o instancer do fontTools (versão fixada em generated_sources.json). Os downloads ficam em cache
(`--cache`, padrão ~/.cache/vnstudio-generated).

Uso:
  python docs/specs/tools/sync_generated_copies.py [runtime|studio|cli ...]      gera (padrão: todos)
  python docs/specs/tools/sync_generated_copies.py --check [runtime|studio|cli]  só confere
"""
import argparse, ast, hashlib, json, os, shutil, subprocess, sys, tempfile, urllib.request
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
SPECS = TOOLS.parent
REPO = SPECS.parent.parent
SOURCES = json.loads((TOOLS / "generated_sources.json").read_text(encoding="utf-8"))
STAMP = ".generated.json"
# Arquivos que o editor do Godot cria ao lado dos recursos importados: não fazem parte da cópia.
GODOT_SIDECARS = (".import", ".uid")

RUNTIME_PRESETS = REPO / "runtime/vn_runtime/presets"
RUNTIME_LICENSES = REPO / "runtime/vn_runtime/licenses"
STUDIO_SPECS = REPO / "studio/src-tauri/resources/specs"
CLI_SCHEMAS = REPO / "cli/schemas"

TARGETS = {
    "runtime": [RUNTIME_PRESETS, RUNTIME_LICENSES],
    "studio": [STUDIO_SPECS],
    "cli": [CLI_SCHEMAS],
}


def sha256(data: bytes) -> str: return hashlib.sha256(data).hexdigest()


def tree(src: Path, prefix=""):
    """{caminho relativo: bytes} de todos os arquivos de uma pasta da fonte."""
    return {prefix + p.relative_to(src).as_posix(): p.read_bytes() for p in sorted(src.rglob("*")) if p.is_file()}


# --- fontes e licenças externas ------------------------------------------------------------------

def fetch(url: str, expected: str, cache: Path) -> bytes:
    """Baixa (ou lê do cache) e confere o sha256. O cache é indexado pelo hash, então nunca fica velho."""
    cached = cache / expected
    if cached.is_file() and sha256(cached.read_bytes()) == expected:
        return cached.read_bytes()
    print(f"  baixando {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "vnstudio-build"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    got = sha256(data)
    if got != expected:
        raise SystemExit(f"sha256 diferente para {url}\n  esperado {expected}\n  recebido {got}")
    cache.mkdir(parents=True, exist_ok=True)
    cached.write_bytes(data)
    return data


def check_font_ids():
    """Os nomes dos arquivos têm de ser os de compile_bundle.py PRESET_ASSETS, que o bundle referencia."""
    mod = ast.parse((TOOLS / "compile_bundle.py").read_text(encoding="utf-8"))
    expected = None
    for node in mod.body:
        if isinstance(node, ast.Assign) and any(getattr(t, "id", None) == "PRESET_ASSETS" for t in node.targets):
            expected = ast.literal_eval(node.value)
    if expected is None: raise SystemExit("PRESET_ASSETS não encontrado em compile_bundle.py")
    ours = {f["id"]: ("font", f"res://vn_runtime/presets/fonts/{f['file']}") for f in SOURCES["fonts"]["items"]}
    if ours != expected:
        raise SystemExit(f"generated_sources.json e compile_bundle.py PRESET_ASSETS divergem:\n  {ours}\n  {expected}")


def instance_font(var_data: bytes, axes: dict) -> bytes:
    """Fonte estática Regular a partir da variável, com o fontTools fixado e sem carimbo de data (reprodutível)."""
    try:
        import fontTools
    except ImportError:
        raise SystemExit(f"falta o fontTools: python -m pip install fonttools=={SOURCES['fonttools']}")
    if fontTools.version != SOURCES["fonttools"]:
        raise SystemExit(f"fontTools {fontTools.version} instalado; o hash das fontes vale para {SOURCES['fonttools']}")
    with tempfile.TemporaryDirectory() as tmp:
        src, out = Path(tmp) / "in.ttf", Path(tmp) / "out.ttf"
        src.write_bytes(var_data)
        cmd = [sys.executable, "-m", "fontTools.varLib.instancer", str(src), *(f"{k}={v}" for k, v in axes.items()),
               "--static", "--no-recalc-timestamp", "-q", "-o", str(out)]
        subprocess.run(cmd, check=True)
        return out.read_bytes()


def font_files(cache: Path):
    """{fonts/arquivo.ttf: bytes} e {OFL-Família.txt: bytes}."""
    check_font_ids()
    base = SOURCES["fonts"]["repository"]
    fonts, licenses = {}, {}
    for f in SOURCES["fonts"]["items"]:
        url = base + f["source"].replace("[", "%5B").replace("]", "%5D")
        data = instance_font(fetch(url, f["source_sha256"], cache), f["axes"])
        if f["output_sha256"] and sha256(data) != f["output_sha256"]:
            raise SystemExit(f"{f['file']} gerada com sha256 {sha256(data)}, esperado {f['output_sha256']}")
        fonts["fonts/" + f["file"]] = data
        licenses[license_name(f)] = fetch(base + f["license"], f["license_sha256"], cache)
    return fonts, licenses


def license_name(font): return "OFL-" + font["family"].replace(" ", "") + ".txt"


def godot_files(cache: Path):
    g = SOURCES["godot"]
    return {i["file"]: fetch(g["repository"] + i["source"], i["sha256"], cache) for i in g["items"]}


def license_index():
    """Índice das licenças do motor, para a tela de créditos (Build System §4.5, UI Spec §3.1)."""
    g = SOURCES["godot"]
    entries = [
        {"kind": "runtime", "name": "VN Studio runtime", "license": "MIT", "file": "vn_runtime-LICENSE.txt"},
        {"kind": "engine", "name": f"Godot Engine {g['version']}", "license": "MIT", "file": "godot-LICENSE.txt"},
        {"kind": "engine", "name": "Godot Engine: bibliotecas de terceiros", "license": "various", "file": "godot-COPYRIGHT.txt"},
    ]
    for f in SOURCES["fonts"]["items"]:
        entries.append({"kind": "font", "name": f["family"], "license": "OFL-1.1", "file": license_name(f),
                        "id": f["id"], "font": "res://vn_runtime/presets/fonts/" + f["file"]})
    return (json.dumps({"licenses": entries}, ensure_ascii=False, indent=2) + "\n").encode()


# --- o que cada pasta deve conter ------------------------------------------------------------------

def expected_static(target: str):
    """Conteúdo esperado das partes que vêm do próprio repositório (sem rede)."""
    presets, schemas = tree(SPECS / "presets"), tree(SPECS / "schemas")
    if target == "runtime":
        return {RUNTIME_PRESETS: dict(presets),
                RUNTIME_LICENSES: {"vn_runtime-LICENSE.txt": (REPO / "LICENSE").read_bytes(), "index.json": license_index()}}
    if target == "studio":
        return {STUDIO_SPECS: {**{"schemas/" + k: v for k, v in schemas.items()},
                               **{"presets/" + k: v for k, v in presets.items()}}}
    if target == "cli":
        return {CLI_SCHEMAS: dict(schemas)}
    raise ValueError(target)


def pinned_hashes():
    """sha256 fixados dos arquivos externos, por pasta (o que --check usa no lugar do conteúdo)."""
    fonts = {"fonts/" + f["file"]: f["output_sha256"] for f in SOURCES["fonts"]["items"]}
    lic = {license_name(f): f["license_sha256"] for f in SOURCES["fonts"]["items"]}
    lic.update({i["file"]: i["sha256"] for i in SOURCES["godot"]["items"]})
    return {RUNTIME_PRESETS: fonts, RUNTIME_LICENSES: lic}


def write_dir(path: Path, files: dict):
    if path.exists(): shutil.rmtree(path)
    for rel, data in files.items():
        p = path / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
    stamp = {"_comment": "Cópia gerada por docs/specs/tools/sync_generated_copies.py. Não edite: rode o script.",
             "files": {rel: sha256(data) for rel, data in sorted(files.items())}}
    (path / STAMP).write_text(json.dumps(stamp, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"  {path.relative_to(REPO)}: {len(files)} arquivos")


def generate(targets, cache: Path):
    for t in targets:
        print(f"[{t}]")
        out = expected_static(t)
        if t == "runtime":
            fonts, ofl = font_files(cache)
            out[RUNTIME_PRESETS].update(fonts)
            out[RUNTIME_LICENSES].update(ofl)
            out[RUNTIME_LICENSES].update(godot_files(cache))
        for path, files in out.items():
            write_dir(path, files)


# --- conferência --------------------------------------------------------------------------------

def tracked(paths):
    rels = [str(p.relative_to(REPO)) for p in paths]
    r = subprocess.run(["git", "-C", str(REPO), "ls-files", "--", *rels], capture_output=True, text=True, check=True)
    return r.stdout.split()


def check(targets):
    errors = []
    pinned = pinned_hashes()
    for t in targets:
        for path, files in expected_static(t).items():
            rel = path.relative_to(REPO)
            if not path.is_dir():
                errors.append(f"{rel}: não existe (rode o script sem --check)"); continue
            want = {k: sha256(v) for k, v in files.items()}
            want.update(pinned.get(path, {}))
            have = {p.relative_to(path).as_posix(): sha256(p.read_bytes()) for p in path.rglob("*")
                    if p.is_file() and p.name != STAMP and not p.name.endswith(GODOT_SIDECARS)}
            for k in sorted(set(want) | set(have)):
                if k not in have: errors.append(f"{rel}/{k}: falta")
                elif k not in want: errors.append(f"{rel}/{k}: não vem da fonte (sobra ou foi criado à mão)")
                elif have[k] != want[k]: errors.append(f"{rel}/{k}: difere da fonte (editado à mão?)")
            stamp = path / STAMP
            if not stamp.is_file() or json.loads(stamp.read_text(encoding="utf-8")).get("files") != dict(sorted(have.items())):
                errors.append(f"{rel}/{STAMP}: ausente ou não confere com os arquivos")
    in_git = tracked([p for t in targets for p in TARGETS[t]])
    errors += [f"{p}: está no Git; as cópias geradas ficam fora (spec 09 §1)" for p in in_git]
    if errors:
        print("Cópias geradas divergem da fonte:\n  " + "\n  ".join(errors))
        print("Edite docs/specs/schemas/ ou docs/specs/presets/ e rode docs/specs/tools/sync_generated_copies.py.")
        return 1
    print(f"Cópias conferidas: {', '.join(targets)}.")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("targets", nargs="*", metavar="{runtime,studio,cli}")
    ap.add_argument("--check", action="store_true", help="só confere as cópias, sem rede e sem escrever")
    ap.add_argument("--cache", type=Path, default=Path(os.environ.get("VNSTUDIO_GENERATED_CACHE",
                                                                       Path.home() / ".cache/vnstudio-generated")))
    a = ap.parse_args()
    targets = a.targets or list(TARGETS)
    if unknown := [t for t in targets if t not in TARGETS]: ap.error(f"alvo desconhecido: {', '.join(unknown)}")
    if a.check: return check(targets)
    generate(targets, a.cache)
    return check(targets)


if __name__ == "__main__":
    sys.exit(main())
