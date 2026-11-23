// Servidor estático da bancada: serve spikes/preview-web/ e aceita PUT em /write/<arquivo>
// (grava em build/work/). Uso: node tools/serve.mjs [porta] [--cache] [--rss <regex>]
//
// Teste B dos assets: POST /swap?target=<rel>&source=<rel> copia um arquivo por cima de
// outro em build/assets/files/ (o autor salvou o asset de novo), e GET /rss devolve a
// memória residente (MB) somada dos processos cujo nome casa com --rss (o motor do webview).
import http from 'node:http';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const TYPES = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.ogg': 'audio/ogg', '.mp3': 'audio/mpeg' };
const ASSETS = path.join(ROOT, 'build', 'assets', 'files');
const rssArg = process.argv.indexOf('--rss');
const RSS = rssArg > 0 ? new RegExp(process.argv[rssArg + 1], 'i') : null;

function rssMB() {
  if (!RSS) return null;
  let procs;
  if (process.platform === 'win32') {
    const out = execSync('powershell -NoProfile -Command "Get-Process | Select-Object ProcessName,WorkingSet64 | ConvertTo-Json -Compress"', { maxBuffer: 1 << 26 }).toString();
    procs = JSON.parse(out).map(p => ({ name: p.ProcessName, kb: p.WorkingSet64 / 1024 }));
  } else {
    procs = execSync('ps -A -o rss=,comm=', { maxBuffer: 1 << 26 }).toString().trim().split('\n')
      .map(l => l.trim().match(/^(\d+)\s+(.*)$/)).filter(Boolean).map(m => ({ name: m[2], kb: Number(m[1]) }));
  }
  const hit = procs.filter(p => RSS.test(p.name));
  return { mb: +(hit.reduce((a, p) => a + p.kb, 0) / 1024).toFixed(1), processes: hit.length };
}
const port = Number(process.argv[2] || 8765);
const cacheable = process.argv.includes('--cache');

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (req.method === 'PUT' && url.pathname.startsWith('/write/')) {
    const file = path.join(ROOT, 'build', 'work', path.basename(url.pathname));
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => { fs.writeFileSync(file, Buffer.concat(chunks)); res.end('ok'); });
    return;
  }
  if (url.pathname === '/rss') {
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify(rssMB()));
  }
  if (req.method === 'POST' && url.pathname === '/swap') {
    const target = path.join(ASSETS, url.searchParams.get('target'));
    const source = path.join(ASSETS, url.searchParams.get('source'));
    if (!target.startsWith(ASSETS) || !source.startsWith(ASSETS)) { res.statusCode = 400; return res.end(); }
    fs.copyFileSync(source, target);
    return res.end('ok');
  }
  const file = path.join(ROOT, decodeURIComponent(url.pathname));
  if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.statusCode = 404; return res.end(); }
  const big = /\.(wasm|js|pck)$/.test(file);
  res.setHeader('Content-Type', TYPES[path.extname(file)] || 'application/octet-stream');
  res.setHeader('Cache-Control', cacheable && big ? 'public, max-age=31536000, immutable' : 'no-store');
  fs.createReadStream(file).pipe(res);
}).listen(port, '127.0.0.1', () => console.log(`servindo ${ROOT} em http://127.0.0.1:${port}`));
