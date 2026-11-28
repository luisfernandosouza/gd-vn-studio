#!/usr/bin/env node
// Runner Web dos vetores de conformidade (spec 08 §4, tarefa M4-03).
//
// Roda o mesmo executor do nativo (`res://tests/vn_test_runner.gd`) no export Web sem threads do
// runtime (preset "Web (vetores)", BS §7.3), num Chromium headless do Playwright, sobre os mesmos
// arquivos de `docs/specs/conformance/`. Pega diferenças do WebAssembly e da ponte JavaScript.
//
// Uso: node runtime/tests/web/run_web_vectors.cjs <pasta-do-export> <pasta-ou-arquivo-de-casos>[#<id>]
// Saída: a do executor (`FALHOU <arquivo>#<id>`, resumo `N/M`), com o mesmo código de saída:
// 0 sem falhas, 1 com falha, 2 com erro de uso; 3 quando o runtime Web não chegou ao fim.
// `VN_WEB_TIMEOUT_MS` muda o limite de espera (padrão 300000).
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const MOUNT = '/vn_cases';  // pasta dos casos no sistema de arquivos em memória do motor
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.json': 'application/json', '.png': 'image/png',
};

function usage(msg) {
  if (msg) console.error(msg);
  console.error('uso: node runtime/tests/web/run_web_vectors.cjs <pasta-do-export> <pasta-ou-arquivo-de-casos>[#<id>]');
  process.exit(2);
}

// Mesma regra do executor nativo (_case_files): um arquivo, ou os *.json do primeiro nível da pasta.
function caseIndex(arg) {
  let target = arg;
  let id = '';
  const hash = target.lastIndexOf('#');
  if (hash > 0) { id = target.slice(hash + 1); target = target.slice(0, hash); }
  target = path.resolve(target);
  if (!fs.existsSync(target)) usage(`--vn-test: nenhum arquivo de casos em ${target}`);
  const isDir = fs.statSync(target).isDirectory();
  const dir = isDir ? target : path.dirname(target);
  const files = isDir
    ? fs.readdirSync(dir).filter((f) => f.endsWith('.json') && fs.statSync(path.join(dir, f)).isFile()).sort()
    : [path.basename(target)];
  if (files.length === 0) usage(`--vn-test: nenhum arquivo de casos em ${target}`);
  const inner = isDir ? MOUNT : `${MOUNT}/${path.basename(target)}`;
  return { dir, files, page: { dir: MOUNT, files, target: id ? `${inner}#${id}` : inner } };
}

function serve(exportDir, cases) {
  const page = fs.readFileSync(path.join(__dirname, 'vectors.html'));
  const send = (res, file) => {
    res.setHeader('Content-Type', TYPES[path.extname(file)] || 'application/octet-stream');
    res.setHeader('Cache-Control', 'no-store');
    fs.createReadStream(file).pipe(res);
  };
  const inside = (root, rel) => {
    const file = path.resolve(root, '.' + path.posix.normalize('/' + rel));
    return file.startsWith(root + path.sep) && fs.existsSync(file) && fs.statSync(file).isFile() ? file : null;
  };
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const p = decodeURIComponent(url.pathname);
    let file = null;
    if (p === '/' || p === '/index.html') {
      res.setHeader('Content-Type', TYPES['.html']);
      return res.end(page);
    }
    if (p === '/cases.json') {
      res.setHeader('Content-Type', TYPES['.json']);
      return res.end(JSON.stringify(cases.page));
    }
    if (p.startsWith('/export/')) file = inside(exportDir, p.slice('/export/'.length));
    else if (p.startsWith('/cases/') && cases.files.includes(p.slice('/cases/'.length))) file = path.join(cases.dir, p.slice('/cases/'.length));
    if (!file) { res.statusCode = 404; return res.end(); }
    send(res, file);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

async function main() {
  const [exportArg, casesArg] = process.argv.slice(2);
  if (!exportArg || !casesArg) usage();
  const exportDir = path.resolve(exportArg);
  for (const f of ['index.js', 'index.wasm', 'index.pck']) {
    if (!fs.existsSync(path.join(exportDir, f))) usage(`run_web_vectors: falta ${f} em ${exportDir} (exporte o preset "Web (vetores)")`);
  }
  const cases = caseIndex(casesArg);
  const { chromium } = require('playwright');
  const server = await serve(exportDir, cases);
  const browser = await chromium.launch();
  const timeout = Number(process.env.VN_WEB_TIMEOUT_MS || 300000);
  let code = 3;
  try {
    const pg = await browser.newPage();
    pg.on('pageerror', (e) => console.error(`run_web_vectors: erro na página: ${e.message}`));
    await pg.goto(`http://127.0.0.1:${server.address().port}/`);
    await pg.waitForFunction(() => window.vnWeb && (window.vnWeb.exit !== null || window.vnWeb.fatal !== null), null, { timeout, polling: 200 });
    const r = await pg.evaluate(() => window.vnWeb);
    for (const l of r.lines) console.log(l);
    for (const l of r.errors) console.error(l);
    if (r.fatal) console.error(`run_web_vectors: o runtime Web não abriu: ${r.fatal}`);
    else code = r.exit;
    const ua = await pg.evaluate(() => navigator.userAgent);
    console.log(`navegador: ${ua}`);
  } catch (e) {
    console.error(`run_web_vectors: ${e.message}`);
  } finally {
    await browser.close();
    server.close();
  }
  process.exit(code);
}

main();
