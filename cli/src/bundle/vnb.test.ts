// Formato .vnb (Build System §5.2, §8.2; tarefa M5-03). A ida e volta TS → Godot roda na CI
// (vnb-roundtrip.yml); aqui ficam o layout do cabeçalho, a cifra e as recusas do leitor.
import { createDecipheriv } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { zstdDecompressSync } from 'node:zlib';
import { afterAll, describe, expect, it } from 'vitest';
import { SPECS } from './fixtures.test-util.js';
import {
  VNB_HEADER_SIZE,
  VnbError,
  bundleFiles,
  canonicalBytes,
  compileProject,
  decodeVnb,
  encodeVnb,
  fromHex,
  generateContentKey,
  loadProject,
  readVnbHeader,
  sha256,
  sri,
  vnbName,
  writeVnbBundle,
} from './index.js';

const KEY = fromHex('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
const IV = fromHex('a0a1a2a3a4a5a6a7a8a9aaabacadaeaf');
const JSON_BYTES = canonicalBytes({ b: [1, 2.5, 'ç'], a: { z: null, y: true } });

const tmp = mkdtempSync(join(tmpdir(), 'vn-vnb-'));
afterAll(() => rmSync(tmp, { recursive: true, force: true }));

function code(f: () => unknown): string | undefined {
  try {
    f();
  } catch (e) {
    if (e instanceof VnbError) return e.code;
    throw e;
  }
  return undefined;
}

describe('cabeçalho (BS §5.2)', () => {
  it('magia, versão, flags, hash, tamanho e IV nos offsets da spec, little-endian', () => {
    const raw = encodeVnb(JSON_BYTES, { key: KEY, iv: IV });
    expect(Buffer.from(raw.subarray(0, 4)).toString('ascii')).toBe('VNB1');
    expect([...raw.subarray(4, 8)]).toEqual([1, 0, 1, 0]);
    expect(Buffer.from(raw.subarray(8, 40))).toEqual(Buffer.from(sha256(JSON_BYTES)));
    const size = JSON_BYTES.length;
    expect([...raw.subarray(40, 44)]).toEqual([size & 0xff, (size >> 8) & 0xff, (size >> 16) & 0xff, size >>> 24]);
    expect(Buffer.from(raw.subarray(44, 60))).toEqual(Buffer.from(IV));
    expect((raw.length - VNB_HEADER_SIZE) % 16).toBe(0);
  });

  it('sem chave: flag 0 desligada, IV zerado e corpo Zstandard puro', () => {
    const raw = encodeVnb(JSON_BYTES);
    const h = readVnbHeader(raw);
    expect(h.flags).toBe(0);
    expect(h.encrypted).toBe(false);
    expect([...h.iv]).toEqual(new Array(16).fill(0));
    expect(Buffer.from(zstdDecompressSync(raw.subarray(VNB_HEADER_SIZE)))).toEqual(Buffer.from(JSON_BYTES));
  });

  it('com chave: AES-256-CBC com PKCS#7 sobre o Zstandard, decifrável por um AES qualquer', () => {
    const raw = encodeVnb(JSON_BYTES, { key: KEY, iv: IV });
    const d = createDecipheriv('aes-256-cbc', KEY, IV);
    d.setAutoPadding(false);
    const plain = Buffer.concat([d.update(raw.subarray(VNB_HEADER_SIZE)), d.final()]);
    const pad = plain[plain.length - 1]!;
    expect(pad).toBeGreaterThanOrEqual(1);
    expect(pad).toBeLessThanOrEqual(16);
    expect([...plain.subarray(plain.length - pad)]).toEqual(new Array(pad).fill(pad));
    expect(Buffer.from(zstdDecompressSync(plain.subarray(0, plain.length - pad)))).toEqual(Buffer.from(JSON_BYTES));
  });

  it('IV aleatório por arquivo quando não é fixado', () => {
    const a = readVnbHeader(encodeVnb(JSON_BYTES, { key: KEY })).iv;
    const b = readVnbHeader(encodeVnb(JSON_BYTES, { key: KEY })).iv;
    expect(Buffer.from(a).equals(Buffer.from(b))).toBe(false);
  });

  it('recusa chave que não tem 32 bytes', () => {
    expect(() => encodeVnb(JSON_BYTES, { key: KEY.subarray(0, 16) })).toThrow(RangeError);
  });

  it('chave nova de 32 bytes a cada build (BS §8.1)', () => {
    const k = generateContentKey();
    expect(k.length).toBe(32);
    expect(Buffer.from(k).equals(Buffer.from(generateContentKey()))).toBe(false);
  });
});

describe('leitura e recusas (BS §8.2, §13.1)', () => {
  it('ida e volta com e sem cifra', () => {
    for (const key of [null, KEY]) {
      const d = decodeVnb(encodeVnb(JSON_BYTES, { key }), key, sri(JSON_BYTES));
      expect(Buffer.from(d.json)).toEqual(Buffer.from(JSON_BYTES));
    }
  });

  it('G001: magia errada, arquivo curto, versão desconhecida', () => {
    const raw = encodeVnb(JSON_BYTES);
    const bad = raw.slice();
    bad[0] = 0x58;
    expect(code(() => decodeVnb(bad))).toBe('G001');
    expect(code(() => decodeVnb(raw.subarray(0, 59)))).toBe('G001');
    const v2 = raw.slice();
    v2[4] = 2;
    expect(code(() => decodeVnb(v2))).toBe('G001');
  });

  it('G001: cifrado sem chave ou com a chave errada', () => {
    const raw = encodeVnb(JSON_BYTES, { key: KEY, iv: IV });
    expect(code(() => decodeVnb(raw))).toBe('G001');
    const other = KEY.slice();
    other[0] = other[0]! ^ 1;
    expect(code(() => decodeVnb(raw, other))).toBe('G001');
  });

  it('G001: corpo truncado ou tamanho do cabeçalho diferente', () => {
    const raw = encodeVnb(JSON_BYTES);
    expect(code(() => decodeVnb(raw.subarray(0, raw.length - 3)))).toBe('G001');
    const sized = raw.slice();
    sized[40] = (sized[40]! + 1) & 0xff;
    expect(code(() => decodeVnb(sized))).toBe('G001');
  });

  it('G002: hash do cabeçalho alterado ou diferente do build_config', () => {
    const raw = encodeVnb(JSON_BYTES);
    const h = raw.slice();
    h[8] = h[8]! ^ 0xff;
    expect(code(() => decodeVnb(h))).toBe('G002');
    expect(code(() => decodeVnb(raw, null, sri(new Uint8Array([1]))))).toBe('G002');
  });
});

describe('bundle da demo em .vnb', () => {
  const demo = join(SPECS, 'examples', 'demo-project');
  const fishing = join(SPECS, 'examples', 'fishing-plugin');
  const compiled = compileProject(loadProject(demo, { pluginDirs: [fishing] }));

  it('nomes da coluna da direita do RT §2', () => {
    expect(vnbName('bundle.json')).toBe('narrative.vnb');
    expect(vnbName('locales/pt-BR.json')).toBe('locales/pt-BR.vnb');
    expect(vnbName('plugins.json')).toBe('plugins.vnb');
    expect(vnbName('licenses.json')).toBe('licenses.vnb');
  });

  it('grava um .vnb por arquivo e devolve o CONTENT_HASHES que confere cada um', () => {
    const out = join(tmp, 'demo');
    const hashes = writeVnbBundle(out, compiled, { key: KEY });
    const files = bundleFiles(compiled);
    expect(Object.keys(hashes).sort()).toEqual(files.map(([p]) => vnbName(p)).sort());
    expect(hashes['narrative.vnb']).toBe(sri(canonicalBytes(compiled.bundle)));
    for (const [jsonPath, json] of files) {
      const rel = vnbName(jsonPath);
      const d = decodeVnb(readFileSync(join(out, rel)), KEY, hashes[rel]);
      expect(d.encrypted).toBe(true);
      expect(Buffer.from(d.json).equals(Buffer.from(json)), rel).toBe(true);
    }
  });

  it('debug: sem cifra, e o mesmo conteúdo dá os mesmos bytes', () => {
    const a = writeVnbBundle(join(tmp, 'dbg1'), compiled, { key: null });
    const b = writeVnbBundle(join(tmp, 'dbg2'), compiled, { key: null });
    expect(a).toEqual(b);
    for (const rel of Object.keys(a)) {
      const x = readFileSync(join(tmp, 'dbg1', rel));
      expect(readVnbHeader(x).encrypted).toBe(false);
      expect(x.equals(readFileSync(join(tmp, 'dbg2', rel)))).toBe(true);
    }
  });
});
