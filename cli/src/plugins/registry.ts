import { readFile } from 'node:fs/promises';
import { relative, sep } from 'node:path';
import type { PluginManifest } from '@vnstudio/plugin-schema';
import type { PluginCache } from './cache.js';
import { fetchCatalog, installableVersions, OFFICIAL_CATALOG_URL, type CatalogIndex } from './catalog.js';
import { tokenHelp, type TokenProvider } from './credentials.js';
import { DependencyError, issue, NetworkError } from './errors.js';
import { downloadReleaseAsset, GithubAccessError, listReleases } from './github.js';
import type { HttpGet } from './http.js';
import { integrityMatches, sriSha256 } from './integrity.js';
import { readPackageManifest as readManifestRaw } from './pack.js';
import { inspectLocalPath, parseSource } from './source.js';

export type Trust = 'official' | 'reviewed' | 'local';

/** Uma versão de um plugin que a origem oferece. O pacote só é carregado quando ela é escolhida. */
export interface Candidate {
  version: string;
  /** O `resolved` do lock: URL, ou `path:<relativo ao projeto>`. */
  resolved: string;
  trust: Trust;
  embedded?: boolean;
  /** Hash conhecido antes de baixar (catálogo). */
  integrity?: string;
}

export interface LoadedPackage {
  manifest: PluginManifest;
  /** Ausente só no plugin embutido (o build calcula, BS §3.2 passo 4). */
  integrity?: string;
}

export interface RegistryOptions {
  projectDir: string;
  http: HttpGet;
  cache: PluginCache;
  githubToken: TokenProvider;
  catalogUrl?: string;
}

/**
 * Lista e carrega versões das quatro origens do Repo §3.1. Guarda em memória o índice e as Releases já
 * lidos, para uma resolução não pedir o mesmo duas vezes.
 */
function readPackageManifest(data: Uint8Array, id?: string): PluginManifest {
  try {
    return readManifestRaw(data);
  } catch (err) {
    throw new DependencyError([
      issue('bad-package', `O pacote do plugin ${id ?? ''} está corrompido ou não é um .vnplugin.`, {
        ...(id ? { plugin: id } : {}),
        details: (err as Error).message,
      }),
    ]);
  }
}

export class Registry {
  private catalog?: Promise<CatalogIndex>;
  private readonly lists = new Map<string, Promise<Candidate[]>>();
  private readonly githubAssets = new Map<string, string>();

  constructor(private readonly opts: RegistryOptions) {}

  official(): Promise<CatalogIndex> {
    this.catalog ??= fetchCatalog(this.opts.http, this.opts.catalogUrl ?? OFFICIAL_CATALOG_URL);
    return this.catalog;
  }

  candidates(id: string, source: string): Promise<Candidate[]> {
    const key = `${id} ${source}`;
    let p = this.lists.get(key);
    if (!p) {
      p = this.list(id, source);
      this.lists.set(key, p);
    }
    return p;
  }

  private async list(id: string, source: string): Promise<Candidate[]> {
    const src = parseSource(source);
    if (src.kind === 'catalog') {
      const index = await this.network(id, () => this.official());
      const entry = index.plugins.find((p) => p.id === id);
      if (!entry) throw new DependencyError([issue('not-found', `O plugin ${id} não está no catálogo oficial.`, { plugin: id })]);
      return installableVersions(entry).map((v) => ({
        version: v.version,
        resolved: v.url,
        integrity: v.integrity,
        trust: v.trust,
      }));
    }
    if (src.kind === 'github') {
      const repo = `${src.owner}/${src.repo}`;
      const token = await this.opts.githubToken();
      const releases = await this.network(id, () => listReleases(this.opts.http, src.owner, src.repo, id, token), repo);
      for (const r of releases) this.githubAssets.set(r.asset.downloadUrl, repo);
      return releases.map((r) => ({ version: r.version, resolved: r.asset.downloadUrl, trust: 'local' as const }));
    }
    const local = await inspectLocalPath(this.opts.projectDir, src.path, id);
    const resolved = `path:${relative(this.opts.projectDir, local.kind === 'vendored' ? local.file : local.root).split(sep).join('/')}`;
    if (local.kind === 'embedded') {
      return [{ version: local.manifest.version, resolved, trust: 'local', embedded: true }];
    }
    const manifest = readPackageManifest(await readFile(local.file), id);
    return [{ version: manifest.version, resolved, trust: 'local' }];
  }

  /**
   * Carrega o pacote de um candidato: do cache, do repositório ou da rede. `expected` é o `integrity` que
   * o lock já tinha para esta mesma versão; pacote diferente dele (ou do catálogo) é B002.
   */
  async load(id: string, cand: Candidate, expected?: string): Promise<LoadedPackage> {
    const want = expected ?? cand.integrity;
    if (cand.resolved.startsWith('path:')) {
      const local = await inspectLocalPath(this.opts.projectDir, cand.resolved.slice(5), id);
      if (local.kind === 'embedded') return { manifest: local.manifest };
      const data = await readFile(local.file);
      this.verify(id, cand.version, data, want);
      return { manifest: readPackageManifest(data, id), integrity: sriSha256(data) };
    }
    let data: Uint8Array | undefined = want ? await this.opts.cache.get(id, cand.version, want) : undefined;
    if (!data) {
      const repo = this.githubAssets.get(cand.resolved);
      const token = repo ? await this.opts.githubToken() : undefined;
      data = await this.network(id, () => downloadReleaseAsset(this.opts.http, cand.resolved, token), repo);
      this.verify(id, cand.version, data, want);
      await this.opts.cache.put(id, cand.version, data);
    }
    return { manifest: readPackageManifest(data, id), integrity: sriSha256(data) };
  }

  private verify(id: string, version: string, data: Uint8Array, want: string | undefined): void {
    if (want && !integrityMatches(data, want)) {
      throw new DependencyError([
        issue('integrity', `O arquivo do plugin ${id} não é o mesmo que foi instalado. Reinstale o plugin pelo Gerenciador de plugins.`, {
          plugin: id,
          version,
          details: `esperado ${want}, obtido ${sriSha256(data)}`,
        }),
      ]);
    }
  }

  private async network<T>(id: string, fn: () => Promise<T>, repo?: string): Promise<T> {
    try {
      return await fn();
    } catch (err) {
      if (err instanceof GithubAccessError) {
        throw new DependencyError([issue('token-required', tokenHelp(err.repo), { plugin: id, details: err.message })]);
      }
      if (err instanceof NetworkError) {
        throw new DependencyError([
          issue('network', `Não foi possível baixar o plugin ${id}${repo ? ` de ${repo}` : ''}. Verifique a internet e tente de novo.`, {
            plugin: id,
            details: err.message,
          }),
        ]);
      }
      throw err;
    }
  }
}
