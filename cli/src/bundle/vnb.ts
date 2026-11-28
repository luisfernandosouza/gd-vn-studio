/**
 * Formato `.vnb` dos builds (Build System §5.2, §8.2; tarefa M5-03): cada arquivo da forma canônica
 * (`bundle.json`, `locales/<idioma>.json`, `plugins.json`, `licenses.json`) vira um binário com
 * cabeçalho de 60 bytes e o JSON canônico comprimido com Zstandard nível 19 e, em release, cifrado
 * com AES-256-CBC (padding PKCS#7, IV aleatório por arquivo).
 *
 * ```text
 * offset  tamanho  campo
 * 0       4        magia "VNB1"
 * 4       2        versão do formato (uint16 LE) = 1
 * 6       2        flags (bit 0 = conteúdo cifrado)
 * 8       32       SHA-256 do JSON canônico deste arquivo (bytes crus)
 * 40      4        tamanho do JSON descomprimido (uint32 LE)
 * 44      16       IV (zeros se não cifrado)
 * 60      n        corpo
 * ```
 *
 * O leitor do jogo é `runtime/vn_runtime/boot/vn_bundle_loader.gd` (`decode_vnb`); o
 * {@link decodeVnb} daqui faz as mesmas conferências, com os mesmos códigos (G001/G002, BS §13.1),
 * para ferramentas de diagnóstico e para os testes de ida e volta.
 *
 * Usa `node:zlib` (Zstandard) e `node:crypto` (AES), por isso fica fora da parte pura do compilador,
 * como o `write.ts`.
 */
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { constants as zc, zstdCompressSync, zstdDecompressSync } from 'node:zlib';
import type { CompiledBundle } from './compile.js';
import { sha256, sri } from './hash.js';
import { canonicalBytes } from './jcs.js';

export const VNB_MAGIC = 'VNB1';
export const VNB_VERSION = 1;
export const VNB_HEADER_SIZE = 60;
export const VNB_FLAG_ENCRYPTED = 1;
/** Nível do Zstandard nos builds (BS §5.2). */
export const VNB_ZSTD_LEVEL = 19;
/** Tamanho de `CONTENT_KEY` (AES-256) e do IV (bloco do AES). */
export const CONTENT_KEY_SIZE = 32;
export const VNB_IV_SIZE = 16;

/** Códigos do jogador (BS §13.1) para as mesmas falhas que o runtime recusa. */
export type VnbErrorCode = 'G001' | 'G002';

export class VnbError extends Error {
  constructor(
    readonly code: VnbErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'VnbError';
  }
}

export interface EncodeVnbOptions {
  /** `CONTENT_KEY` (32 bytes). Sem chave, o `.vnb` sai sem cifra (builds de debug, BS §11.1). */
  key?: Uint8Array | null;
  /** IV do arquivo. Padrão: 16 bytes aleatórios. Só os testes fixam. */
  iv?: Uint8Array;
  /** Nível do Zstandard. Padrão {@link VNB_ZSTD_LEVEL}. */
  level?: number;
}

/** `.vnb` dos bytes de um JSON canônico (BS §5.2). */
export function encodeVnb(json: Uint8Array, options: EncodeVnbOptions = {}): Uint8Array {
  if (json.length === 0) throw new RangeError('.vnb vazio: o JSON canônico nunca tem 0 bytes');
  if (json.length > 0xffffffff) throw new RangeError('.vnb acima de 4 GiB não cabe no cabeçalho');
  const key = options.key ?? null;
  if (key !== null && key.length !== CONTENT_KEY_SIZE)
    throw new RangeError(`CONTENT_KEY precisa de ${CONTENT_KEY_SIZE} bytes, veio com ${key.length}`);

  let body: Uint8Array = zstdCompressSync(json, {
    params: {
      [zc.ZSTD_c_compressionLevel]: options.level ?? VNB_ZSTD_LEVEL,
      [zc.ZSTD_c_checksumFlag]: 0,
    },
    pledgedSrcSize: json.length,
  });
  const iv = new Uint8Array(VNB_IV_SIZE);
  if (key !== null) {
    if (options.iv && options.iv.length !== VNB_IV_SIZE) throw new RangeError(`IV precisa de ${VNB_IV_SIZE} bytes`);
    iv.set(options.iv ?? randomBytes(VNB_IV_SIZE));
    const cipher = createCipheriv('aes-256-cbc', key, iv); // padding PKCS#7 é o padrão do OpenSSL
    body = Buffer.concat([cipher.update(body), cipher.final()]);
  }

  const out = new Uint8Array(VNB_HEADER_SIZE + body.length);
  const view = new DataView(out.buffer);
  out.set(new TextEncoder().encode(VNB_MAGIC), 0);
  view.setUint16(4, VNB_VERSION, true);
  view.setUint16(6, key !== null ? VNB_FLAG_ENCRYPTED : 0, true);
  out.set(sha256(json), 8);
  view.setUint32(40, json.length, true);
  out.set(iv, 44);
  out.set(body, VNB_HEADER_SIZE);
  return out;
}

export interface VnbHeader {
  version: number;
  flags: number;
  encrypted: boolean;
  /** SHA-256 do JSON canônico, em bytes crus. */
  hash: Uint8Array;
  /** Tamanho do JSON descomprimido. */
  size: number;
  iv: Uint8Array;
}

/** Cabeçalho de um `.vnb`. Lança {@link VnbError} G001 se não é `.vnb` ou a versão é desconhecida. */
export function readVnbHeader(raw: Uint8Array): VnbHeader {
  if (raw.length < VNB_HEADER_SIZE || new TextDecoder().decode(raw.subarray(0, 4)) !== VNB_MAGIC)
    throw new VnbError('G001', 'cabeçalho .vnb inválido');
  const view = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
  const version = view.getUint16(4, true);
  if (version !== VNB_VERSION) throw new VnbError('G001', `versão de formato .vnb ${version} desconhecida`);
  const flags = view.getUint16(6, true);
  return {
    version,
    flags,
    encrypted: (flags & VNB_FLAG_ENCRYPTED) !== 0,
    hash: raw.slice(8, 40),
    size: view.getUint32(40, true),
    iv: raw.slice(44, 60),
  };
}

export interface DecodedVnb extends VnbHeader {
  /** Bytes do JSON canônico. */
  json: Uint8Array;
}

/**
 * JSON de um `.vnb`, com as conferências do runtime (BS §5.2, §8.2): magia e versão, decifragem com
 * `key` quando a flag 0 está ligada, tamanho, hash do cabeçalho e, se dado, o hash esperado
 * (`CONTENT_HASHES`, em SRI). Lança {@link VnbError} com G001 ou G002.
 */
export function decodeVnb(raw: Uint8Array, key?: Uint8Array | null, expectedHash?: string): DecodedVnb {
  const header = readVnbHeader(raw);
  let body = raw.subarray(VNB_HEADER_SIZE);
  if (header.encrypted) {
    if (!key || key.length !== CONTENT_KEY_SIZE || body.length === 0 || body.length % 16 !== 0)
      throw new VnbError('G001', 'não foi possível decifrar');
    try {
      const d = createDecipheriv('aes-256-cbc', key, header.iv);
      body = Buffer.concat([d.update(body), d.final()]);
    } catch {
      throw new VnbError('G001', 'não foi possível decifrar');
    }
  }
  let json: Uint8Array;
  try {
    json = header.size > 0 ? zstdDecompressSync(body, { maxOutputLength: header.size }) : new Uint8Array();
  } catch {
    throw new VnbError('G001', 'corpo não descomprime');
  }
  if (header.size === 0 || json.length !== header.size) throw new VnbError('G001', 'corpo não descomprime');
  const actual = sha256(json);
  if (!equalBytes(actual, header.hash)) throw new VnbError('G002', 'hash diferente do cabeçalho');
  if (expectedHash !== undefined && sri(json) !== expectedHash)
    throw new VnbError('G002', 'hash diferente do build_config');
  return { ...header, json };
}

/** `CONTENT_KEY` nova: 32 bytes aleatórios a cada build (BS §8.1). */
export function generateContentKey(): Uint8Array {
  return new Uint8Array(randomBytes(CONTENT_KEY_SIZE));
}

/** Nome do `.vnb` de um arquivo da forma canônica (RT §2): `bundle.json` → `narrative.vnb`. */
export function vnbName(jsonPath: string): string {
  if (jsonPath === 'bundle.json') return 'narrative.vnb';
  if (!jsonPath.endsWith('.json')) throw new RangeError(`não é um arquivo do bundle: ${jsonPath}`);
  return jsonPath.slice(0, -'.json'.length) + '.vnb';
}

/** Os arquivos da forma canônica de um bundle compilado, com os bytes JCS, na ordem do `writeBundle`. */
export function bundleFiles(compiled: CompiledBundle): [string, Uint8Array][] {
  const files: [string, Uint8Array][] = [
    ['licenses.json', canonicalBytes(compiled.licenses)],
    ['bundle.json', canonicalBytes(compiled.bundle)],
  ];
  for (const [lang, doc] of Object.entries(compiled.locales)) files.push([`locales/${lang}.json`, canonicalBytes(doc)]);
  files.push(['plugins.json', canonicalBytes(compiled.plugins)]);
  return files;
}

export interface WriteVnbOptions {
  /** `CONTENT_KEY`. `null` grava sem cifra (debug). */
  key: Uint8Array | null;
  /** IV fixo para todos os arquivos. Só os testes usam: em build, cada arquivo tem o seu. */
  iv?: Uint8Array;
  level?: number;
}

/**
 * Grava o bundle em `.vnb` na pasta (a `vn_content/` do staging, BS §4.2): `narrative.vnb`,
 * `locales/<idioma>.vnb`, `plugins.vnb` e `licenses.vnb`. Devolve o `CONTENT_HASHES` do
 * `build_config.gd` (BS §4.4, §8.2): caminho de cada `.vnb`, relativo à pasta, → SHA-256 do JSON
 * canônico em SRI.
 */
export function writeVnbBundle(out: string, compiled: CompiledBundle, options: WriteVnbOptions): Record<string, string> {
  const hashes: Record<string, string> = {};
  for (const [jsonPath, json] of bundleFiles(compiled)) {
    const rel = vnbName(jsonPath);
    const path = join(out, rel);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, encodeVnb(json, { key: options.key, iv: options.iv, level: options.level }));
    hashes[rel] = sri(json);
  }
  return hashes;
}

function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}
