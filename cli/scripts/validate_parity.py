#!/usr/bin/env python3
"""Gera os casos de paridade do validador TypeScript (tarefa M5-01, Req §14).

Monta, numa pasta, o projeto de exemplo sem alterações e cada um dos casos de
docs/specs/tools/test_validate.py (a mesma mutação, o mesmo --export), roda neles o
validador de referência (validate.py) e grava manifest.json com os erros e avisos
esperados. O teste cli/src/validate/parity.test.ts roda o validador TypeScript nas
mesmas pastas e compara.

Uso: python3 cli/scripts/validate_parity.py <pasta-de-saída>
"""
import json, shutil, sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[2] / "docs" / "specs" / "tools"
sys.path.insert(0, str(TOOLS))
import test_validate as tv  # noqa: E402
import validate  # noqa: E402


def build(out: Path, n: int, code: str | None, mutate, export: bool) -> dict:
    case = out / f"{n:03d}"
    w = tv.Workspace.__new__(tv.Workspace)
    w.tmp = case; w.proj = case / "demo"; w.plug = case / "fishing"
    shutil.copytree(tv.DEMO, w.proj); shutil.copytree(tv.PLUGIN, w.plug)
    plugins = [w.plug]
    if code == "P001":
        twin = case / "twin"; shutil.copytree(w.plug, twin)
        t = json.loads((twin / "plugin.json").read_text(encoding="utf-8")); t["id"] = "outro.fishing"
        (twin / "plugin.json").write_text(json.dumps(t), encoding="utf-8"); plugins.append(twin)
    elif code == "W004":
        plugins = []
    elif mutate is not None:
        mutate(w)
    errs, warns = validate.run(w.proj, plugins, export)
    return {"code": code, "export": export, "project": str(w.proj), "plugins": [str(p) for p in plugins],
            "errors": errs, "warnings": warns}


def main():
    out = Path(sys.argv[1]).resolve()
    if out.exists(): shutil.rmtree(out)
    out.mkdir(parents=True)
    cases = [dict(build(out, 0, None, None, False), desc="projeto de exemplo sem alterações")]
    for n, (code, desc, mutate, export) in enumerate(tv.CASES, 1):
        cases.append(dict(build(out, n, code, mutate, export), desc=desc))
    (out / "manifest.json").write_text(json.dumps({"cases": cases}, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(cases)} casos gerados em {out}")


if __name__ == "__main__":
    main()
