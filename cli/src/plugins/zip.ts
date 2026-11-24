import { crc32, deflateRawSync, inflateRawSync } from 'node:zlib';

/**
 * ZIP mínimo para pacotes `.vnplugin` (Plugin SDK §2.1–§2.2): escrita reprodutível e leitura.
 * Sem ZIP64 (o pacote tem no máximo 100 MB) e sem pastas como entradas.
 */

export interface ZipEntry {
  /** Caminho com `/`, relativo à raiz do ZIP. */
  path: string;
  data: Uint8Array;
}

/** 1980-01-01 00:00:00 no formato DOS (Plugin SDK §2.2). */
const DOS_TIME = 0;
const DOS_DATE = (0 << 9) | (1 << 5) | 1;
/** Arquivo comum, rw-r--r--, criado em "Unix" (versão 2.0). */
const EXTERNAL_ATTRS = (0o100644 << 16) >>> 0;
const VERSION_MADE_BY = (3 << 8) | 20;
const VERSION_NEEDED = 20;
const FLAG_UTF8 = 1 << 11;

function compareBytes(a: string, b: string): number {
  return Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'));
}

/**
 * Empacotamento reprodutível: entradas em ordem lexicográfica (bytes UTF-8), data fixa 1980-01-01,
 * permissões normalizadas e deflate nível 9. A mesma árvore dá o mesmo arquivo.
 */
export function writeZip(entries: ZipEntry[]): Buffer {
  const sorted = [...entries].sort((a, b) => compareBytes(a.path, b.path));
  const locals: Buffer[] = [];
  const centrals: Buffer[] = [];
  let offset = 0;
  const seen = new Set<string>();
  for (const e of sorted) {
    if (seen.has(e.path)) throw new Error(`entrada repetida no ZIP: ${e.path}`);
    seen.add(e.path);
    const name = Buffer.from(e.path, 'utf8');
    const data = Buffer.from(e.data.buffer, e.data.byteOffset, e.data.byteLength);
    const compressed = deflateRawSync(data, { level: 9 });
    const crc = crc32(data);

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(VERSION_NEEDED, 4);
    local.writeUInt16LE(FLAG_UTF8, 6);
    local.writeUInt16LE(8, 8);
    local.writeUInt16LE(DOS_TIME, 10);
    local.writeUInt16LE(DOS_DATE, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(0, 28);
    locals.push(local, name, compressed);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(VERSION_MADE_BY, 4);
    central.writeUInt16LE(VERSION_NEEDED, 6);
    central.writeUInt16LE(FLAG_UTF8, 8);
    central.writeUInt16LE(8, 10);
    central.writeUInt16LE(DOS_TIME, 12);
    central.writeUInt16LE(DOS_DATE, 14);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(compressed.length, 20);
    central.writeUInt32LE(data.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt16LE(0, 30);
    central.writeUInt16LE(0, 32);
    central.writeUInt16LE(0, 34);
    central.writeUInt16LE(0, 36);
    central.writeUInt32LE(EXTERNAL_ATTRS, 38);
    central.writeUInt32LE(offset, 42);
    centrals.push(central, name);

    offset += local.length + name.length + compressed.length;
  }
  const centralSize = centrals.reduce((n, b) => n + b.length, 0);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(sorted.length, 8);
  end.writeUInt16LE(sorted.length, 10);
  end.writeUInt32LE(centralSize, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, ...centrals, end]);
}

export class ZipFormatError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ZipFormatError';
  }
}

/** Lê as entradas de um ZIP (métodos store e deflate). Pastas (nomes terminados em `/`) são ignoradas. */
export function readZip(input: Uint8Array): ZipEntry[] {
  const buf = Buffer.from(input.buffer, input.byteOffset, input.byteLength);
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 0xffff); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new ZipFormatError('não é um arquivo ZIP');
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const entries: ZipEntry[] = [];
  for (let n = 0; n < count; n++) {
    if (p + 46 > buf.length || buf.readUInt32LE(p) !== 0x02014b50) throw new ZipFormatError('diretório central inválido');
    const method = buf.readUInt16LE(p + 10);
    const crc = buf.readUInt32LE(p + 16);
    const compSize = buf.readUInt32LE(p + 20);
    const size = buf.readUInt32LE(p + 24);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const localOffset = buf.readUInt32LE(p + 42);
    const path = buf.toString('utf8', p + 46, p + 46 + nameLen);
    p += 46 + nameLen + extraLen + commentLen;
    if (path.endsWith('/')) continue;
    if (localOffset + 30 > buf.length || buf.readUInt32LE(localOffset) !== 0x04034b50) {
      throw new ZipFormatError(`cabeçalho local inválido: ${path}`);
    }
    const start = localOffset + 30 + buf.readUInt16LE(localOffset + 26) + buf.readUInt16LE(localOffset + 28);
    const raw = buf.subarray(start, start + compSize);
    let data: Buffer;
    if (method === 0) data = Buffer.from(raw);
    else if (method === 8) data = inflateRawSync(raw);
    else throw new ZipFormatError(`método de compressão ${method} não suportado: ${path}`);
    if (data.length !== size || crc32(data) !== crc) throw new ZipFormatError(`CRC ou tamanho errado: ${path}`);
    entries.push({ path, data });
  }
  return entries;
}
