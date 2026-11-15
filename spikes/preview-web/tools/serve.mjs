// Servidor estático da bancada: serve spikes/preview-web/ e aceita PUT em /write/<arquivo>
// (grava em build/work/). Uso: node tools/serve.mjs [porta] [--cache]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const TYPES = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.json': 'application/json', '.png': 'image/png' };
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
  const file = path.join(ROOT, decodeURIComponent(url.pathname));
  if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.statusCode = 404; return res.end(); }
  const big = /\.(wasm|js|pck)$/.test(file);
  res.setHeader('Content-Type', TYPES[path.extname(file)] || 'application/octet-stream');
  res.setHeader('Cache-Control', cacheable && big ? 'public, max-age=31536000, immutable' : 'no-store');
  fs.createReadStream(file).pipe(res);
}).listen(port, '127.0.0.1', () => console.log(`servindo ${ROOT} em http://127.0.0.1:${port}`));
