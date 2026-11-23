// Teste B dos assets (D18, PP §1.3), rodado dentro da página da bancada.
// Precisa de build/assets/ (tools/make_assets.py) e do servidor tools/serve.mjs (/swap e /rss).
// Com ?autorun=1&engine=<nome> (ver harness/index.html), grava build/work/results-<nome>.json.
(() => {
  const stats = xs => {
    if (!xs.length) return null;
    const s = [...xs].sort((a, b) => a - b);
    const q = p => s[Math.min(s.length - 1, Math.ceil(p * s.length) - 1)];
    return { n: s.length, p50: +q(0.5).toFixed(1), p95: +q(0.95).toFixed(1), max: +s[s.length - 1].toFixed(1), sum: +s.reduce((a, b) => a + b, 0).toFixed(0) };
  };
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const near = (a, b, tol) => a && b && a.every((v, i) => Math.abs(v - b[i]) <= tol);
  const mb = x => +(x / 1048576).toFixed(1);

  async function snap(label) {
    const st = await bench.call('assets_stats');
    const fw = document.getElementById('frame').contentWindow;
    const mem = fw.__vnWasmMemory;
    let rss = null;
    try { rss = await (await fetch('/rss')).json(); } catch (e) { /* servidor sem --rss */ }
    const pm = fw.performance && fw.performance.memory;
    const s = {
      label, wasm_mb: mem ? mb(mem.buffer.byteLength) : null, tex_mb: +st.tex_mb.toFixed(1),
      rss_mb: rss ? rss.mb : null, rss_processes: rss ? rss.processes : null,
      js_heap_mb: pm ? mb(pm.usedJSHeapSize) : null, cache_size: st.cache_size,
    };
    bench.log('memória ' + JSON.stringify(s));
    return s;
  }

  // Carrega uma lista de ids, um por vez, com show; para no primeiro erro.
  async function loadAll(map, ids, show, checkpoints, mem) {
    const rows = [];
    let error = null;
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i];
      let d;
      try { d = await bench.call('assets_load', id, show); } catch (e) { error = `${id}: ${e.message || JSON.stringify(e)}`; break; }
      const ext = map.assets[id].split('.').pop();
      const okMarker = map.kinds[id] !== 'image' || near(d.marker, map.markers[id], ext === 'png' ? 0 : 14);
      rows.push({ id, ext, total: d.total_ms, runtime: d.runtime_ms, fetch: d.fetch_ms, decode: d.decode_ms, upload: d.upload_ms, bytes: d.bytes, ok: okMarker });
      if (checkpoints.includes(i + 1)) mem.push(await snap(`${i + 1} carregados`));
      if ((i + 1) % 25 === 0) bench.log(`imagens ${i + 1}/${ids.length}, último ${d.total_ms.toFixed(0)} ms`);
    }
    const byExt = {};
    for (const ext of [...new Set(rows.map(r => r.ext))]) {
      const rs = rows.filter(r => r.ext === ext);
      byExt[ext] = {
        n: rs.length, mb_mean: +(rs.reduce((a, r) => a + r.bytes, 0) / rs.length / 1e6).toFixed(2),
        total: stats(rs.map(r => r.total)), fetch: stats(rs.map(r => r.fetch)), decode: stats(rs.map(r => r.decode)), upload: stats(rs.map(r => r.upload)),
      };
    }
    return {
      loaded: rows.length, of: ids.length, error, markers_ok: rows.every(r => r.ok),
      bad_markers: rows.filter(r => !r.ok).map(r => r.id), total_s: +(rows.reduce((a, r) => a + r.total, 0) / 1000).toFixed(1),
      total: stats(rows.map(r => r.total)), by_format: byExt,
    };
  }

  async function config(base, map, opts) {
    await bench.call('assets_config', base, JSON.stringify(map.assets), JSON.stringify(opts));
  }

  window.runAssets = async ({ engine, swaps = 20, maxImages = 0 }) => {
    const gl = document.createElement('canvas').getContext('webgl2');
    const ext = gl && gl.getExtension('WEBGL_debug_renderer_info');
    const renderer = gl ? (ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER)) : 'sem WebGL 2';
    const map = await (await fetch('/build/assets/map.json', { cache: 'no-store' })).json();
    // assets_base: no Studio é a URL /project/assets/ do vnpreview (PP §1.3); aqui, HTTP.
    const base = location.origin + '/build/assets/files/';
    const images = Object.keys(map.kinds).filter(k => map.kinds[k] === 'image').slice(0, maxImages || undefined);
    const music = Object.keys(map.kinds).filter(k => map.kinds[k] === 'music');
    const src = '/build/web/index.html';
    const r = { suite: 'assets', engine, userAgent: navigator.userAgent, renderer, files_mb: Object.fromEntries(Object.entries(map.bytes).map(([k, v]) => [k, +(v / 1e6).toFixed(1)])) };
    const step = (name) => { window.__benchProgress = name; bench.log('== ' + name); };

    // 1. Uso real: o cache guarda só os 16 últimos (LRU), e as 200 imagens passam pela tela uma a uma.
    step('lru');
    r.open_ms = +(await bench.open(src)).ms.toFixed(0);
    await config(base, map, { loader: 'js', max_cache: 16 });
    r.lru = { mem: [await snap('motor aberto')] };
    Object.assign(r.lru, await loadAll(map, images, true, [100, 200], r.lru.mem));
    bench.log('lru ' + JSON.stringify(r.lru.total));

    // 2. Teste B como a spec pede: 200 imagens e 30 músicas no cache ao mesmo tempo (motor novo).
    step('tudo no cache');
    await bench.open(src);
    await config(base, map, { loader: 'js', max_cache: 0 });
    r.all = { mem: [await snap('motor aberto')] };
    r.all.images = await loadAll(map, images, true, [50, 100, 150, 200], r.all.mem);
    bench.log('imagens ' + JSON.stringify(r.all.images.total) + ' erro ' + r.all.images.error);
    r.all.music = await loadAll(map, music, false, [music.length], r.all.mem);
    bench.log('músicas ' + JSON.stringify(r.all.music.total) + ' erro ' + r.all.music.error);
    await bench.call('assets_load', music[0], true);
    await sleep(1000);
    const p1 = (await bench.call('assets_stats')).music_pos;
    await sleep(2000);
    const p2 = (await bench.call('assets_stats')).music_pos;
    // posição avança ~2 s em 2 s se o áudio toca em tempo real (sem saída de som, alguns motores atrasam)
    r.all.music_plays = { position_s: +p2.toFixed(2), advanced_in_2s: +(p2 - p1).toFixed(2), playing: p2 > p1 };

    // 3. Troca de um asset em uso (preview.reload com /assets/<id>): o Studio grava o arquivo novo e manda a troca.
    step('troca');
    const swapOne = async (id, i) => {
      const v = map.swap[id][i % map.swap[id].length];
      const t0 = performance.now();
      await fetch(`/swap?target=${encodeURIComponent(map.assets[id].slice(map.prefix.length))}&source=${encodeURIComponent(v.file)}`, { method: 'POST' });
      const before = await bench.call('assets_stats');
      const d = await bench.call('assets_reload', id);
      return { total: performance.now() - t0, d, v, before };
    };
    const restore = async id => {
      await fetch(`/swap?target=${encodeURIComponent(map.assets[id].slice(map.prefix.length))}&source=${encodeURIComponent(map.restore[id])}`, { method: 'POST' });
      await bench.call('assets_reload', id);
    };
    const imgId = Object.keys(map.swap).find(k => map.kinds[k] === 'image');
    const musId = Object.keys(map.swap).find(k => map.kinds[k] === 'music');
    try {
      await bench.call('assets_load', imgId, true);
      const xs = [];
      for (let i = 0; i < swaps; i++) xs.push(await swapOne(imgId, i));
      r.swap_image = { id: imgId, total: stats(xs.map(x => x.total)), runtime: stats(xs.map(x => x.d.runtime_ms)), shown_new: xs.every(x => x.d.in_use && near(x.d.marker, x.v.marker, 0)) };
      await restore(imgId);
      await bench.call('assets_load', musId, true);
      await sleep(1000);
      const ys = [];
      for (let i = 0; i < Math.ceil(swaps / 2); i++) { await sleep(300); ys.push(await swapOne(musId, i)); }
      r.swap_music = {
        id: musId, total: stats(ys.map(x => x.total)), runtime: stats(ys.map(x => x.d.runtime_ms)),
        in_use: ys.every(x => x.d.in_use), new_length: ys.every(x => Math.abs(x.d.length - x.v.length) < 1),
        kept_position: ys.every(x => x.before.music_pos < 0 || Math.abs(x.d.music_pos - x.before.music_pos) < 1),
      };
      await restore(musId);
    } catch (e) { r.swap_error = String(e.message || JSON.stringify(e)); await restore(imgId).catch(() => {}); await restore(musId).catch(() => {}); }
    bench.log('troca ' + JSON.stringify([r.swap_image, r.swap_music]));

    // 4. Esvaziar o cache: a memória de texturas volta? E o heap do WASM?
    await bench.call('assets_clear');
    await sleep(500);
    r.all.mem.push(await snap('cache esvaziado'));

    // 5. Leitor HTTPRequest do Godot (em vez do fetch da página) e custo dos mipmaps, em 20 PNG.
    step('leitores');
    const pngs = images.filter(id => map.assets[id].endsWith('.png')).slice(0, 20);
    await config(base, map, { loader: 'http', max_cache: 4 });
    r.loader_http = await loadAll(map, pngs, true, [], []);
    await config(base, map, { loader: 'js', max_cache: 4 });
    r.loader_js = await loadAll(map, pngs, true, [], []);
    await config(base, map, { loader: 'js', max_cache: 4, mipmaps: true });
    r.mipmaps = await loadAll(map, pngs, true, [], []);
    // Referência: a própria página (sem o Godot) lendo os mesmos 20 PNG, com o motor aberto no iframe.
    const page = [];
    for (const id of pngs) {
      const t0 = performance.now();
      await (await fetch(base + map.assets[id].slice(map.prefix.length).split('/').map(encodeURIComponent).join('/'), { cache: 'no-store' })).arrayBuffer();
      page.push(performance.now() - t0);
    }
    r.page_fetch_png = stats(page);
    step('fim');
    return r;
  };
})();
