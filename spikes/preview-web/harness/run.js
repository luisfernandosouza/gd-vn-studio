// Cenários da bancada, rodados dentro da página: servem a qualquer motor
// (Chromium pelo Playwright, WebKitGTK pelo tools/webkitgtk_bench.py).
// Com ?autorun=1&engine=<nome>, roda tudo e grava build/work/results-<nome>.json.
(() => {
  const stats = xs => {
    const s = [...xs].sort((a, b) => a - b);
    const q = p => s[Math.min(s.length - 1, Math.ceil(p * s.length) - 1)];
    return { n: s.length, p50: +q(0.5).toFixed(1), p95: +q(0.95).toFixed(1), max: +s[s.length - 1].toFixed(1) };
  };
  const summarize = xs => ({ total: stats(xs.map(x => x.total)), runtime: stats(xs.map(x => x.runtime)), studio: stats(xs.map(x => x.studio)), detail: xs[xs.length - 1].detail });

  async function editLoop(edits, step) {
    const out = [];
    for (let i = 0; i < edits; i++) {
      const node = _b.bundle.scenes[_b.scene].nodes.find(n => n.id === _b.node);
      node.text = 'Edição ' + i + ': ' + node.text.replace(/^Edição \d+: /, '');
      out.push(await step());
    }
    return summarize(out);
  }

  async function runBundle(name, src, edits) {
    const b = `/build/bundles/${name}`;
    await bench.open(src);
    const bundle = await (await fetch(b + '/bundle.json')).json();
    const scenes = Object.values(bundle.scenes).sort((x, y) => y.nodes.length - x.nodes.length);
    const scene = scenes[Math.floor(scenes.length / 2)];
    const lines = scene.nodes.filter(n => n.type === 'line');
    window._b = { bundle, scene: scene.id, node: lines[Math.floor(lines.length / 2)].id };
    const first = await bench.call('load_url', b + '/bundle.json', 'pt-BR', '', true);
    await bench.call('start', _b.scene, _b.node, '');
    const res = { hash_ok: first.hash_ok };

    res.restart_engine = await editLoop(edits, async () => {
      const t0 = performance.now();
      const studio = await bench.writeCanonical(_b.bundle, 'bundle.json');
      await bench.open(src);
      const d = await bench.call('load_url', '/build/work/bundle.json', 'pt-BR', '', true);
      const s = await bench.call('start', _b.scene, _b.node, '');
      return { total: performance.now() - t0, runtime: d.runtime_ms + s.runtime_ms, studio, detail: d };
    });
    res.engine_open = await editLoop(edits, async () => {
      const t0 = performance.now();
      const studio = await bench.writeCanonical(_b.bundle, 'bundle.json');
      const d = await bench.call('load_url', '/build/work/bundle.json', 'pt-BR', '', true);
      return { total: performance.now() - t0, runtime: d.runtime_ms, studio, detail: d };
    });
    res.in_memory = await editLoop(edits, async () => {
      const t0 = performance.now();
      const text = JSON.stringify(_b.bundle);
      const studio = performance.now() - t0;
      const d = await bench.call('load_text', text, 'pt-BR', '', false);
      return { total: performance.now() - t0, runtime: d.runtime_ms, studio, detail: d };
    });
    res.incremental = await editLoop(edits, async () => {
      const t0 = performance.now();
      const text = JSON.stringify(_b.bundle.scenes[_b.scene]);
      const studio = performance.now() - t0;
      const d = await bench.call('patch_scene', text);
      return { total: performance.now() - t0, runtime: d.runtime_ms, studio, detail: d };
    });
    const ids = Object.keys(_b.bundle.scenes); const jumps = [];
    for (let i = 0; i < edits; i++) {
      const sc = _b.bundle.scenes[ids[(i * 7) % ids.length]];
      const line = sc.nodes.filter(n => n.type === 'line').pop() || sc.nodes[0];
      jumps.push((await bench.call('start', sc.id, line.id, JSON.stringify({ 'global.player_money': 50 + i }))).total_ms);
    }
    res.jump = stats(jumps);
    return res;
  }

  window.runBench = async ({ engine, templates = ['web', 'web-lean'], edits = 20, onlyOpen = false }) => {
    const gl = document.createElement('canvas').getContext('webgl2');
    const ext = gl && gl.getExtension('WEBGL_debug_renderer_info');
    const renderer = gl ? (ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER)) : 'sem WebGL 2';
    const results = { engine, userAgent: navigator.userAgent, renderer, edits, templates: {} };
    for (const tpl of templates) {
      const src = `/build/${tpl}/index.html`;
      const r = results.templates[tpl] = {};
      const cold = await bench.open(src);
      const warm = [];
      for (let i = 0; i < 5; i++) warm.push((await bench.open(src)).ms);
      r.first_open = { cold_ms: +cold.ms.toFixed(0), warm: stats(warm), godot: cold.godot };
      bench.log(`${tpl} abertura ${JSON.stringify(r.first_open)}`);
      if (onlyOpen || tpl !== templates[0]) continue;
      for (const name of ['demo', 'big']) {
        r[name] = await runBundle(name, src, edits);
        bench.log(`${name} ${['restart_engine', 'engine_open', 'in_memory', 'incremental'].map(k => k + ' p95 ' + r[name][k].total.p95).join(' | ')} | salto p95 ${r[name].jump.p95}`);
      }
      const act = [];
      for (let i = 0; i < 5; i++) {
        const d = await bench.call('start_activity', JSON.stringify({ difficulty: 'normal', duration_seconds: 30, target_fish: 3 }), true);
        act.push({ ms: d.total_ms, overlays: d.overlays });
      }
      r.activity = { start: stats(act.map(a => a.ms)), overlay_shown: act.every(a => a.overlays >= 1) };
      bench.log('minijogo ' + JSON.stringify(r.activity));
    }
    return results;
  };

  const q = new URLSearchParams(location.search);
  if (q.get('autorun')) {
    window.addEventListener('load', async () => {
      let out;
      try {
        out = await runBench({ engine: q.get('engine') || 'desconhecido', edits: Number(q.get('edits') || 20),
          templates: (q.get('templates') || 'web,web-lean').split(','), onlyOpen: q.get('only') === 'open' });
      } catch (e) {
        out = { engine: q.get('engine'), error: String(e && e.stack || e) };
      }
      await fetch(`/write/results-${q.get('engine') || 'desconhecido'}.json`, { method: 'PUT', body: JSON.stringify(out, null, 2) });
    });
  }
})();
