// Bancada do spike do Preview Web (proposta A).
//
// Sobe um servidor estático, abre a página da bancada (o "Studio") no Chromium
// e mede, para o bundle do demo e o bundle grande:
//   - primeira abertura do Preview, com e sem cache, por template;
//   - recarga depois de editar uma fala, em quatro caminhos acumulando as otimizações;
//   - salto para uma cena com variáveis (preview.start);
//   - início do minijogo de pesca com o GDScript real.
//
// Uso: node tools/bench.mjs [--edits 20] [--templates web,web-lean] [--out build/results.json]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, all) => (v.startsWith('--') ? a.concat([[v.slice(2), all[i + 1]]]) : a), []));
const EDITS = Number(args.edits || 20);
const TEMPLATES = (args.templates || 'web').split(',').filter(t => fs.existsSync(path.join(ROOT, 'build', t, 'index.html')));
const OUT = path.join(ROOT, args.out || 'build/results.json');

const TYPES = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.json': 'application/json', '.png': 'image/png' };
let cacheable = false;

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (req.method === 'PUT' && url.pathname.startsWith('/write/')) {
    const file = path.join(ROOT, 'build', 'work', url.pathname.slice(7));
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => { fs.writeFileSync(file, Buffer.concat(chunks)); res.end('ok'); });
    return;
  }
  const file = path.join(ROOT, decodeURIComponent(url.pathname));
  if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.statusCode = 404; return res.end(); }
  const big = file.endsWith('.wasm') || file.endsWith('.js') || file.endsWith('.pck');
  res.setHeader('Content-Type', TYPES[path.extname(file)] || 'application/octet-stream');
  res.setHeader('Cache-Control', cacheable && big ? 'public, max-age=31536000, immutable' : 'no-store');
  fs.createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const BASE = `http://127.0.0.1:${server.address().port}`;

const stats = xs => {
  const s = [...xs].sort((a, b) => a - b);
  const q = p => s[Math.min(s.length - 1, Math.ceil(p * s.length) - 1)];
  return { n: s.length, p50: +q(0.5).toFixed(1), p95: +q(0.95).toFixed(1), max: +s[s.length - 1].toFixed(1) };
};

const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const results = { machine: { cpus: os.cpus().length, cpu: os.cpus()[0].model, gpu: 'SwiftShader (sem GPU)' }, edits: EDITS, templates: {} };

for (const tpl of TEMPLATES) {
  const r = results.templates[tpl] = { wasm_mb: +(fs.statSync(path.join(ROOT, 'build', tpl, 'index.wasm')).size / 1e6).toFixed(1) };
  const src = `/build/${tpl}/index.html`;

  // Primeira abertura: sem cache (contexto novo, no-store) e com cache (mesmo contexto, segunda vez).
  cacheable = true;
  const ctx = await browser.newContext({ viewport: { width: 1300, height: 900 } });
  const page = await ctx.newPage();
  page.on('console', m => { if (m.type() === 'error') console.error('[página]', m.text()); });
  await page.goto(`${BASE}/harness/index.html`);
  const cold = await page.evaluate(s => bench.open(s), src);
  const warm = [];
  for (let i = 0; i < 5; i++) warm.push((await page.evaluate(s => bench.open(s), src)).ms);
  r.first_open = { cold_ms: +cold.ms.toFixed(0), warm: stats(warm), godot: cold.godot };
  console.log(tpl, 'abertura', r.first_open);
  if (tpl !== TEMPLATES[0]) { await ctx.close(); continue; }

  for (const name of ['demo', 'big']) {
    const b = `/build/bundles/${name}`;
    const loc = name === 'demo' ? 'pt-BR' : 'pt-BR';
    const res = r[name] = {};
    const setup = await page.evaluate(async ({ b, src }) => {
      await bench.open(src);
      const bundle = await (await fetch(b + '/bundle.json')).json();
      // cena e fala a editar: a primeira fala da cena com mais falas
      const scenes = Object.values(bundle.scenes).sort((x, y) => y.nodes.length - x.nodes.length);
      const scene = scenes[Math.floor(scenes.length / 2)];
      const lines = scene.nodes.filter(n => n.type === 'line');
      const node = lines[Math.floor(lines.length / 2)];
      window._b = { bundle, scene: scene.id, node: node.id };
      const first = await bench.call('load_url', b + '/bundle.json', 'pt-BR', '', true);
      await bench.call('start', scene.id, node.id, '');
      return { scene: scene.id, node: node.id, hash_ok: first.hash_ok, load: first };
    }, { b, src });
    res.hash_ok = setup.hash_ok;
    console.log(name, 'carga inicial', setup.load.total_ms.toFixed(0), 'ms; hash ok:', setup.hash_ok);

    const run = async (label, fn) => {
      const xs = await page.evaluate(fn, { b, src, edits: EDITS, label });
      res[label] = { total: stats(xs.map(x => x.total)), runtime: stats(xs.map(x => x.runtime)), studio: stats(xs.map(x => x.studio)), detail: xs[xs.length - 1].detail };
      console.log(name, label, JSON.stringify(res[label].total), 'runtime', JSON.stringify(res[label].runtime));
    };
    const edit = `const node = _b.bundle.scenes[_b.scene].nodes.find(n => n.id === _b.node); node.text = 'Edição ' + i + ': ' + node.text.replace(/^Edição \\d+: /, '');`;

    // 0. Ingênuo: a cada edição, Studio grava o bundle canônico e o Preview reinicia o motor.
    await run('restart_engine', new Function('{ b, src, edits }', `return (async () => { const out = [];
      for (let i = 0; i < edits; i++) { ${edit}
        const t0 = performance.now();
        const studio = await bench.writeCanonical(_b.bundle, 'bundle.json');
        await bench.open(src);
        const d = await bench.call('load_url', '/build/work/bundle.json', 'pt-BR', '', true);
        const s = await bench.call('start', _b.scene, _b.node, '');
        out.push({ total: performance.now() - t0, runtime: d.runtime_ms + s.runtime_ms, studio, detail: d });
      } return out; })()`));

    // 3. Motor sempre aberto: mesmo arquivo e hash, sem reiniciar o motor.
    await run('engine_open', new Function('{ b, src, edits }', `return (async () => { const out = [];
      for (let i = 0; i < edits; i++) { ${edit}
        const t0 = performance.now();
        const studio = await bench.writeCanonical(_b.bundle, 'bundle.json');
        const d = await bench.call('load_url', '/build/work/bundle.json', 'pt-BR', '', true);
        out.push({ total: performance.now() - t0, runtime: d.runtime_ms, studio, detail: d });
      } return out; })()`));

    // 2. + bundle em memória: sem arquivo e sem recalcular o hash no Preview.
    await run('in_memory', new Function('{ b, src, edits }', `return (async () => { const out = [];
      for (let i = 0; i < edits; i++) { ${edit}
        const t0 = performance.now();
        const text = JSON.stringify(_b.bundle);
        const studio = performance.now() - t0;
        const d = await bench.call('load_text', text, 'pt-BR', '', false);
        out.push({ total: performance.now() - t0, runtime: d.runtime_ms, studio, detail: d });
      } return out; })()`));

    // 1. + recarga incremental: só a cena alterada.
    await run('incremental', new Function('{ b, src, edits }', `return (async () => { const out = [];
      for (let i = 0; i < edits; i++) { ${edit}
        const t0 = performance.now();
        const text = JSON.stringify(_b.bundle.scenes[_b.scene]);
        const studio = performance.now() - t0;
        const d = await bench.call('patch_scene', text);
        out.push({ total: performance.now() - t0, runtime: d.runtime_ms, studio, detail: d });
      } return out; })()`));

    // Salto para cena com variáveis (preview.start).
    const jumps = await page.evaluate(async (edits) => {
      const ids = Object.keys(_b.bundle.scenes); const out = [];
      for (let i = 0; i < edits; i++) {
        const sc = _b.bundle.scenes[ids[(i * 7) % ids.length]];
        const line = sc.nodes.filter(n => n.type === 'line').pop() || sc.nodes[0];
        const d = await bench.call('start', sc.id, line.id, JSON.stringify({ 'global.player_money': 50 + i }));
        out.push(d.total_ms);
      } return out;
    }, EDITS);
    res.jump = stats(jumps);
    console.log(name, 'salto', JSON.stringify(res.jump));
  }

  // Minijogo de pesca com o GDScript real do plugin.
  const act = await page.evaluate(async () => {
    const out = [];
    for (let i = 0; i < 5; i++) {
      const d = await bench.call('start_activity', JSON.stringify({ difficulty: 'normal', duration_seconds: 30, target_fish: 3 }), true);
      out.push({ ms: d.total_ms, overlays: d.overlays });
    } return out;
  });
  r.activity = { start: stats(act.map(a => a.ms)), overlay_shown: act.every(a => a.overlays >= 1) };
  console.log('minijogo', JSON.stringify(r.activity));
  await page.screenshot({ path: path.join(ROOT, 'build', `screenshot-${tpl}.png`) });
  await ctx.close();
}

await browser.close();
server.close();
fs.writeFileSync(OUT, JSON.stringify(results, null, 2));
console.log('resultados em', OUT);
