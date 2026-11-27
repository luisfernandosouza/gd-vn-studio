/**
 * Sessão do Preview no painel (M6-10): abre a conversa com o runtime (`hello`, `load`), mantém o bundle em
 * `.vnstudio/preview/narrative/` e manda a cada edição só o que mudou (`preview.reload` com `patch`, PP §3).
 *
 * Recarga: o plano de `planReload` (CLI, M5-02) compara o bundle anterior com o projeto editado, entidade
 * por entidade. Sem nada que peça recarga completa, vai o `patch` (DEVERIA levar menos de 50 ms, PP §3).
 * Mudança em `/project`, `/variables`, `/aliases`, nos idiomas ou em `plugins.json`, um erro do patch e
 * cada {@link FULL_RELOAD_EVERY} recargas incrementais pedem a recarga completa (`bundle_url` + `changed`).
 *
 * O estado visível ao painel fica num `snapshot` imutável, lido com `useSyncExternalStore`.
 */
import { applyPatch, planReload, rehash, type PatchOp } from '../../cli/src/bundle/incremental';
import { compileProject, type CompiledBundle, type CompileOptions } from '../../cli/src/bundle/compile';
import type { ProjectInput } from '../../cli/src/bundle/input';
import type { GameState, PreviewStartParams, SessionHelloResult } from '@vnstudio/plugin-schema';
import { joinPath, type ProjectFs } from '../src/project-manager/fs';
import { filesTouchedBy, writeBundleFiles } from './bundle-files';
import {
  PreviewClient,
  PreviewRpcError,
  type PreviewMethods,
  type PreviewNotification,
  type PreviewTransport,
} from './client';
import { fromBase64, readUserFiles, safeUserPath } from './user-files';
import { PREVIEW_USER_DIR, type PreviewUrls } from './urls';

/** A cada tantas recargas incrementais, uma completa confere que a memória do runtime bate com o disco (PP §3). */
export const FULL_RELOAD_EVERY = 50;

/** Versão do protocolo que o Studio fala (PP §1, `protocol`). */
export const PROTOCOL_VERSION = '1.0';

export type PreviewStatus = 'idle' | 'connecting' | 'ready' | 'closed' | 'error';
/** Estado do Preview (PP §2) que o painel mostra. */
export type PreviewRunState = 'LOADED' | 'RUNNING' | 'PAUSED';

export interface LogEntry {
  at: number;
  level: 'debug' | 'info' | 'warning' | 'error';
  source: 'studio' | 'runtime' | 'plugin';
  message: string;
}

export interface ReloadStats {
  incremental: number;
  full: number;
  /** Incrementais desde a última recarga completa. */
  sinceFull: number;
  lastMs: number | null;
  /** `resumed` da última recarga (PP §3). */
  lastResumed: string | null;
  lastKind: 'incremental' | 'full' | null;
  /** Motivo da última recarga completa (lista do plano, erro do patch ou conferência periódica). */
  lastFullReason: string | null;
}

export interface PreviewSnapshot {
  status: PreviewStatus;
  runState: PreviewRunState | null;
  hello: SessionHelloResult | null;
  contentHash: string | null;
  /** Modo stream ligado (Req §11.2). */
  contentFilter: boolean;
  phase: string | null;
  scene: string | null;
  node: string | null;
  reloads: ReloadStats;
  log: readonly LogEntry[];
  error: string | null;
}

export interface PreviewSessionOptions {
  fs: ProjectFs;
  root: string;
  transport: PreviewTransport;
  urls: PreviewUrls;
  studioVersion?: string;
  /** "Manter saves do Preview" (PP §1.4). */
  keepSaves?: boolean;
  locale?: string;
  compile?: CompileOptions;
  /** Relógio dos tempos de recarga (testes). */
  now?: () => number;
  /** Prazo de cada requisição ao runtime. */
  timeoutMs?: number;
}

const MAX_LOG = 200;

const initial: PreviewSnapshot = {
  status: 'idle',
  runState: null,
  hello: null,
  contentHash: null,
  contentFilter: false,
  phase: null,
  scene: null,
  node: null,
  reloads: { incremental: 0, full: 0, sinceFull: 0, lastMs: null, lastResumed: null, lastKind: null, lastFullReason: null },
  log: [],
  error: null,
};

/** Caminho do projeto a que cada parte do plano de recarga completa se refere (`changed` de `preview.reload`). */
function changedFiles(reasons: readonly string[]): string[] {
  const files = new Set<string>();
  for (const reason of reasons) {
    if (reason.endsWith('/project') || reason === 'idiomas') files.add('project.json');
    else if (reason.endsWith('/variables') || reason.endsWith('/aliases')) files.add('variables.json');
    else if (reason === 'plugins.json') files.add('plugins.json');
    else files.add('project.json');
  }
  return [...files];
}

export type ReloadOutcome =
  | { kind: 'none' }
  | { kind: 'incremental'; ops: number; ms: number; resumed: string }
  | { kind: 'full'; reason: string; ms: number; resumed: string };

export class PreviewSession {
  readonly client: PreviewClient;
  private snap: PreviewSnapshot = initial;
  private readonly listeners = new Set<() => void>();
  private compiled: CompiledBundle | null = null;
  private queue: Promise<unknown> = Promise.resolve();
  private latest: ProjectInput | null = null;
  private disposed = false;
  private readonly now: () => number;

  constructor(private readonly o: PreviewSessionOptions) {
    this.now = o.now ?? (() => performance.now());
    this.client = new PreviewClient(o.transport, {
      ...(o.timeoutMs ? { timeoutMs: o.timeoutMs } : {}),
      onIgnored: (reason) => this.log('warning', 'studio', reason),
    });
    this.client.onNotification((n) => this.onNotification(n));
  }

  // ------------------------------------------------------------------------------------------ estado

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): PreviewSnapshot => this.snap;

  private set(patch: Partial<PreviewSnapshot>): void {
    this.snap = { ...this.snap, ...patch };
    for (const l of this.listeners) l();
  }

  private log(level: LogEntry['level'], source: LogEntry['source'], message: string): void {
    const entry: LogEntry = { at: Date.now(), level, source, message };
    this.set({ log: [...this.snap.log, entry].slice(-MAX_LOG) });
  }

  // ------------------------------------------------------------------------------------------ abertura

  /**
   * `session.hello` + bundle no disco + `preview.load`. O `hello` vem sem `token` no painel (PP §1.1).
   * `source` é o projeto a mostrar (ou quem o lê do disco: a falha da leitura também vira erro da sessão); o runtime fica com a página viva até `dispose`.
   */
  async open(source: ProjectInput | (() => Promise<ProjectInput>)): Promise<SessionHelloResult> {
    this.set({ status: 'connecting', error: null });
    try {
      const hello = await this.client.request('session.hello', {
        protocol: PROTOCOL_VERSION,
        studio_version: this.o.studioVersion ?? '0.0.0',
      });
      if (hello.protocol.split('.')[0] !== PROTOCOL_VERSION.split('.')[0]) {
        throw new Error(`protocolo ${hello.protocol} do runtime não é compatível com o ${PROTOCOL_VERSION} do Studio`);
      }
      this.set({ hello });
      await this.loadFull(typeof source === 'function' ? await source() : source);
      this.set({ status: 'ready' });
      return hello;
    } catch (err) {
      this.fail(err);
      throw err;
    }
  }

  private async loadFull(input: ProjectInput): Promise<void> {
    const compiled = compileProject(input, this.o.compile);
    await writeBundleFiles(this.o.fs, this.o.root, compiled);
    this.compiled = compiled;
    this.latest = input;
    const keep = this.o.keepSaves === true;
    const result = await this.client.request('preview.load', {
      bundle_url: this.o.urls.bundleUrl,
      assets_base: this.o.urls.assetsBase,
      ...(this.o.locale ? { locale: this.o.locale } : {}),
      user_data: keep ? 'project' : 'memory',
      ...(keep ? { user_files: await readUserFiles(this.o.fs, this.o.root) } : {}),
    });
    const filter = (compiled.bundle as unknown as { project?: { content_filter?: { default?: boolean } } }).project?.content_filter?.default;
    this.set({ runState: 'LOADED', contentHash: result.content_hash, contentFilter: this.snap.contentFilter || filter === true });
  }

  // ------------------------------------------------------------------------------------------ recarga

  /**
   * A cada edição: manda o patch das entidades que mudaram. Edições em sequência se enfileiram, e só a
   * última importa se chegarem várias enquanto uma recarga está em curso (o runtime responde `BUSY` a
   * uma segunda requisição longa).
   */
  update(input: ProjectInput): Promise<ReloadOutcome> {
    this.latest = input;
    const run = this.queue.then(() => (this.latest === input ? this.reloadNow(input) : { kind: 'none' as const }));
    this.queue = run.catch(() => undefined);
    return run;
  }

  /** Recarga completa pedida pelo autor ("Recarregar tudo"). */
  reloadAll(input: ProjectInput, reason = 'pedido do autor'): Promise<ReloadOutcome> {
    this.latest = input;
    const run = this.queue.then(() => this.fullReload(input, [reason], reason));
    this.queue = run.catch(() => undefined);
    return run;
  }

  private async reloadNow(input: ProjectInput): Promise<ReloadOutcome> {
    const prev = this.compiled;
    if (!prev) throw new Error('o Preview ainda não carregou o projeto');
    const plan = planReload(prev, input, this.o.compile);
    if (plan.fullReload.length > 0) return this.fullReload(input, plan.fullReload, `mudou ${plan.fullReload.join(', ')}`);
    if (plan.patch.length === 0) return { kind: 'none' };
    const t0 = this.now();
    try {
      const next = rehash(applyPatch(prev, plan.patch));
      await writeBundleFiles(this.o.fs, this.o.root, next, new Set([...filesTouchedBy(plan.patch), 'bundle.json']));
      const result = await this.client.request('preview.reload', { patch: plan.patch as [PatchOp, ...PatchOp[]] });
      this.compiled = next;
      const ms = this.now() - t0;
      const r = this.snap.reloads;
      this.set({
        reloads: { ...r, incremental: r.incremental + 1, sinceFull: r.sinceFull + 1, lastMs: ms, lastResumed: result.resumed, lastKind: 'incremental' },
      });
      if (this.snap.reloads.sinceFull >= FULL_RELOAD_EVERY) {
        // PP §3: a cada 50 incrementais, uma completa confere que a memória bate com o disco.
        await this.fullReload(input, ['conferência periódica'], `${FULL_RELOAD_EVERY} recargas incrementais`);
      }
      return { kind: 'incremental', ops: plan.patch.length, ms, resumed: result.resumed };
    } catch (err) {
      if (this.disposed || (err instanceof PreviewRpcError && err.dataCode !== 'BUNDLE_INVALID')) throw err;
      // Patch recusado (BUNDLE_INVALID, incluindo full_reload_required) ou falha ao gravar: recarga completa.
      const why = err instanceof PreviewRpcError ? `${err.detail ?? err.dataCode}${typeof err.data?.path === 'string' ? ` em ${err.data.path}` : ''}` : String(err);
      this.log('warning', 'studio', `recarga incremental recusada (${why}); recarregando por completo`);
      return this.fullReload(input, [why], why);
    }
  }

  private async fullReload(input: ProjectInput, changed: readonly string[], reason: string): Promise<ReloadOutcome> {
    const t0 = this.now();
    const compiled = compileProject(input, this.o.compile);
    await writeBundleFiles(this.o.fs, this.o.root, compiled);
    this.compiled = compiled;
    const result = await this.client.request('preview.reload', { bundle_url: this.o.urls.bundleUrl, changed: changedFiles(changed) });
    const ms = this.now() - t0;
    const r = this.snap.reloads;
    this.set({
      contentHash: result.content_hash ?? (compiled.bundle as unknown as { content_hash: string }).content_hash,
      reloads: { ...r, full: r.full + 1, sinceFull: 0, lastMs: ms, lastResumed: result.resumed, lastKind: 'full', lastFullReason: reason },
    });
    return { kind: 'full', reason, ms, resumed: result.resumed };
  }

  // ------------------------------------------------------------------------------------------ métodos do §3

  async start(params: PreviewStartParams = {}): Promise<GameState> {
    const state = await this.client.request('preview.start', params);
    this.applyGameState(state);
    this.set({ runState: state.preview });
    return state;
  }

  async stop(): Promise<void> {
    await this.client.request('preview.stop', {});
    this.set({ runState: 'LOADED', phase: 'TITLE', scene: null, node: null });
  }

  async pause(): Promise<void> {
    await this.client.request('preview.pause', {});
    this.set({ runState: 'PAUSED' });
  }

  async resume(): Promise<void> {
    await this.client.request('preview.resume', {});
    this.set({ runState: 'RUNNING' });
  }

  async step(until?: NonNullable<PreviewMethods['preview.step'][0]['until']>): Promise<PreviewMethods['preview.step'][1]> {
    const result = await this.client.request('preview.step', until ? { until } : {});
    this.set({ node: result.node, phase: result.phase });
    return result;
  }

  input(params: PreviewMethods['preview.input'][0]): Promise<PreviewMethods['preview.input'][1]> {
    return this.client.request('preview.input', params);
  }

  setVariables(variables: PreviewMethods['preview.set_variables'][0]['variables']): Promise<PreviewMethods['preview.set_variables'][1]> {
    return this.client.request('preview.set_variables', { variables });
  }

  async getState(include?: PreviewMethods['preview.get_state'][0]['include']): Promise<GameState> {
    const state = await this.client.request('preview.get_state', include ? { include } : {});
    this.applyGameState(state);
    return state;
  }

  explainSelection(scene?: string): Promise<PreviewMethods['preview.explain_selection'][1]> {
    return this.client.request('preview.explain_selection', scene ? { scene } : {});
  }

  reloadPlugins(ids: [string, ...string[]]): Promise<PreviewMethods['preview.reload_plugins'][1]> {
    return this.client.request('preview.reload_plugins', { ids });
  }

  async showScreen(screen: string, simulate?: PreviewMethods['preview.show_screen'][0]['simulate']): Promise<void> {
    await this.client.request('preview.show_screen', { screen, ...(simulate ? { simulate } : {}) });
  }

  async setSetting(setting: string, value: unknown): Promise<void> {
    await this.client.request('preview.set_setting', { setting, value });
  }

  async setLocale(locale: string): Promise<void> {
    await this.client.request('preview.set_locale', { locale });
  }

  /** Botão "Modo stream" da barra do Preview (Req §11.2): liga e desliga o modo no jogo em execução. */
  async setContentFilter(on: boolean): Promise<void> {
    await this.setSetting('content_filter', on);
    this.set({ contentFilter: on });
  }

  // ------------------------------------------------------------------------------------------ notificações

  private applyGameState(state: GameState): void {
    this.set({ phase: state.phase, scene: state.scene ?? null, node: state.node ?? null });
  }

  private onNotification(n: PreviewNotification): void {
    const p = n.params;
    const str = (v: unknown): string | null => (typeof v === 'string' ? v : null);
    if (typeof p.phase === 'string' && p.phase !== this.snap.phase) this.set({ phase: p.phase });
    switch (n.method) {
      case 'node.entered':
        this.set({ scene: str(p.scene), node: str(p.node) });
        break;
      case 'scene.started':
        this.set({ scene: str(p.scene) });
        break;
      case 'game.ended':
        this.set({ runState: 'LOADED' });
        break;
      case 'session.closing':
        this.set({ status: 'closed' });
        this.log('info', 'runtime', `o runtime vai fechar (${str(p.reason) ?? '?'})`);
        break;
      case 'storage.write':
        void this.applyStorage('write', p);
        break;
      case 'storage.delete':
        void this.applyStorage('delete', p);
        break;
      case 'log':
        this.log(['debug', 'info', 'warning', 'error'].includes(String(p.level)) ? (p.level as LogEntry['level']) : 'info', 'runtime', String(p.message ?? ''));
        break;
      case 'error':
        this.log('error', 'runtime', `${String(p.code ?? '')}: ${String(p.message ?? '')}`);
        break;
      case 'plugin.log':
        this.log(['debug', 'info', 'warning', 'error'].includes(String(p.level)) ? (p.level as LogEntry['level']) : 'info', 'plugin', `${String(p.plugin ?? '')}: ${String(p.message ?? '')}`);
        break;
      case 'plugin.permission_denied':
        this.log('warning', 'plugin', `${String(p.plugin ?? '')} chamou ${String(p.call ?? '')} sem a permissão ${String(p.capability ?? '')}`);
        break;
      case 'plugin.faulted':
        this.log('error', 'plugin', `${String(p.plugin ?? '')} falhou: ${String(p.error ?? '')}`);
        break;
      default:
        break;
    }
  }

  /** `storage.write` / `storage.delete` (PP §1.4): só dentro de `.vnstudio/preview/user/` e só com `user_data: "project"`. */
  private async applyStorage(kind: 'write' | 'delete', p: PreviewNotification['params']): Promise<void> {
    if (this.o.keepSaves !== true) {
      this.log('warning', 'studio', `storage.${kind} recusado: "Manter saves do Preview" está desligado`);
      return;
    }
    const rel = safeUserPath(p.path);
    if (!rel) {
      this.log('warning', 'studio', `storage.${kind} recusado: caminho inválido ${JSON.stringify(p.path)}`);
      return;
    }
    const target = joinPath(this.o.root, PREVIEW_USER_DIR, rel);
    try {
      if (kind === 'delete') {
        await this.o.fs.removeFile(target);
        return;
      }
      const text = fromBase64(p.data);
      if (text === null) {
        this.log('warning', 'studio', `storage.write recusado: ${rel} não é texto UTF-8 em base64`);
        return;
      }
      await this.o.fs.writeText(target, text);
    } catch (err) {
      this.log('error', 'studio', `storage.${kind} de ${rel} falhou: ${String(err)}`);
    }
  }

  // ------------------------------------------------------------------------------------------ fim

  private fail(err: unknown): void {
    const message = err instanceof PreviewRpcError && err.dataCode === 'INTERNAL' ? `${err.message} (reabra o Preview)` : err instanceof Error ? err.message : String(err);
    this.set({ status: 'error', error: message });
    this.log('error', 'studio', message);
  }

  /** Fecha o painel: a página é descartada, sem processo para encerrar (PP §1.1, item 4). */
  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.client.close();
    this.set({ status: 'closed', runState: null });
  }
}
