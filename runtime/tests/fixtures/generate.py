#!/usr/bin/env python3
"""Gera os bundles de teste do runtime (tarefa M0-08; spec 09 §1.1, decisão D22; Runtime Spec §2.1).

Uso, da raiz do repositório:

    python3 runtime/tests/fixtures/generate.py           # (re)gera runtime/tests/fixtures/bundles/
    python3 runtime/tests/fixtures/generate.py --check   # gera duas vezes e confere: schemas, mídia e bytes iguais

Para cada projeto de `src/projects/<nome>/` (com os arquivos de `src/common/` por baixo), o script:

1. monta o projeto numa pasta temporária e gera ali os assets sintéticos de `assets.json`:
   PNG de cores sólidas e formas, WAV de tons senoidais. Nada de arte de terceiros nem gerada por IA;
2. compila com o compilador de referência `docs/specs/tools/compile_bundle.py`, que valida o projeto
   (zero erros) antes de compilar;
3. grava a forma canônica (Runtime Spec §2) e os assets em `bundles/<nome>/`, que fica fora do Git.

O código dos plugins não é copiado para `bundles/`: o Godot analisaria os scripts dentro de `runtime/`,
e os testes de atividade usam o dublê do Plugin Host. `plugins.json` do bundle traz o plugin normalmente.

Só usa a biblioteca padrão do Python, mais o `jsonschema` que o validador das specs já exige.
"""
import hashlib, json, math, shutil, struct, sys, tempfile, zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SPECS = REPO / "docs" / "specs"
SRC = HERE / "src"
OUT = HERE / "bundles"

sys.path.insert(0, str(SPECS / "tools"))
import compile_bundle                                          # noqa: E402

# Edições compiladas por projeto (Build System §5.4). O modo stream sai nas duas.
EDITIONS = {"stream": ["standard", "censored"]}
BUNDLE_FILES = {"bundle.json": "bundle", "plugins.json": "bundle-plugins", "licenses.json": "bundle-licenses"}
MEDIA_EXT = {".png", ".wav"}


# ------------------------------------------------------------------ imagens (PNG RGBA, determinístico)

def hexrgba(c, a=255):
    return (int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16), a)


def solid_with_shapes(w, h, color, shapes=()):
    """Fundo sólido + formas (retângulos e círculos), linha a linha, para tamanhos de cenário."""
    bg = hexrgba(color)
    out = []
    for y in range(h):
        row = [bg] * w
        for s in shapes:
            if s[0] == "rect":
                _, x0, y0, x1, y1, c = s
                if y0 <= y < y1:
                    row[x0:x1] = [hexrgba(c)] * (x1 - x0)
            elif s[0] == "circle":
                _, cx, cy, r, c = s
                dy = y - cy
                if abs(dy) < r:
                    dx = int(math.sqrt(r * r - dy * dy))
                    a, b = max(0, cx - dx), min(w, cx + dx)
                    row[a:b] = [hexrgba(c)] * (b - a)
        out.append(bytes(v for px in row for v in px))
    return out


def png_rows(w, h, rows):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + r for r in rows)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def background(color, *shapes):
    """Cenário 1920×1080 (resolução base do runtime, RT §1.1): cor sólida, faixa de chão e formas."""
    w, h = 1920, 1080
    return png_rows(w, h, solid_with_shapes(w, h, color, [("rect", 0, 760, w, h, "#3b3b3b")] + list(shapes)))


def transparent_with_shapes(w, h, shapes):
    out = []
    clear = (0, 0, 0, 0)
    for y in range(h):
        row = [clear] * w
        for s in shapes:
            if s[0] == "rect":
                _, x0, y0, x1, y1, c = s
                if y0 <= y < y1:
                    row[x0:x1] = [hexrgba(c)] * (x1 - x0)
            elif s[0] == "ellipse":
                _, cx, cy, rx, ry, c = s
                dy = (y - cy) / ry
                if abs(dy) < 1:
                    dx = int(rx * math.sqrt(1 - dy * dy))
                    a, b = max(0, cx - dx), min(w, cx + dx)
                    row[a:b] = [hexrgba(c)] * (b - a)
        out.append(bytes(v for px in row for v in px))
    return png_rows(w, h, out)


def sprite(mark):
    """Personagem 480×960 com fundo transparente: corpo em elipse e uma marca por expressão."""
    body = [("ellipse", 240, 620, 200, 340, "#3a7bd5"), ("ellipse", 240, 200, 130, 130, "#f2c9a0")]
    marks = {"neutral": [("rect", 180, 230, 300, 245, "#202020")],
             "happy": [("ellipse", 240, 235, 60, 25, "#202020"), ("ellipse", 240, 225, 60, 25, "#f2c9a0")],
             "sad": [("ellipse", 240, 250, 60, 25, "#202020"), ("ellipse", 240, 260, 60, 25, "#f2c9a0")]}
    eyes = [("ellipse", 195, 180, 12, 16, "#202020"), ("ellipse", 285, 180, 12, 16, "#202020")]
    return transparent_with_shapes(480, 960, body + eyes + marks[mark])


def textbox():
    """64×64 com borda de 16 px (nine_slice [16, 16, 16, 16])."""
    return transparent_with_shapes(64, 64, [("rect", 0, 0, 64, 64, "#ffffff"), ("rect", 4, 4, 60, 60, "#1b2a3a")])


# ------------------------------------------------------------------ áudio (WAV PCM 16 bits mono)

RATE = 22050


def wav(samples):
    data = b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples)
    return (b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE"
            + b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, RATE, RATE * 2, 2, 16)
            + b"data" + struct.pack("<I", len(data)) + data)


def tone(freqs, seconds, volume=0.3, fade=0.01):
    n = int(RATE * seconds)
    f = max(1, int(RATE * fade))
    return wav(volume * min(1.0, i / f, (n - i) / f) * sum(math.sin(2 * math.pi * fr * i / RATE) for fr in freqs) / len(freqs)
               for i in range(n))


def loop(freq, seconds):
    """Música que fecha o laço sem estalo: frequência ajustada para um número inteiro de ciclos."""
    n = int(RATE * seconds)
    cycles = round(freq * seconds)
    return wav(0.25 * math.sin(2 * math.pi * cycles * i / n) for i in range(n))


def noise(seconds):
    x, out = 1, []                                             # LCG fixo: mesmo ruído em toda máquina
    for _ in range(int(RATE * seconds)):
        x = (1103515245 * x + 12345) & 0x7FFFFFFF
        out.append(0.2 * (x / 0x3FFFFFFF - 1))
    return wav(out)


# Receita de cada arquivo citado em src/common/assets.json (caminho relativo a assets/).
MEDIA = {
    "backgrounds/day.png": lambda: background("#87ceeb", ("circle", 1600, 220, 110, "#fff3b0")),
    "backgrounds/night.png": lambda: background("#0b1d3a", ("circle", 1500, 200, 90, "#e8e8f0")),
    "backgrounds/dusk.png": lambda: background("#e0785a", ("circle", 960, 760, 160, "#ffb347")),
    "backgrounds/dusk_safe.png": lambda: background("#7a8a99", ("rect", 860, 660, 1060, 860, "#a0aab4")),
    "backgrounds/secret.png": lambda: background("#6a1b9a", ("rect", 760, 340, 1160, 740, "#ff00ff")),
    "backgrounds/placeholder.png": lambda: background("#808080"),
    "characters/probe/neutral.png": lambda: sprite("neutral"),
    "characters/probe/happy.png": lambda: sprite("happy"),
    "characters/probe/sad.png": lambda: sprite("sad"),
    "objects/lamp_off.png": lambda: transparent_with_shapes(128, 128, [("rect", 56, 64, 72, 128, "#555555"), ("ellipse", 64, 40, 36, 36, "#9e9e9e")]),
    "objects/lamp_on.png": lambda: transparent_with_shapes(128, 128, [("rect", 56, 64, 72, 128, "#555555"), ("ellipse", 64, 40, 36, 36, "#ffe066")]),
    "objects/box.png": lambda: transparent_with_shapes(160, 160, [("rect", 0, 0, 160, 160, "#8d6e63"), ("rect", 10, 10, 150, 150, "#a1887f")]),
    "ui/textbox.png": textbox,
    "audio/music/loop_a.wav": lambda: loop(220, 2.0),
    "audio/music/loop_b.wav": lambda: loop(330, 2.0),
    "audio/sfx/click.wav": lambda: tone([1000], 0.05),
    "audio/sfx/chime.wav": lambda: tone([880, 1320], 0.4, fade=0.05),
    "audio/sfx/noise.wav": lambda: noise(0.3),
    "audio/voice/probe_001.wav": lambda: tone([180, 270], 0.6, fade=0.05),
}


# ------------------------------------------------------------------ montagem e compilação

def assemble(name, dst, cache):
    shutil.copytree(SRC / "common", dst)
    shutil.copytree(SRC / "projects" / name, dst, dirs_exist_ok=True)
    assets = json.loads((dst / "assets.json").read_text(encoding="utf-8"))["assets"]
    for aid, a in sorted(assets.items()):
        if a["path"] not in MEDIA:
            raise SystemExit(f"{aid}: sem receita em MEDIA para {a['path']}")
        if a["path"] not in cache:
            cache[a["path"]] = MEDIA[a["path"]]()
        p = dst / "assets" / a["path"]
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(cache[a["path"]])


def build(out):
    """Gera todos os bundles em `out`. Devolve a lista de (nome, content_hash)."""
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    cache, made = {}, []
    with tempfile.TemporaryDirectory() as tmp:
        for proj in sorted(p.name for p in (SRC / "projects").iterdir() if p.is_dir()):
            root = Path(tmp) / proj
            assemble(proj, root, cache)
            for edition in EDITIONS.get(proj, ["standard"]):
                name = proj if edition == "standard" else f"{proj}_{edition}"
                b, l, p, roots, lic = compile_bundle.compile_project(root, (), edition)
                compile_bundle.write(out / name, b, l, p, lic)
                compile_bundle.stage(root, out / name, b, roots, [])      # só os assets (veja a docstring)
                made.append((name, b["content_hash"]))
    (out / "index.json").write_text(json.dumps(
        {"bundles": {n: {"content_hash": h, "path": f"res://tests/fixtures/bundles/{n}/"} for n, h in made}},
        indent=2) + "\n", encoding="utf-8")
    return made


# ------------------------------------------------------------------ --check

def digest(folder):
    return {str(p.relative_to(folder)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(folder.rglob("*")) if p.is_file()}


def check(out):
    from jsonschema import Draft202012Validator
    from referencing import Registry, Resource
    schemas = {}
    for f in (SPECS / "schemas").glob("*.schema.json"):
        s = json.loads(f.read_text(encoding="utf-8")); schemas[s["$id"]] = s
    registry = Registry().with_resources((i, Resource.from_contents(s)) for i, s in schemas.items())
    base = "https://schemas.vnstudio.dev/specs-v1.0.0/"
    validator = lambda n: Draft202012Validator(schemas[f"{base}{n}.schema.json"], registry=registry)
    errors = []
    for bdir in sorted(d for d in out.iterdir() if d.is_dir()):
        for fname, schema in BUNDLE_FILES.items():
            doc = json.loads((bdir / fname).read_text(encoding="utf-8"))
            errors += [f"{bdir.name}/{fname}: {e.json_path}: {e.message}" for e in validator(schema).iter_errors(doc)]
        for loc in sorted((bdir / "locales").glob("*.json")):
            doc = json.loads(loc.read_text(encoding="utf-8"))
            errors += [f"{bdir.name}/locales/{loc.name}: {e.message}" for e in validator("bundle-locale").iter_errors(doc)]
        bundle = json.loads((bdir / "bundle.json").read_text(encoding="utf-8"))
        for aid, a in bundle["assets"].items():                     # todo asset do projeto foi gerado e copiado
            if a["path"].startswith("res://vn_content/assets/"):
                rel = a["path"][len("res://vn_content/assets/"):]
                hidden = bundle["project"]["content_filter"]["edition"] == "censored" and a.get("censored", {}).get("hide")
                if not hidden and not (bdir / "assets" / rel).is_file():
                    errors.append(f"{bdir.name}: asset {aid} sem arquivo em assets/{rel}")
        for f in bdir.rglob("*"):                                    # só mídia sintética e os JSON do bundle
            if f.is_file() and f.suffix not in MEDIA_EXT | {".json"}:
                errors.append(f"{bdir.name}: arquivo inesperado {f.relative_to(bdir)}")
    with tempfile.TemporaryDirectory() as tmp:                       # determinismo: a segunda geração é igual
        build(Path(tmp) / "bundles")
        if digest(Path(tmp) / "bundles") != digest(out):
            errors.append("duas gerações seguidas deram bytes diferentes")
    return errors


if __name__ == "__main__":
    made = build(OUT)
    for name, h in made:
        print(f"{name:20} {h}")
    print(f"{len(made)} bundles em {OUT.relative_to(REPO)}")
    if "--check" in sys.argv[1:]:
        errs = check(OUT)
        for e in errs:
            print("ERRO", e)
        if errs:
            raise SystemExit(1)
        print("conferência ok: schemas, assets e determinismo")
