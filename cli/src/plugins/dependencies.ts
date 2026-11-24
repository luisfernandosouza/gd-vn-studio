import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { PluginLock } from '@vnstudio/plugin-schema';
import type { PluginCache } from './cache.js';
import { fetchCatalog, findCatalogVersion, OFFICIAL_CATALOG_URL, type CatalogIndex } from './catalog.js';
import { tokenHelp, type TokenProvider } from './credentials.js';
import { DependencyError, issue, NetworkError, type DependencyIssue } from './errors.js';
import { downloadReleaseAsset, GithubAccessError } from './github.js';
import type { HttpGet } from './http.js';
import { integrityMatches, sriSha256 } from './integrity.js';
import { packPluginFolder } from './pack.js';
import { findEmbeddedPlugin, inspectLocalPath, projectPath } from './source.js';
import type { LockEntry } from './resolver.js';

export const LOCK_FILE = 'plugin-lock.json';
export const LOCAL_LOCK_FILE = join('.vnstudio', 'plugin-lock.local.json');

/** Um plugin pronto para o staging (BS §4.5). */
export interface PreparedPlugin {
  id: string;
  version: string;
  namespace: string;
  trust: LockEntry['trust'];
  /** Hash do pacote usado; no embutido, o calculado no build, que vai para o manifesto (BS §9.2). */
  integrity?: string;
  from: 'cache' | 'download' | 'vendored' | 'embedded' | 'link';
  /** O `.vnplugin` (ausente só no vínculo, que é lido da pasta). */
  package?: Uint8Array;
  /** Pasta `vn_plugins/<namespace>/` do vínculo ou do embutido. */
  folder?: string;
}

export interface DependencyReport {
  plugins: PreparedPlugin[];
  /** Erros e avisos (B015). Com algum erro, o build para (BS §3). */
  issues: DependencyIssue[];
}

export interface PrepareOptions {
  projectDir: string;
  lock: PluginLock;
  /** `.vnstudio/plugin-lock.local.json`: vínculos de desenvolvimento desta máquina (SDK §12.3). */
  localLock?: PluginLock;
  /** Exportação para jogadores: vínculos são recusados (P013). O Preview e testes passam `false`. */
  export: boolean;
  /** `--offline`: não consulta o catálogo nem baixa nada; falta no cache é erro (BS §11). */
  offline?: boolean;
  cache: PluginCache;
  http: HttpGet;
  githubToken: TokenProvider;
  catalogUrl?: string;
  /** Versões revogadas que o autor confirmou que quer usar mesmo assim (`<id>@<versão>`, SDK §13.3). */
  allowRevoked?: Iterable<string>;
}

/** Lê `plugin-lock.json` e, se existir, o lock local de vínculos. */
export async function readLocks(projectDir: string): Promise<{ lock: PluginLock; localLock?: PluginLock }> {
  const lock = JSON.parse(await readFile(join(projectDir, LOCK_FILE), 'utf8')) as PluginLock;
  const local = await readFile(join(projectDir, LOCAL_LOCK_FILE), 'utf8').catch(() => undefined);
  return { lock, ...(local ? { localLock: JSON.parse(local) as PluginLock } : {}) };
}

/** JSON do lock como vai para o Git: 2 espaços e quebra de linha no fim. */
export function formatLock(lock: PluginLock): string {
  return `${JSON.stringify(lock, null, 2)}\n`;
}

/**
 * Etapa 3 do pipeline, "Dependências" (Build System §3.2): pega cada pacote do lock no cache, no
 * repositório ou na rede, confere o `integrity` (B002), empacota os embutidos, consulta revogações no
 * índice oficial (B003; sem rede, aviso B015) e, na exportação, recusa vínculos (P013).
 */
export async function prepareDependencies(opts: PrepareOptions): Promise<DependencyReport> {
  const issues: DependencyIssue[] = [];
  const plugins: PreparedPlugin[] = [];
  const entries: [string, LockEntry][] = Object.entries({ ...opts.lock.plugins, ...(opts.localLock?.plugins ?? {}) });
  entries.sort(([a], [b]) => a.localeCompare(b));

  for (const [id, e] of entries) {
    if (e.link && opts.export) {
      issues.push(
        issue('link-on-export', `O plugin ${id} está vinculado a uma pasta de desenvolvimento. Empacote e instale o plugin antes de exportar.`, {
          plugin: id,
          details: e.resolved,
        }),
      );
    }
  }
  if (issues.length) return { plugins, issues };

  for (const [id, e] of entries) {
    if (!e.enabled) continue;
    try {
      plugins.push(await preparePlugin(id, e, opts));
    } catch (err) {
      if (err instanceof DependencyError) issues.push(...err.issues);
      else throw err;
    }
  }

  if (opts.offline) {
    issues.push(issue('catalog-offline', 'Sem internet: não foi possível conferir se algum plugin foi retirado pelo autor.'));
  } else if (plugins.length) {
    let index: CatalogIndex | undefined;
    try {
      index = await fetchCatalog(opts.http, opts.catalogUrl ?? OFFICIAL_CATALOG_URL);
    } catch (err) {
      if (!(err instanceof NetworkError)) throw err;
      issues.push(
        issue('catalog-offline', 'Sem internet: não foi possível conferir se algum plugin foi retirado pelo autor.', { details: err.message }),
      );
    }
    const allowed = new Set(opts.allowRevoked ?? []);
    for (const p of index ? plugins : []) {
      const v = findCatalogVersion(index!, p.id, p.version);
      if (v?.revoked && !allowed.has(`${p.id}@${p.version}`)) {
        issues.push(
          issue(
            'revoked',
            `A versão ${p.version} do plugin ${p.id} foi retirada pelo autor por um problema. Atualize o plugin ou confirme que quer usá-la mesmo assim.`,
            { plugin: p.id, version: p.version, details: v.revoked.reason },
          ),
        );
      }
    }
  }
  return { plugins, issues };
}

async function preparePlugin(id: string, e: LockEntry, opts: PrepareOptions): Promise<PreparedPlugin> {
  const base = { id, version: e.version, namespace: e.namespace, trust: e.trust };
  if (e.link) {
    // Vínculo: `path:<pasta>/vn_plugins/<namespace>`, normalmente fora do projeto (SDK §12.3).
    const rel = e.resolved.replace(/^path:/, '');
    const dir = rel.startsWith('/') || /^[A-Za-z]:[\\/]/.test(rel) ? rel : join(opts.projectDir, rel);
    const { pluginDir } = await findEmbeddedPlugin(dir, rel, id);
    return { ...base, from: 'link', folder: pluginDir };
  }
  if (e.resolved.startsWith('path:')) {
    const rel = e.resolved.slice(5);
    if (e.embedded) {
      const { pluginDir } = await findEmbeddedPlugin(projectPath(opts.projectDir, rel, id), rel, id);
      const pkg = await packPluginFolder(pluginDir);
      return { ...base, from: 'embedded', folder: pluginDir, package: pkg, integrity: sriSha256(pkg) };
    }
    const local = await inspectLocalPath(opts.projectDir, rel, id);
    if (local.kind !== 'vendored') throw new DependencyError([issue('bad-path', `${rel} do plugin ${id} não é um arquivo .vnplugin.`, { plugin: id })]);
    const data = await readFile(local.file);
    verify(id, e, data);
    return { ...base, from: 'vendored', package: data, integrity: e.integrity! };
  }

  const cached = await opts.cache.get(id, e.version, e.integrity);
  if (cached) return { ...base, from: 'cache', package: cached, integrity: e.integrity! };
  if (opts.offline) {
    throw new DependencyError([
      issue('offline-missing', `O plugin ${id} ${e.version} não está no cache deste computador, e o build está sem internet (--offline).`, {
        plugin: id,
        version: e.version,
      }),
    ]);
  }
  const isGithub = e.trust === 'local';
  const token = isGithub ? await opts.githubToken() : undefined;
  let data: Uint8Array;
  try {
    data = await downloadReleaseAsset(opts.http, e.resolved, token);
  } catch (err) {
    if (err instanceof GithubAccessError) {
      throw new DependencyError([issue('token-required', tokenHelp(err.repo), { plugin: id, details: err.message })]);
    }
    if (err instanceof NetworkError) {
      throw new DependencyError([
        issue('network', `Não foi possível baixar o plugin ${id}. Verifique a internet e tente de novo.`, { plugin: id, details: err.message }),
      ]);
    }
    throw err;
  }
  verify(id, e, data);
  await opts.cache.put(id, e.version, data);
  return { ...base, from: 'download', package: data, integrity: e.integrity! };
}

function verify(id: string, e: LockEntry, data: Uint8Array): void {
  if (!e.integrity || !integrityMatches(data, e.integrity)) {
    throw new DependencyError([
      issue('integrity', `O arquivo do plugin ${id} não é o mesmo que foi instalado. Reinstale o plugin pelo Gerenciador de plugins.`, {
        plugin: id,
        version: e.version,
        details: `esperado ${e.integrity ?? '(sem integrity no lock)'}, obtido ${sriSha256(data)}`,
      }),
    ]);
  }
}
