#!/usr/bin/env python3
"""Confere os resultados da bancada (falha a CI se uma resposta do spike for "não").

  check_results.py native <native-linux.json>
  check_results.py webview <webview-*.json>...
"""

import json
import sys
from pathlib import Path


def by_step(steps: list) -> dict:
    return {s["step"]: s["result"] for s in steps}


def check_plugins(s: dict, after_v2: str) -> list[str]:
    bad = []
    v1, v2 = s.get("probe_v1", {}), s.get(after_v2, {})
    if v1.get("probe", {}).get("describe", {}).get("thing_version") != 1:
        bad.append("class_name do pacote v1 não funcionou")
    if v1.get("fishing", {}).get("game_class") != "FishingGame":
        bad.append("plugin de pesca não abriu o minijogo (FishingGame)")
    d2 = v2.get("probe", {}).get("describe", {})
    if d2.get("thing_version") != 2 or d2.get("extra") != "extra":
        bad.append("a troca do pacote não trouxe o código v2 com o class_name novo")
    return bad


def main() -> None:
    kind, files = sys.argv[1], [Path(p) for p in sys.argv[2:]]
    bad = []
    for f in files:
        data = json.loads(f.read_text())
        if kind == "native":
            bad += [f"{f.name}: {b}" for b in check_plugins(by_step(data), "probe_v2_after_1_pass")]
            continue
        r = data.get("report", {})
        bad += [f"{f.name}: {e}" for e in r.get("errors", [])]
        for tpl, steps in r.get("plugins", {}).items():
            s = by_step(steps)
            bad += [f"{f.name}: {tpl}: {b}" for b in check_plugins(s, "probe_v2")]
            if not s.get("asset sha256 confere", {}).get("ok"):
                bad.append(f"{f.name}: {tpl}: asset com acento não chegou igual por vnpreview")
            for o in s.get("fora do mapa", [{"path": "?", "refused": False}]):
                if not o["refused"]:
                    bad.append(f"{f.name}: {tpl}: o protocolo serviu {o['path']}")
        for tpl, t in r.get("templates", {}).items():
            c = t.get("checks", {})
            if c.get("wasm_content_type") != "application/wasm" or not c.get("compile_streaming"):
                bad.append(f"{f.name}: {tpl}: .wasm sem application/wasm ou sem compilação em streaming ({c})")
        if "official" not in r.get("templates", {}) or "official" not in r.get("plugins", {}):
            bad.append(f"{f.name}: o template oficial não abriu")
        print(f"{f.name}: {data.get('os')} {data.get('origin')}: " + ", ".join(
            f"{k} {v['first_open_ms']} ms / {v['reopen_p50_ms']} ms" for k, v in r.get("templates", {}).items()))
    for b in bad:
        print("ERRO:", b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
