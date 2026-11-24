import { NetworkError } from './errors.js';
import { decodeJson, type HttpGet } from './http.js';

/**
 * URL fixa do índice oficial, o `catalog:official` do v1 (Plugin SDK §13.2, decisão D11).
 * O índice mora em `catalog/official.json` no monorepo (spec 09 §1).
 */
export const OFFICIAL_CATALOG_URL =
  'https://raw.githubusercontent.com/luisfernandosouza/gd-vn-studio/main/catalog/official.json';

/** Uma versão no índice (Plugin SDK §13.2). No v1 toda versão tem `state: published` e `trust: official`. */
export interface CatalogVersion {
  version: string;
  url: string;
  integrity: string;
  state: 'draft' | 'review' | 'published';
  trust: 'official' | 'reviewed';
  /** Presente quando a versão foi retirada (§13.3), com o motivo. */
  revoked?: { reason: string };
}

export interface CatalogEntry {
  id: string;
  namespace: string;
  versions: CatalogVersion[];
}

export interface CatalogIndex {
  catalog_version: 1;
  plugins: CatalogEntry[];
}

export class CatalogFormatError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CatalogFormatError';
  }
}

/** Confere a forma do índice. O índice é escrito pela CI de release, mas chega pela rede. */
export function parseCatalog(raw: unknown): CatalogIndex {
  const bad = (m: string): never => {
    throw new CatalogFormatError(`índice do catálogo inválido: ${m}`);
  };
  if (typeof raw !== 'object' || raw === null) return bad('não é um objeto');
  const idx = raw as Partial<CatalogIndex>;
  if (idx.catalog_version !== 1) bad('catalog_version deve ser 1');
  if (!Array.isArray(idx.plugins)) return bad('plugins deve ser uma lista');
  for (const p of idx.plugins) {
    if (typeof p?.id !== 'string' || typeof p.namespace !== 'string' || !Array.isArray(p.versions)) {
      bad(`entrada sem id, namespace ou versions`);
    }
    for (const v of p.versions) {
      if (typeof v?.version !== 'string' || typeof v.url !== 'string' || typeof v.integrity !== 'string') {
        bad(`${p.id}: versão sem version, url ou integrity`);
      }
    }
  }
  return idx as CatalogIndex;
}

/** Baixa o índice. Sem rede, `NetworkError` (quem chama decide: B015 no build, erro na instalação). */
export async function fetchCatalog(http: HttpGet, url: string = OFFICIAL_CATALOG_URL): Promise<CatalogIndex> {
  const res = await http(url, { Accept: 'application/json' });
  if (res.status !== 200) throw new NetworkError(`o índice ${url} respondeu ${res.status}`);
  try {
    return parseCatalog(decodeJson(res.body));
  } catch (err) {
    if (err instanceof CatalogFormatError) throw err;
    throw new CatalogFormatError(`índice do catálogo não é JSON: ${(err as Error).message}`);
  }
}

export function findCatalogVersion(index: CatalogIndex, id: string, version: string): CatalogVersion | undefined {
  return index.plugins.find((p) => p.id === id)?.versions.find((v) => v.version === version);
}

/** Versões instaláveis: `published` e não revogadas (§13.2, §13.3: "uma versão revoked não é instalada"). */
export function installableVersions(entry: CatalogEntry): CatalogVersion[] {
  return entry.versions.filter((v) => v.state === 'published' && !v.revoked);
}
