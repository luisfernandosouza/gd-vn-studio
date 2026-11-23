#!/usr/bin/env python3
"""Resume os resultados do teste B dos assets (harness/assets.js). Uso: summary_assets.py <results.json>..."""
import json, sys


def f(s, k="p50"):
    return "—" if not s else f"{s[k]:.0f}"


for path in sys.argv[1:]:
    r = json.load(open(path))
    print(f"== {path}: {r.get('engine')} | {r.get('renderer')} | erro: {r.get('error') or r.get('swap_error')}")
    if "all" not in r:
        print("  progresso:", r.get("progress"))
        continue
    print("  abertura do motor", r.get("open_ms"), "ms | arquivos (MB)", r.get("files_mb"))
    for name in ("lru", "all"):
        imgs = r[name] if name == "lru" else r[name]["images"]
        print(f"  [{name}] imagens {imgs['loaded']}/{imgs['of']} em {imgs['total_s']} s, p50/p95 {f(imgs['total'])}/{f(imgs['total'], 'p95')} ms, marcas ok {imgs['markers_ok']}, erro {imgs['error']}")
        for ext, v in imgs["by_format"].items():
            print(f"      {ext:4} {v['n']:3} × {v['mb_mean']} MB: total {f(v['total'])}/{f(v['total'], 'p95')} | leitura {f(v['fetch'])} | decodificação {f(v['decode'])} | textura {v['upload']['p50']}")
        for m in r[name]["mem"]:
            print(f"      memória {m['label']:16} WASM {m['wasm_mb']} | texturas {m['tex_mb']} | processos {m['rss_mb']} ({m['rss_processes']}) | cache {m['cache_size']}")
    mus = r["all"]["music"]
    print(f"  músicas {mus['loaded']}/{mus['of']} em {mus['total_s']} s, p50/p95 {f(mus['total'])}/{f(mus['total'], 'p95')} ms, erro {mus['error']}; toca: {r['all'].get('music_plays')}")
    for ext, v in mus["by_format"].items():
        print(f"      {ext:4} {v['n']:3} × {v['mb_mean']} MB: total {f(v['total'])}/{f(v['total'], 'p95')} | leitura {f(v['fetch'])} | decodificação {f(v['decode'])}")
    si, sm = r.get("swap_image"), r.get("swap_music")
    if si:
        print(f"  troca da imagem em uso: p50/p95 {f(si['total'])}/{f(si['total'], 'p95')} ms (runtime {f(si['runtime'])}/{f(si['runtime'], 'p95')}), nova na tela {si['shown_new']}")
    if sm:
        print(f"  troca da música em uso: p50/p95 {f(sm['total'])}/{f(sm['total'], 'p95')} ms (runtime {f(sm['runtime'])}/{f(sm['runtime'], 'p95')}), em uso {sm.get('in_use')}, duração nova {sm['new_length']}, posição mantida {sm['kept_position']}")
    for k in ("loader_http", "loader_js", "mipmaps"):
        v = r[k]["by_format"].get("png", {})
        print(f"  20 PNG, {k:11}: total {f(r[k]['total'])}/{f(r[k]['total'], 'p95')} | leitura {f(v.get('fetch'))} | decodificação {f(v.get('decode'))}")
    print(f"  20 PNG lidos pela página (sem Godot): {f(r.get('page_fetch_png'))}/{f(r.get('page_fetch_png'), 'p95')} ms")
