#!/usr/bin/env node
// Ida e volta do .vnb entre o compilador TypeScript e o runtime Godot (tarefa M5-03, Build System §5.2).
//
//   node cli/scripts/vnb_roundtrip.mjs prepare <pasta>   # TS: compila a demo e grava json/, release/, debug/
//   godot --headless --path runtime --script res://tests/boot/test_vnb_roundtrip.gd -- --vnb-dir <pasta>
//   node cli/scripts/vnb_roundtrip.mjs check <pasta>     # TS: lê os .vnb que o Godot gravou em godot/
//
// Precisa de `npm run build -w @vnstudio/cli` antes (importa de cli/dist/).
//
// <pasta>/json/          forma canônica do compilador TypeScript (bundle.json, locales/, plugins.json, licenses.json)
// <pasta>/release/       os mesmos arquivos em .vnb cifrado com uma CONTENT_KEY nova
// <pasta>/debug/         em .vnb sem cifra (build de debug, BS §11.1)
// <pasta>/build_config.json  as constantes do build_config.gd (BS §4.4) do release: chave em base64,
//                        CONTENT_HASH e CONTENT_HASHES
// <pasta>/godot/         .vnb gravados pelo Godot a partir de json/, com a mesma chave (passo do Godot)
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  base64,
  bundleFiles,
  canonicalBytes,
  compileProject,
  decodeVnb,
  generateContentKey,
  loadProject,
  encodeVnb,
  readVnbHeader,
  sri,
  vnbName,
  writeBundle,
  writeVnbBundle,
} from '../dist/bundle/index.js';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const SPECS = join(REPO, 'docs', 'specs');

function fail(msg) {
  console.error(`vnb_roundtrip: ${msg}`);
  process.exit(1);
}

function prepare(dir) {
  rmSync(dir, { recursive: true, force: true });
  const compiled = compileProject(
    loadProject(join(SPECS, 'examples', 'demo-project'), { pluginDirs: [join(SPECS, 'examples', 'fishing-plugin')] }),
  );
  writeBundle(join(dir, 'json'), compiled);
  const key = generateContentKey();
  const hashes = writeVnbBundle(join(dir, 'release'), compiled, { key });
  const debugHashes = writeVnbBundle(join(dir, 'debug'), compiled, { key: null });
  if (JSON.stringify(hashes) !== JSON.stringify(debugHashes)) fail('hashes do release e do debug diferem');
  writeFileSync(
    join(dir, 'build_config.json'),
    JSON.stringify(
      {
        BUILD_ID: 'vnb-roundtrip',
        DEBUG_BUILD: false,
        CONTENT_KEY: base64(key),
        CONTENT_HASH: compiled.bundle.content_hash,
        CONTENT_HASHES: hashes,
      },
      null,
      2,
    ),
  );
  // Arquivo de ~10 MB para a medição do BS §15 item 4: cenas sintéticas com texto variado, no formato do bundle.
  const lines = [];
  let seed = 12345;
  const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
  const words = ['praia', 'festival', 'peixe', 'mar', 'Alice', 'sol', 'rede', 'barco', 'vento', 'noite', 'ilha', 'onda'];
  let total = 0;
  for (let i = 0; total < 10 * 1024 * 1024; i++) {
    const text = Array.from({ length: 12 + Math.floor(rnd() * 20) }, () => words[Math.floor(rnd() * words.length)] + Math.floor(rnd() * 1000)).join(' ');
    const o = { id: `ev_${i}`, type: 'dialogue', speaker: 'alice', text, tags: [i % 7, i % 13], at: rnd() };
    total += JSON.stringify(o).length + 1;
    lines.push(o);
  }
  const big = canonicalBytes({ events: lines });
  writeFileSync(join(dir, 'big.vnb'), encodeVnb(big, { key }));
  writeFileSync(join(dir, 'big.json.size'), String(big.length));
  console.log(`TS → big.vnb: ${big.length} bytes de JSON`);
  for (const [rel, h] of Object.entries(hashes)) {
    const size = readFileSync(join(dir, 'release', rel)).length;
    console.log(`TS → ${rel}: ${size} bytes, ${h}`);
  }
}

function check(dir) {
  const cfg = JSON.parse(readFileSync(join(dir, 'build_config.json'), 'utf8'));
  const key = new Uint8Array(Buffer.from(cfg.CONTENT_KEY, 'base64'));
  const godot = join(dir, 'godot');
  const found = readdirSync(godot, { recursive: true, encoding: 'utf8' })
    .filter((f) => f.endsWith('.vnb'))
    .map((f) => f.split('\\').join('/'))
    .sort();
  const expected = Object.keys(cfg.CONTENT_HASHES).sort();
  if (JSON.stringify(found) !== JSON.stringify(expected))
    fail(`o Godot gravou ${found.join(', ')}; esperava ${expected.join(', ')}`);
  const json = new Map();
  for (const f of readdirSync(join(dir, 'json'), { recursive: true, encoding: 'utf8' }))
    if (f.endsWith('.json')) json.set(vnbName(f.split('\\').join('/')), readFileSync(join(dir, 'json', f)));
  for (const rel of found) {
    const raw = readFileSync(join(godot, rel));
    if (!readVnbHeader(raw).encrypted) fail(`${rel}: o Godot devia ter cifrado`);
    const d = decodeVnb(raw, key, cfg.CONTENT_HASHES[rel]);
    if (!Buffer.from(d.json).equals(json.get(rel))) fail(`${rel}: JSON diferente do que o TS compilou`);
    if (sri(d.json) !== cfg.CONTENT_HASHES[rel]) fail(`${rel}: hash`);
    console.log(`Godot → TS ok: ${relative(dir, join(godot, rel))}`);
  }
}

const [cmd, dir] = process.argv.slice(2);
if (!dir || !['prepare', 'check'].includes(cmd)) fail('uso: vnb_roundtrip.mjs prepare|check <pasta>');
mkdirSync(dir, { recursive: true });
if (cmd === 'prepare') prepare(resolve(dir));
else check(resolve(dir));
void bundleFiles;
