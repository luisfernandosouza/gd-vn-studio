import type { PluginLock, ProjectPlugins } from '@vnstudio/plugin-schema';
import { maxSatisfying, satisfies, validRange } from 'semver';
import { DependencyError, issue, type DependencyIssue } from './errors.js';
import type { Candidate, LoadedPackage, Registry } from './registry.js';

export type LockEntry = PluginLock['plugins'][string];

/** Origem de um plugin que só aparece como dependência de outro: o catálogo oficial (o único do v1). */
export const DEFAULT_DEPENDENCY_SOURCE = 'catalog:official';

export interface ResolveOptions {
  plugins: ProjectPlugins;
  /** Lock atual: versões travadas ficam como estão enquanto satisfizerem as faixas (SDK §11.3 passo 6). */
  previousLock?: PluginLock;
  /** Plugins que podem mudar de versão (`atualizar`), ou `'all'`. Os outros mantêm a versão do lock. */
  update?: Iterable<string> | 'all';
  registry: Registry;
}

interface Selected {
  id: string;
  source: string;
  enabled: boolean;
  cand: Candidate;
  pkg: LoadedPackage;
}

const MAX_ROUNDS = 50;

/**
 * Dependency Resolver (Plugin SDK §11.3). Parte de `plugins.json`, expande `dependencies` e escolhe uma
 * única versão por id: a maior que satisfaz todas as faixas, ou a do lock anterior se ainda satisfaz e o
 * plugin não está em `update`. Falha com conflito, ciclo, dependência desabilitada, namespace duplicado
 * (P001) ou origem `path:` inválida (P021). Devolve o lock novo; quem chama grava.
 */
export async function resolvePlugins(opts: ResolveOptions): Promise<PluginLock> {
  const { plugins, registry } = opts;
  const prev = opts.previousLock?.plugins ?? {};
  const updateAll = opts.update === 'all';
  const updating = new Set(opts.update === 'all' || !opts.update ? [] : opts.update);
  const project = plugins.plugins;
  const selected = new Map<string, Selected>();

  const sourceOf = (id: string): string => project[id]?.source ?? DEFAULT_DEPENDENCY_SOURCE;
  const enabledOf = (id: string): boolean => project[id]?.enabled ?? true;

  for (const [id, cfg] of Object.entries(project)) {
    if (!validRange(cfg.version)) {
      throw new DependencyError([issue('conflict', `A faixa de versão "${cfg.version}" do plugin ${id} não é válida.`, { plugin: id })]);
    }
  }

  let constraints = new Map<string, Map<string, string>>();
  for (let round = 0; ; round++) {
    if (round >= MAX_ROUNDS) {
      throw new DependencyError([issue('conflict', 'As dependências dos plugins não chegaram a um acordo de versões.')]);
    }
    constraints = collectConstraints(project, selected);
    for (const id of [...selected.keys()]) if (!constraints.has(id)) selected.delete(id);

    let changed = false;
    for (const [id, ranges] of [...constraints].sort(([a], [b]) => a.localeCompare(b))) {
      const current = selected.get(id);
      if (current && [...ranges.values()].every((r) => satisfies(current.cand.version, r, { includePrerelease: false }))) continue;

      const source = sourceOf(id);
      const cands = await registry.candidates(id, source);
      const ok = cands.filter((c) => [...ranges.values()].every((r) => satisfies(c.version, r)));
      if (ok.length === 0) throw new DependencyError([conflictIssue(id, ranges, cands)]);

      const locked = prev[id];
      const keep =
        locked && !updateAll && !updating.has(id) ? ok.find((c) => c.version === locked.version && c.resolved === locked.resolved) : undefined;
      const best = maxSatisfying(ok.map((c) => c.version), '*', { includePrerelease: true });
      const cand = keep ?? ok.find((c) => c.version === best);
      if (!cand) throw new DependencyError([conflictIssue(id, ranges, cands)]);

      const expected = locked && locked.version === cand.version && locked.resolved === cand.resolved ? locked.integrity : undefined;
      const pkg = await registry.load(id, cand, expected);
      checkManifest(id, cand, pkg);
      selected.set(id, { id, source, enabled: enabledOf(id), cand, pkg });
      changed = true;
    }
    if (!changed) break;
  }

  const problems: DependencyIssue[] = [];
  // dependência desabilitada
  for (const s of selected.values()) {
    if (!s.enabled) continue;
    for (const dep of Object.keys(s.pkg.manifest.dependencies ?? {})) {
      if (!enabledOf(dep)) {
        problems.push(
          issue('disabled-dependency', `O plugin ${s.id} precisa de ${dep}, que está desativado no projeto.`, { plugin: s.id }),
        );
      }
    }
  }
  // ciclo
  const cycle = findCycle(selected);
  if (cycle) problems.push(issue('cycle', `Os plugins dependem uns dos outros em círculo: ${cycle.join(' → ')}.`, { plugin: cycle[0] }));
  // namespace duplicado (P001)
  const byNs = new Map<string, string[]>();
  for (const s of selected.values()) byNs.set(s.pkg.manifest.namespace, [...(byNs.get(s.pkg.manifest.namespace) ?? []), s.id]);
  for (const [ns, ids] of byNs) {
    if (ids.length > 1) {
      problems.push(issue('duplicate-namespace', `Os plugins ${ids.sort().join(' e ')} usam o mesmo namespace "${ns}".`, { plugin: ids[0] }));
    }
  }
  if (problems.length) throw new DependencyError(problems);

  const lock: PluginLock = { lock_version: 1, plugins: {} };
  for (const id of [...selected.keys()].sort()) {
    const s = selected.get(id)!;
    const requesters = [...(constraints.get(id)?.keys() ?? [])];
    const deps: Record<string, string> = {};
    for (const dep of Object.keys({ ...s.pkg.manifest.dependencies, ...s.pkg.manifest.optional_dependencies }).sort()) {
      const d = selected.get(dep);
      if (d) deps[dep] = d.cand.version;
    }
    const entry: LockEntry = {
      version: s.cand.version,
      namespace: s.pkg.manifest.namespace,
      resolved: s.cand.resolved,
      ...(s.pkg.integrity && !s.cand.embedded ? { integrity: s.pkg.integrity } : {}),
      enabled: s.enabled,
      trust: s.cand.trust,
      requested_by: [...requesters.filter((r) => r === 'project'), ...requesters.filter((r) => r !== 'project').sort()],
      dependencies: deps,
      ...(s.cand.embedded ? { embedded: true } : {}),
    };
    lock.plugins[id] = entry;
  }
  return lock;
}

/**
 * Faixas pedidas para cada id, por quem pediu (`project` ou o id do plugin). Plugins desativados entram
 * no lock, mas as dependências deles não são expandidas. `optional_dependencies` só contam quando o
 * plugin já entra por outro caminho (SDK §11.3 passo 4).
 */
function collectConstraints(
  project: ProjectPlugins['plugins'],
  selected: Map<string, Selected>,
): Map<string, Map<string, string>> {
  const out = new Map<string, Map<string, string>>();
  const add = (id: string, by: string, range: string): void => {
    const m = out.get(id) ?? new Map<string, string>();
    m.set(by, range);
    out.set(id, m);
  };
  for (const [id, cfg] of Object.entries(project)) add(id, 'project', cfg.version);
  const queue = Object.keys(project);
  const seen = new Set(queue);
  while (queue.length) {
    const id = queue.shift()!;
    const s = selected.get(id);
    if (!s || !s.enabled) continue;
    for (const [dep, range] of Object.entries(s.pkg.manifest.dependencies ?? {})) {
      add(dep, id, range);
      if (!seen.has(dep)) {
        seen.add(dep);
        queue.push(dep);
      }
    }
  }
  for (const s of selected.values()) {
    if (!s.enabled || !out.has(s.id)) continue;
    for (const [dep, range] of Object.entries(s.pkg.manifest.optional_dependencies ?? {})) {
      if (out.has(dep)) add(dep, s.id, range);
    }
  }
  return out;
}

function conflictIssue(id: string, ranges: Map<string, string>, cands: Candidate[]): DependencyIssue {
  const asked = [...ranges].map(([by, r]) => `${by === 'project' ? 'o projeto' : by} pede ${r}`).join('; ');
  return issue('conflict', `Nenhuma versão do plugin ${id} atende a todos os pedidos (${asked}).`, {
    plugin: id,
    details: `versões disponíveis: ${cands.map((c) => c.version).join(', ') || 'nenhuma'}`,
  });
}

function checkManifest(id: string, cand: Candidate, pkg: LoadedPackage): void {
  const m = pkg.manifest;
  if (m.id !== id || m.version !== cand.version) {
    throw new DependencyError([
      issue('manifest-mismatch', `O pacote do plugin ${id} ${cand.version} traz outro plugin (${m.id} ${m.version}).`, {
        plugin: id,
        version: cand.version,
        details: cand.resolved,
      }),
    ]);
  }
}

function findCycle(selected: Map<string, Selected>): string[] | undefined {
  const state = new Map<string, 'visiting' | 'done'>();
  const stack: string[] = [];
  const visit = (id: string): string[] | undefined => {
    if (state.get(id) === 'done') return undefined;
    if (state.get(id) === 'visiting') return [...stack.slice(stack.indexOf(id)), id];
    state.set(id, 'visiting');
    stack.push(id);
    const s = selected.get(id);
    for (const dep of Object.keys(s?.enabled ? (s.pkg.manifest.dependencies ?? {}) : {}).sort()) {
      if (!selected.has(dep)) continue;
      const c = visit(dep);
      if (c) return c;
    }
    stack.pop();
    state.set(id, 'done');
    return undefined;
  };
  for (const id of [...selected.keys()].sort()) {
    const c = visit(id);
    if (c) return c;
  }
  return undefined;
}
