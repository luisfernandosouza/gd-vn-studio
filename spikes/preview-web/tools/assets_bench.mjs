// Teste B dos assets no Chromium, no Edge (motor do WebView2) ou no WebKit do Playwright.
// Sobe tools/serve.mjs com --rss (memória dos processos do navegador), abre a página da
// bancada com ?autorun=1&suite=assets e espera build/work/results-<engine>.json.
//
// Uso: node tools/assets_bench.mjs [--browser chromium|webkit] [--channel msedge] [--gpu]
//                                  [--rss <regex>] [--swaps 20] [--out build/results-assets.json]
// Antes: tools/export.sh e python3 tools/make_assets.py build/assets
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const pw = createRequire(import.meta.url)('playwright');

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, all) => (v.startsWith('--') ? a.concat([[v.slice(2), all[i + 1]]]) : a), []));
const BROWSER = args.browser || 'chromium';
const GPU = 'gpu' in args;
const engine = args.channel || BROWSER;
const RSS = args.rss || (args.channel === 'msedge' ? '^msedge' : BROWSER === 'chromium' ? 'chrom|headless_shell' : 'WebKit|pw_run');
const OUT = path.join(ROOT, args.out || `build/results-assets-${engine}.json`);
const port = 8790 + Math.floor(Math.random() * 100);

const server = spawn(process.execPath, [path.join(ROOT, 'tools', 'serve.mjs'), String(port), '--cache', '--rss', RSS], { stdio: 'inherit' });
await new Promise(r => setTimeout(r, 800));

const launchArgs = BROWSER === 'chromium'
  ? ['--autoplay-policy=no-user-gesture-required', ...(GPU ? ['--ignore-gpu-blocklist', '--enable-gpu'] : ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'])]
  : [];
const browser = await pw[BROWSER].launch({ args: launchArgs, headless: !GPU || BROWSER !== 'chromium', ...(args.channel ? { channel: args.channel } : {}) });
const page = await (await browser.newContext({ viewport: { width: 1300, height: 900 } })).newPage();
page.on('console', m => { const t = m.text(); if (m.type() === 'error' || t.startsWith('memória') || t.startsWith('==')) console.log('[página]', t); });
page.on('crash', () => console.error('[página] o processo da página caiu'));

const result = path.join(ROOT, 'build', 'work', `results-${engine}.json`);
fs.rmSync(result, { force: true });
await page.goto(`http://127.0.0.1:${port}/harness/index.html?autorun=1&suite=assets&engine=${engine}&edits=${args.swaps || 20}`);
const t0 = Date.now();
let last = '';
while (!fs.existsSync(result) && Date.now() - t0 < 40 * 60 * 1000) {
  await new Promise(r => setTimeout(r, 2000));
  const p = await page.evaluate(() => window.__benchProgress).catch(() => 'página fora do ar');
  if (p !== last) { console.log('etapa:', p); last = p; }
  if (p === 'página fora do ar') break;
}
const out = fs.existsSync(result) ? JSON.parse(fs.readFileSync(result, 'utf8')) : { engine, error: 'sem resultado (tempo esgotado ou página caiu)', progress: last };
out.machine = { cpus: os.cpus().length, cpu: os.cpus()[0].model, mem_gb: +(os.totalmem() / 1e9).toFixed(1), platform: os.platform(), arch: os.arch() };
out.browser = BROWSER; out.channel = args.channel || null; out.gpu = GPU; out.rss_match = RSS;
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(out, null, 2));
console.log('gravado em', OUT);
await browser.close();
server.kill();
