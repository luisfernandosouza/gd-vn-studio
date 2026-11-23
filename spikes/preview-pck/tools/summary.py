#!/usr/bin/env python3
"""Resumo em poucas linhas dos JSON de build/results (para o log da CI e o README)."""

import json
import sys
from pathlib import Path


def steps(lst):
    return {s["step"]: s["result"] for s in lst}


for f in sorted(Path(sys.argv[1]).glob("*.json")):
    d = json.loads(f.read_text())
    if f.name.startswith("webview-"):
        r = d["report"]
        for tpl, t in r.get("templates", {}).items():
            c = t.get("checks", {})
            print(f"SUMMARY {f.stem} {tpl}: abertura {t['first_open_ms']} ms, reabertura p50 {t['reopen_p50_ms']} / p95 {t['reopen_p95_ms']} ms,"
                  f" wasm {c.get('wasm_content_type')}, streaming {c.get('compile_streaming')} ({round(c.get('compile_streaming_ms', 0))} ms),"
                  f" secure {c.get('secure_context')}")
        for tpl, lst in r.get("plugins", {}).items():
            s = steps(lst)
            m2, rl, http = s.get("mount probe-v2", {}), s.get("reload probe", {}), s.get("http asset (HTTPRequest do Godot)", {})
            print(f"SUMMARY {f.stem} {tpl} plugins: v2 fetch {m2.get('fetch_ms')} ms, grava {m2.get('write_ms')} ms, monta {m2.get('mount_ms')} ms,"
                  f" recarga {rl.get('reload_ms')} ms, v2 ok {s.get('probe_v2', {}).get('probe', {}).get('describe')},"
                  f" HTTPRequest {http}, fetch asset {s.get('fetch asset', {}).get('fetch_ms')} ms")
        if r.get("errors"):
            print(f"SUMMARY {f.stem} erros: {r['errors']}")
    elif f.name.startswith("pck-"):
        print(f"SUMMARY {f.stem}: frio {d['cold']['total_ms']} ms (import {d['cold']['import_ms']}), quente p50 {d['warm_p50_ms']} / p95 {d['warm_p95_ms']} ms, erros {d['warm_errors']}")
    elif f.name.startswith("native-"):
        s = steps(d)
        print(f"SUMMARY {f.stem}: recarga {s.get('reload probe 1 pass', {}).get('reload_ms')} ms, v2 {s.get('probe_v2_after_1_pass', {}).get('probe', {}).get('describe')}")
