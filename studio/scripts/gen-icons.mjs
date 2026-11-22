// Gera os ícones do app em src-tauri/icons/ (fora do Git).
// O repositório do produto não guarda imagens fora das pastas da spec 09 §1.1 (decisão D22),
// então o ícone provisório é um quadrado de cor sólida gerado aqui, e o `tauri icon` deriva
// os formatos de cada sistema (.ico, .icns, .png). O ícone definitivo chega com a identidade visual.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';

const studio = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(studio, 'src-tauri', 'icons');
const force = process.argv.includes('--force');

if (!force && existsSync(join(out, 'icon.ico')) && existsSync(join(out, 'icon.icns'))) {
  console.log('Ícones já existem em src-tauri/icons/ (use --force para gerar de novo).');
  process.exit(0);
}

const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = (buf) => {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type, data) => {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
};

/** PNG RGBA de tamanho `size`, cor sólida com uma borda mais escura. */
function solidPng(size, [r, g, b]) {
  const border = Math.round(size / 16);
  const rows = [];
  for (let y = 0; y < size; y++) {
    const row = Buffer.alloc(1 + size * 4);
    for (let x = 0; x < size; x++) {
      const edge = x < border || y < border || x >= size - border || y >= size - border;
      const k = edge ? 0.7 : 1;
      row.set([Math.round(r * k), Math.round(g * k), Math.round(b * k), 255], 1 + x * 4);
    }
    rows.push(row);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr.set([8, 6, 0, 0, 0], 8);
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(Buffer.concat(rows))),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const source = join(tmpdir(), `vnstudio-icon-${process.pid}.png`);
writeFileSync(source, solidPng(1024, [94, 92, 230]));
mkdirSync(out, { recursive: true });
const bin = join(studio, 'node_modules', '.bin', process.platform === 'win32' ? 'tauri.cmd' : 'tauri');
execFileSync(bin, ['icon', source, '--output', out], {
  cwd: studio,
  stdio: 'inherit',
  shell: process.platform === 'win32',
});
console.log(`Ícones gerados em ${out}`);
