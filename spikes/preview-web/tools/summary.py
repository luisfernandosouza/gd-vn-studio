#!/usr/bin/env python3
"""Resume arquivos de resultados da bancada (bench.mjs ou run.js). Uso: summary.py <results.json>..."""
import json, sys
for f in sys.argv[1:]:
    r = json.load(open(f))
    print(f"== {f}: {r.get('engine') or r.get('browser')} | {r.get('renderer')} | erro: {r.get('error')}")
    for t, v in r.get("templates", {}).items():
        print(" ", t, "abertura fria", v["first_open"]["cold_ms"], "ms, com cache p50/p95", v["first_open"]["warm"]["p50"], v["first_open"]["warm"]["p95"])
        for b in ("demo", "big"):
            if b in v:
                print("   ", b, " | ".join(f"{k} {v[b][k]['total']['p50']}/{v[b][k]['total']['p95']}" for k in ("restart_engine", "engine_open", "in_memory", "incremental")), "| salto p95", v[b]["jump"]["p95"], "| hash", v[b]["hash_ok"])
        if "activity" in v:
            print("    minijogo p95", v["activity"]["start"]["p95"], "overlay", v["activity"]["overlay_shown"])
