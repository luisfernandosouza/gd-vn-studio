import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { PluginLock, PluginManifest, ProjectPlugins } from '@vnstudio/plugin-schema';
import { describe, expect, it } from 'vitest';
import { PluginCache } from './cache.js';
import { OFFICIAL_CATALOG_URL, type CatalogIndex } from './catalog.js';
import { GITHUB_TOKEN_ENV, githubTokenProvider } from './credentials.js';
import { prepareDependencies, type PrepareOptions } from './dependencies.js';
import { DependencyError, NetworkError, type DependencyIssue } from './errors.js';
import type { HttpGet } from './http.js';
import { sriSha256 } from './integrity.js';
import { Registry } from './registry.js';
import { resolvePlugins } from './resolver.js';
import { writeZip } from './zip.js';

// ---------- fixtures ----------

function manifest(id: string, version: string, extra: Partial<PluginManifest> = {}): PluginManifest {
  return {
    manifest_version: 1,
    id,
    namespace: id.split('.')[1]!.replace(/-/g, '_'),
    name: id,
    version,
    license: 'MIT',
    default_locale: 'en',
    sdk: { runtime: '^1.0.0' },
    compatibility: { runtime: '^1.0.0' },
    targets: ['runtime'],
    entrypoints: { runtime: 'runtime/src/plugin.gd' },
    ...extra,
  } as PluginManifest;
}

function pkg(m: PluginManifest): Buffer {
  return writeZip([
    { path: 'plugin.json', data: Buffer.from(JSON.stringify(m)) },
    { path: 'runtime/src/plugin.gd', data: Buffer.from(`# ${m.id} ${m.version}\n`) },
  ]);
}

const REL = (repo: string, tag: string, name: string): string => `https://github.com/${repo}/releases/download/${tag}/${name}`;
const OFFICIAL = 'luisfernandosouza/gd-vn-studio';

/** Servidor HTTP falso: URL → corpo. Registra as chamadas e os cabeçalhos. */
class FakeNet {
  routes = new Map<string, { status: number; body: Uint8Array; auth?: string }>();
  calls: { url: string; headers: Record<string, string> }[] = [];
  offline = false;
  get: HttpGet = async (url, headers = {}) => {
    this.calls.push({ url, headers });
    if (this.offline) throw new NetworkError('offline');
    const r = this.routes.get(url);
    if (!r) return { status: 404, body: new Uint8Array() };
    if (r.auth && headers.Authorization !== `Bearer ${r.auth}`) return { status: 404, body: new Uint8Array() };
    return { status: r.status, body: r.body };
  };
  json(url: string, data: unknown, auth?: string): void {
    this.routes.set(url, { status: 200, body: Buffer.from(JSON.stringify(data)), ...(auth ? { auth } : {}) });
  }
  file(url: string, data: Uint8Array, auth?: string): void {
    this.routes.set(url, { status: 200, body: data, ...(auth ? { auth } : {}) });
  }
}

/** Publica versões no índice oficial falso (Plugin SDK §13.2), cada uma numa Release do monorepo. */
function officialCatalog(net: FakeNet, plugins: { m: PluginManifest; revoked?: string; integrity?: string }[]): void {
  const index: CatalogIndex = { catalog_version: 1, plugins: [] };
  for (const { m, revoked, integrity } of plugins) {
    const data = pkg(m);
    const url = REL(OFFICIAL, `plugin-${m.namespace}-v${m.version}`, `${m.id}-${m.version}.vnplugin`);
    net.file(url, data);
    let entry = index.plugins.find((p) => p.id === m.id);
    if (!entry) index.plugins.push((entry = { id: m.id, namespace: m.namespace, versions: [] }));
    entry.versions.push({
      version: m.version,
      url,
      integrity: integrity ?? sriSha256(data),
      state: 'published',
      trust: 'official',
      ...(revoked ? { revoked: { reason: revoked } } : {}),
    });
  }
  net.json(OFFICIAL_CATALOG_URL, index);
}

/** Releases falsas de um repositório de plugin (`github:`), opcionalmente privado (exige o token). */
function githubRepo(net: FakeNet, repo: string, ms: PluginManifest[], token?: string): void {
  const releases = ms.map((m, i) => {
    const name = `${m.id}-${m.version}.vnplugin`;
    const tag = `v${m.version}`;
    const apiUrl = `https://api.github.com/repos/${repo}/releases/assets/${i + 1}`;
    const data = pkg(m);
    net.file(apiUrl, data, token);
    if (!token) net.file(REL(repo, tag, name), data);
    return { tag_name: tag, draft: false, assets: [{ name, url: apiUrl, browser_download_url: REL(repo, tag, name) }] };
  });
  net.json(`https://api.github.com/repos/${repo}/releases?per_page=100&page=1`, releases, token);
  for (const r of releases) net.json(`https://api.github.com/repos/${repo}/releases/tags/${r.tag_name}`, r, token);
}

async function tmp(): Promise<string> {
  return mkdtemp(join(tmpdir(), 'vnplugins-'));
}

async function project(plugins: ProjectPlugins['plugins']): Promise<{ dir: string; plugins: ProjectPlugins }> {
  const dir = await tmp();
  return { dir, plugins: { plugins } };
}

/** Projeto de desenvolvimento de um plugin embutido (spec 09 §3.2) em `<dir>/<rel>`. */
async function embedded(dir: string, rel: string, m: PluginManifest): Promise<void> {
  const p = join(dir, rel, 'vn_plugins', m.namespace);
  await mkdir(join(p, 'runtime', 'src'), { recursive: true });
  await writeFile(join(dir, rel, 'project.godot'), '; dev\n');
  await writeFile(join(p, 'plugin.json'), JSON.stringify(m));
  await writeFile(join(p, 'runtime', 'src', 'plugin.gd'), 'extends Node\n');
}

function env(net: FakeNet, dir: string, cacheRoot: string, token?: string) {
  const githubToken = githubTokenProvider(token ? { [GITHUB_TOKEN_ENV]: token } : {}, async () => undefined);
  const cache = new PluginCache(cacheRoot);
  return { cache, githubToken, registry: new Registry({ projectDir: dir, http: net.get, cache, githubToken }) };
}

async function rejects(p: Promise<unknown>): Promise<DependencyIssue[]> {
  try {
    await p;
  } catch (err) {
    if (err instanceof DependencyError) return err.issues;
    throw err;
  }
  throw new Error('esperava DependencyError');
}

// ---------- as quatro origens (Repo §3.1) ----------

describe('origens de plugins (spec 09 §3.1)', () => {
  it('catalog:official resolve contra o índice oficial, pega a maior versão e guarda no cache', async () => {
    const net = new FakeNet();
    officialCatalog(net, [
      { m: manifest('vnstudio.fishing', '1.0.0') },
      { m: manifest('vnstudio.fishing', '1.2.0') },
      { m: manifest('vnstudio.fishing', '1.3.0'), revoked: 'trava no Web' },
      { m: manifest('vnstudio.fishing', '2.0.0') },
    ]);
    const { dir, plugins } = await project({ 'vnstudio.fishing': { version: '^1.0.0', source: 'catalog:official' } });
    const cacheRoot = await tmp();
    const { registry, cache } = env(net, dir, cacheRoot);
    const lock = await resolvePlugins({ plugins, registry });
    const e = lock.plugins['vnstudio.fishing']!;
    expect(e.version).toBe('1.2.0'); // 1.3.0 revogada não é instalada; 2.0.0 fora da faixa
    expect(e).toMatchObject({
      namespace: 'fishing',
      resolved: REL(OFFICIAL, 'plugin-fishing-v1.2.0', 'vnstudio.fishing-1.2.0.vnplugin'),
      integrity: sriSha256(pkg(manifest('vnstudio.fishing', '1.2.0'))),
      enabled: true,
      trust: 'official',
      requested_by: ['project'],
      dependencies: {},
    });
    expect(await cache.get('vnstudio.fishing', '1.2.0', e.integrity)).toBeDefined();
    expect(cache.path('vnstudio.fishing', '1.2.0')).toBe(join(cacheRoot, 'vnstudio.fishing', '1.2.0', 'vnstudio.fishing-1.2.0.vnplugin'));
  });

  it('catalog:official: pacote diferente do integrity do índice dá B002', async () => {
    const net = new FakeNet();
    officialCatalog(net, [{ m: manifest('vnstudio.fishing', '1.0.0'), integrity: sriSha256(Buffer.from('outro')) }]);
    const { dir, plugins } = await project({ 'vnstudio.fishing': { version: '^1.0.0', source: 'catalog:official' } });
    const issues = await rejects(resolvePlugins({ plugins, registry: env(net, dir, await tmp()).registry }));
    expect(issues[0]).toMatchObject({ code: 'B002', plugin: 'vnstudio.fishing' });
  });

  it('github: em repositório privado usa VNSTUDIO_GITHUB_TOKEN; sem token explica como criar um', async () => {
    const net = new FakeNet();
    githubRepo(net, 'acme/cards', [manifest('acme.cards', '1.1.0'), manifest('acme.cards', '1.2.0')], 'segredo');
    const { dir, plugins } = await project({ 'acme.cards': { version: '~1.1.0', source: 'github:acme/cards' } });

    const issues = await rejects(resolvePlugins({ plugins, registry: env(net, dir, await tmp()).registry }));
    expect(issues[0]).toMatchObject({ kind: 'token-required', plugin: 'acme.cards' });
    expect(issues[0]!.message).toMatch(/VNSTUDIO_GITHUB_TOKEN/);

    const lock = await resolvePlugins({ plugins, registry: env(net, dir, await tmp(), 'segredo').registry });
    expect(lock.plugins['acme.cards']).toMatchObject({
      version: '1.1.0',
      resolved: REL('acme/cards', 'v1.1.0', 'acme.cards-1.1.0.vnplugin'),
      integrity: sriSha256(pkg(manifest('acme.cards', '1.1.0'))),
      trust: 'local',
    });
    expect(net.calls.some((c) => c.headers.Authorization === 'Bearer segredo')).toBe(true);
    expect(JSON.stringify(lock)).not.toContain('segredo');
  });

  it('path: para um .vnplugin guardado no repositório (pacote guardado)', async () => {
    const m = manifest('acme.cards', '1.2.0');
    const { dir, plugins } = await project({
      'acme.cards': { version: '^1.0.0', source: 'path:vendor/plugins/acme.cards-1.2.0.vnplugin' },
    });
    await mkdir(join(dir, 'vendor', 'plugins'), { recursive: true });
    await writeFile(join(dir, 'vendor', 'plugins', 'acme.cards-1.2.0.vnplugin'), pkg(m));
    const lock = await resolvePlugins({ plugins, registry: env(new FakeNet(), dir, await tmp()).registry });
    expect(lock.plugins['acme.cards']).toEqual({
      version: '1.2.0',
      namespace: 'cards',
      resolved: 'path:vendor/plugins/acme.cards-1.2.0.vnplugin',
      integrity: sriSha256(pkg(m)),
      enabled: true,
      trust: 'local',
      requested_by: ['project'],
      dependencies: {},
    });
  });

  it('path: para uma pasta é plugin embutido: embedded, trust local e sem integrity', async () => {
    const { dir, plugins } = await project({ 'seaside.quiz': { version: '*', source: 'path:plugins/quiz' } });
    await embedded(dir, 'plugins/quiz', manifest('seaside.quiz', '0.3.0'));
    const lock = await resolvePlugins({ plugins, registry: env(new FakeNet(), dir, await tmp()).registry });
    expect(lock.plugins['seaside.quiz']).toEqual({
      version: '0.3.0',
      namespace: 'quiz',
      resolved: 'path:plugins/quiz',
      enabled: true,
      trust: 'local',
      requested_by: ['project'],
      dependencies: {},
      embedded: true,
    });
  });

  it('path: inexistente, fora do projeto ou com dois plugin.json dá P021', async () => {
    for (const source of ['path:plugins/nada', 'path:../fora']) {
      const { dir, plugins } = await project({ 'seaside.quiz': { version: '*', source } });
      const issues = await rejects(resolvePlugins({ plugins, registry: env(new FakeNet(), dir, await tmp()).registry }));
      expect(issues[0]?.code, source).toBe('P021');
    }
    const { dir, plugins } = await project({ 'seaside.quiz': { version: '*', source: 'path:plugins/quiz' } });
    await embedded(dir, 'plugins/quiz', manifest('seaside.quiz', '0.3.0'));
    await embedded(dir, 'plugins/quiz', manifest('seaside.quiz2', '0.3.0'));
    const issues = await rejects(resolvePlugins({ plugins, registry: env(new FakeNet(), dir, await tmp()).registry }));
    expect(issues[0]?.code).toBe('P021');
  });
});

// ---------- Dependency Resolver (Plugin SDK §11.3) ----------

describe('Dependency Resolver (Plugin SDK §11.3)', () => {
  it('expande dependências e escolhe uma versão que atende a todas as faixas', async () => {
    const net = new FakeNet();
    officialCatalog(net, [
      { m: manifest('vnstudio.core', '1.0.0') },
      { m: manifest('vnstudio.core', '1.4.0') },
      { m: manifest('vnstudio.core', '2.0.0') },
      { m: manifest('vnstudio.fishing', '1.0.0', { dependencies: { 'vnstudio.core': '^1.0.0' } }) },
      { m: manifest('vnstudio.boats', '1.0.0', { dependencies: { 'vnstudio.core': '>=1.0.0 <1.4.0' } }) },
    ]);
    const { dir, plugins } = await project({
      'vnstudio.fishing': { version: '^1.0.0', source: 'catalog:official' },
      'vnstudio.boats': { version: '^1.0.0', source: 'catalog:official' },
    });
    const lock = await resolvePlugins({ plugins, registry: env(net, dir, await tmp()).registry });
    expect(Object.keys(lock.plugins)).toEqual(['vnstudio.boats', 'vnstudio.core', 'vnstudio.fishing']);
    expect(lock.plugins['vnstudio.core']).toMatchObject({ version: '1.0.0', requested_by: ['vnstudio.boats', 'vnstudio.fishing'] });
    expect(lock.plugins['vnstudio.fishing']!.dependencies).toEqual({ 'vnstudio.core': '1.0.0' });
  });

  it('conflito quando nenhuma versão atende a todas as faixas', async () => {
    const net = new FakeNet();
    officialCatalog(net, [
      { m: manifest('vnstudio.core', '1.0.0') },
      { m: manifest('vnstudio.core', '2.0.0') },
      { m: manifest('vnstudio.fishing', '1.0.0', { dependencies: { 'vnstudio.core': '^2.0.0' } }) },
    ]);
    const { dir, plugins } = await project({
      'vnstudio.fishing': { version: '^1.0.0', source: 'catalog:official' },
      'vnstudio.core': { version: '^1.0.0', source: 'catalog:official' },
    });
    const issues = await rejects(resolvePlugins({ plugins, registry: env(net, dir, await tmp()).registry }));
    expect(issues[0]).toMatchObject({ kind: 'conflict', plugin: 'vnstudio.core' });
  });

  it('ciclo, dependência desativada e namespace duplicado (P001)', async () => {
    const net = new FakeNet();
    officialCatalog(net, [
      { m: manifest('vnstudio.aa', '1.0.0', { dependencies: { 'vnstudio.bb': '*' } }) },
      { m: manifest('vnstudio.bb', '1.0.0', { dependencies: { 'vnstudio.aa': '*' } }) },
      { m: manifest('vnstudio.cc', '1.0.0', { dependencies: { 'vnstudio.dd': '*' } }) },
      { m: manifest('vnstudio.dd', '1.0.0') },
      { m: manifest('vnstudio.ee', '1.0.0', { namespace: 'same' }) },
      { m: manifest('vnstudio.ff', '1.0.0', { namespace: 'same' }) },
    ]);
    const cases: [ProjectPlugins['plugins'], string][] = [
      [{ 'vnstudio.aa': { version: '*', source: 'catalog:official' } }, 'cycle'],
      [
        {
          'vnstudio.cc': { version: '*', source: 'catalog:official' },
          'vnstudio.dd': { version: '*', source: 'catalog:official', enabled: false },
        },
        'disabled-dependency',
      ],
      [
        {
          'vnstudio.ee': { version: '*', source: 'catalog:official' },
          'vnstudio.ff': { version: '*', source: 'catalog:official' },
        },
        'duplicate-namespace',
      ],
    ];
    for (const [ps, kind] of cases) {
      const { dir, plugins } = await project(ps);
      const issues = await rejects(resolvePlugins({ plugins, registry: env(net, dir, await tmp()).registry }));
      expect(issues.map((i) => i.kind), kind).toContain(kind);
    }
  });

  it('optional_dependencies só entram se o projeto já usa o plugin, e então a faixa vale', async () => {
    const net = new FakeNet();
    officialCatalog(net, [
      { m: manifest('vnstudio.core', '1.0.0') },
      { m: manifest('vnstudio.core', '1.5.0') },
      { m: manifest('vnstudio.fishing', '1.0.0', { optional_dependencies: { 'vnstudio.core': '<1.5.0' } }) },
    ]);
    const alone = await project({ 'vnstudio.fishing': { version: '*', source: 'catalog:official' } });
    const l1 = await resolvePlugins({ plugins: alone.plugins, registry: env(net, alone.dir, await tmp()).registry });
    expect(Object.keys(l1.plugins)).toEqual(['vnstudio.fishing']);

    const both = await project({
      'vnstudio.fishing': { version: '*', source: 'catalog:official' },
      'vnstudio.core': { version: '^1.0.0', source: 'catalog:official' },
    });
    const l2 = await resolvePlugins({ plugins: both.plugins, registry: env(net, both.dir, await tmp()).registry });
    expect(l2.plugins['vnstudio.core']!.version).toBe('1.0.0');
    expect(l2.plugins['vnstudio.fishing']!.dependencies).toEqual({ 'vnstudio.core': '1.0.0' });
  });

  it('o lock só muda com ação explícita: mantém a versão travada até "atualizar"', async () => {
    const net = new FakeNet();
    officialCatalog(net, [{ m: manifest('vnstudio.fishing', '1.0.0') }]);
    const { dir, plugins } = await project({ 'vnstudio.fishing': { version: '^1.0.0', source: 'catalog:official' } });
    const first = await resolvePlugins({ plugins, registry: env(net, dir, await tmp()).registry });

    officialCatalog(net, [{ m: manifest('vnstudio.fishing', '1.0.0') }, { m: manifest('vnstudio.fishing', '1.1.0') }]);
    const kept = await resolvePlugins({ plugins, previousLock: first, registry: env(net, dir, await tmp()).registry });
    expect(kept).toEqual(first);
    const updated = await resolvePlugins({ plugins, previousLock: first, update: ['vnstudio.fishing'], registry: env(net, dir, await tmp()).registry });
    expect(updated.plugins['vnstudio.fishing']!.version).toBe('1.1.0');
  });
});

// ---------- etapa de dependências do build (Build System §3.2) ----------

describe('dependências no build (Build System §3.2)', () => {
  async function demo() {
    const net = new FakeNet();
    const fishing = manifest('vnstudio.fishing', '1.0.0');
    officialCatalog(net, [{ m: fishing }]);
    const { dir, plugins } = await project({ 'vnstudio.fishing': { version: '^1.0.0', source: 'catalog:official' } });
    const cacheRoot = await tmp();
    const e = env(net, dir, cacheRoot);
    const lock = await resolvePlugins({ plugins, registry: e.registry });
    const opts = (o: Partial<PrepareOptions> = {}): PrepareOptions => ({
      projectDir: dir,
      lock,
      export: true,
      cache: new PluginCache(cacheRoot),
      http: net.get,
      githubToken: e.githubToken,
      ...o,
    });
    return { net, dir, lock, cacheRoot, opts, fishing };
  }

  it('usa o pacote do cache e confere o índice', async () => {
    const { opts, net } = await demo();
    net.calls = [];
    const r = await prepareDependencies(opts());
    expect(r.issues).toEqual([]);
    expect(r.plugins).toMatchObject([{ id: 'vnstudio.fishing', from: 'cache', trust: 'official' }]);
    expect(net.calls.map((c) => c.url)).toEqual([OFFICIAL_CATALOG_URL]);
  });

  it('sem o pacote no cache, baixa de resolved; arquivo diferente do lock dá B002 e sai do cache', async () => {
    const { opts, lock, net, cacheRoot } = await demo();
    const fresh = await tmp();
    const r = await prepareDependencies(opts({ cache: new PluginCache(fresh) }));
    expect(r.plugins[0]!.from).toBe('download');

    const e = lock.plugins['vnstudio.fishing']!;
    net.file(e.resolved, Buffer.from('adulterado'));
    const r2 = await prepareDependencies(opts({ cache: new PluginCache(await tmp()) }));
    expect(r2.issues.map((i) => i.code)).toEqual(['B002']);

    // cache adulterado: apagado e baixado de novo (BS §10.2), e o novo download também não confere
    const cache = new PluginCache(cacheRoot);
    await writeFile(cache.path('vnstudio.fishing', '1.0.0'), 'lixo');
    const r3 = await prepareDependencies(opts());
    expect(r3.issues.map((i) => i.code)).toEqual(['B002']);
    expect(await readFile(cache.path('vnstudio.fishing', '1.0.0')).catch(() => undefined)).toBeUndefined();
  });

  it('versão revogada no índice dá B003, salvo confirmação explícita', async () => {
    const { opts, net, fishing } = await demo();
    officialCatalog(net, [{ m: fishing, revoked: 'perde o save' }]);
    const r = await prepareDependencies(opts());
    expect(r.issues).toMatchObject([{ code: 'B003', level: 'error', plugin: 'vnstudio.fishing', version: '1.0.0', details: 'perde o save' }]);
    const ok = await prepareDependencies(opts({ allowRevoked: ['vnstudio.fishing@1.0.0'] }));
    expect(ok.issues).toEqual([]);
  });

  it('sem rede: aviso B015 e segue com o cache; --offline sem o pacote no cache falha', async () => {
    const { opts, net } = await demo();
    net.offline = true;
    const r = await prepareDependencies(opts());
    expect(r.issues).toMatchObject([{ code: 'B015', level: 'warning' }]);
    expect(r.plugins).toHaveLength(1);

    const r2 = await prepareDependencies(opts({ offline: true, cache: new PluginCache(await tmp()) }));
    expect(r2.issues.map((i) => i.kind)).toEqual(['offline-missing', 'catalog-offline']);
  });

  it('vínculo de desenvolvimento: recusado na exportação (P013), aceito fora dela', async () => {
    const { opts, lock } = await demo();
    const devDir = await tmp();
    const m = manifest('vnstudio.fishing', '1.1.0');
    await embedded(devDir, '.', m);
    const localLock: PluginLock = {
      lock_version: 1,
      plugins: {
        'vnstudio.fishing': {
          ...lock.plugins['vnstudio.fishing']!,
          version: '1.1.0',
          resolved: `path:${join(devDir, 'vn_plugins', 'fishing')}`,
          link: true,
          trust: 'local',
        },
      },
    };
    delete localLock.plugins['vnstudio.fishing']!.integrity;
    const r = await prepareDependencies(opts({ localLock }));
    expect(r.issues).toMatchObject([{ code: 'P013', plugin: 'vnstudio.fishing' }]);
    expect(r.plugins).toEqual([]);

    const dev = await prepareDependencies(opts({ localLock, export: false }));
    expect(dev.issues).toEqual([]);
    expect(dev.plugins).toMatchObject([{ from: 'link', version: '1.1.0', folder: join(devDir, 'vn_plugins', 'fishing') }]);
  });

  it('pacote guardado confere o hash (B002) e o embutido é empacotado com integrity calculado', async () => {
    const { dir, plugins } = await project({
      'acme.cards': { version: '*', source: 'path:vendor/plugins/acme.cards-1.0.0.vnplugin' },
      'seaside.quiz': { version: '*', source: 'path:plugins/quiz' },
      'seaside.off': { version: '*', source: 'path:plugins/off', enabled: false },
    });
    await mkdir(join(dir, 'vendor', 'plugins'), { recursive: true });
    const file = join(dir, 'vendor', 'plugins', 'acme.cards-1.0.0.vnplugin');
    await writeFile(file, pkg(manifest('acme.cards', '1.0.0')));
    await embedded(dir, 'plugins/quiz', manifest('seaside.quiz', '0.1.0'));
    await embedded(dir, 'plugins/off', manifest('seaside.off', '0.1.0'));
    const net = new FakeNet();
    net.json(OFFICIAL_CATALOG_URL, { catalog_version: 1, plugins: [] });
    const e = env(net, dir, await tmp());
    const lock = await resolvePlugins({ plugins, registry: e.registry });
    expect(lock.plugins['seaside.off']!.enabled).toBe(false);

    const base: PrepareOptions = { projectDir: dir, lock, export: true, cache: e.cache, http: net.get, githubToken: e.githubToken };
    const r = await prepareDependencies(base);
    expect(r.issues).toEqual([]);
    expect(r.plugins.map((p) => [p.id, p.from])).toEqual([
      ['acme.cards', 'vendored'],
      ['seaside.quiz', 'embedded'],
    ]);
    const quiz = r.plugins[1]!;
    expect(quiz.integrity).toBe(sriSha256(quiz.package!));
    expect((await prepareDependencies(base)).plugins[1]!.integrity).toBe(quiz.integrity); // reprodutível

    await writeFile(file, pkg(manifest('acme.cards', '1.0.0', { name: 'trocado' })));
    const bad = await prepareDependencies(base);
    expect(bad.issues.map((i) => [i.code, i.plugin])).toEqual([['B002', 'acme.cards']]);
  });

  it('github: no build baixa pela API com o token quando o pacote não está no cache', async () => {
    const net = new FakeNet();
    githubRepo(net, 'acme/cards', [manifest('acme.cards', '1.0.0')], 'segredo');
    net.json(OFFICIAL_CATALOG_URL, { catalog_version: 1, plugins: [] });
    const { dir, plugins } = await project({ 'acme.cards': { version: '*', source: 'github:acme/cards' } });
    const e = env(net, dir, await tmp(), 'segredo');
    const lock = await resolvePlugins({ plugins, registry: e.registry });
    const r = await prepareDependencies({
      projectDir: dir,
      lock,
      export: true,
      cache: new PluginCache(await tmp()),
      http: net.get,
      githubToken: e.githubToken,
    });
    expect(r.issues).toEqual([]);
    expect(r.plugins).toMatchObject([{ id: 'acme.cards', from: 'download', trust: 'local' }]);
  });
});

describe('token do GitHub (spec 09 §3.1)', () => {
  it('VNSTUDIO_GITHUB_TOKEN vem antes do chaveiro', async () => {
    expect(await githubTokenProvider({ [GITHUB_TOKEN_ENV]: ' t1 ' }, async () => 'k')()).toBe('t1');
    expect(await githubTokenProvider({}, async () => 'k')()).toBe('k');
    expect(await githubTokenProvider({}, async () => undefined)()).toBeUndefined();
  });
});
