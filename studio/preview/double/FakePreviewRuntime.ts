/**
 * Dublê do runtime do Preview (M0-09): um servidor falso que fala o JSON-RPC da spec 07 com respostas válidas
 * pelo `preview-protocol.schema.json`. Serve aos testes e ao desenvolvimento do Studio (Preview, painel
 * "por que não apareceu", Menu Editor) enquanto o runtime Web não existe (M6-14).
 *
 * O que ele faz de verdade: estados do Preview (§2), autenticação do `hello` (§1.1, §1.2), todos os métodos do §3
 * com os erros do §6, notificações com `seq` e `phase` na ordem do §4.2, `GameState` (§5), dados do jogador no
 * painel (§1.4) e recarga incremental (§3). Ele anda pelas cenas no formato do Data Model com um subconjunto da
 * lógica (`logic.ts`). O que ele não faz: rodar o Scheduler (usa avaliações gravadas por capítulo,
 * `DoubleChapter.selections`), validar `params`/`payload` de atividades contra os schemas dos plugins, agrupar
 * notificações (`batch`, §4.1, que é opcional) e desenhar qualquer coisa.
 */
import { evalCondition, evalValue, effectWrites, interpolate, VariableStore, WriteError, type Change } from './logic';
import type {
  DoubleActivity,
  DoubleChapter,
  DoubleStory,
  EnginePhase,
  JsonObject,
  Literal,
  MessageValidator,
  OutgoingMessage,
  PreviewState,
  RecordedSelection,
  RpcErrorObject,
  RpcRequest,
  SceneEntity,
  SceneNode,
  Transport,
} from './types';
import type { GameState, SchedulerEvaluation } from '@vnstudio/plugin-schema';

export const PROTOCOL_VERSION = '1.0';

/** Códigos do §6. */
export const RpcCode = {
  PARSE_ERROR: -32700,
  INVALID_REQUEST: -32600,
  METHOD_NOT_FOUND: -32601,
  INVALID_PARAMS: -32602,
  UNAUTHENTICATED: -32001,
  UNSUPPORTED_VERSION: -32002,
  INVALID_PREVIEW_STATE: -32003,
  BUNDLE_INVALID: -32004,
  NOT_FOUND: -32005,
  STATE_REJECTED: -32006,
  BUSY: -32007,
  INTERNAL: -32099,
} as const;

/** Código de fechamento do WebSocket na janela (§1.2). */
export const CloseCode = { NORMAL: 1000, UNAUTHENTICATED: 4401, CONFLICT: 4409 } as const;

type ErrorName = 'UNAUTHENTICATED' | 'UNSUPPORTED_VERSION' | 'INVALID_PREVIEW_STATE' | 'BUNDLE_INVALID' | 'NOT_FOUND' | 'STATE_REJECTED' | 'BUSY' | 'INTERNAL';

class RpcFailure extends Error {
  constructor(readonly error: RpcErrorObject) {
    super(error.message);
  }
}

function fail(name: ErrorName, message: string, data: JsonObject = {}): never {
  throw new RpcFailure({ code: RpcCode[name], message, data: { code: name, ...data } });
}

function invalidParams(message: string): never {
  throw new RpcFailure({ code: RpcCode.INVALID_PARAMS, message, data: { detail: message } });
}

/** Estados em que cada método é aceito (tabela do §3). */
const AFTER_LOAD: PreviewState[] = ['LOADED', 'RUNNING', 'PAUSED'];
const METHOD_STATES: Record<string, PreviewState[]> = {
  'session.hello': ['CONNECTED'],
  'preview.load': ['READY', 'LOADED'],
  'preview.start': ['LOADED'],
  'preview.stop': ['RUNNING', 'PAUSED'],
  'preview.pause': ['RUNNING'],
  'preview.resume': ['PAUSED'],
  'preview.step': ['PAUSED'],
  'preview.input': ['LOADED', 'RUNNING', 'PAUSED'],
  'preview.set_variables': ['RUNNING', 'PAUSED'],
  'preview.get_state': AFTER_LOAD,
  'preview.explain_selection': ['RUNNING', 'PAUSED'],
  'preview.reload': AFTER_LOAD,
  'preview.reload_plugins': AFTER_LOAD,
  'preview.show_screen': AFTER_LOAD,
  'preview.set_setting': AFTER_LOAD,
  'preview.set_locale': AFTER_LOAD,
};

/** Requisições longas (§6, `BUSY`). */
const LONG_METHODS = new Set(['preview.load', 'preview.reload']);

/** Marca de `dispatch` para quando a conexão foi fechada e não há resposta (janela, token errado). */
const CLOSED_SILENTLY = Symbol('closed');

const ENTITY_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

export interface FakePreviewRuntimeOptions {
  /** Conteúdo carregado em `preview.load`. Padrão: a demo das specs (`demoStory`). */
  story: DoubleStory;
  /** `panel` (padrão): `hello` sem token, erros `UNAUTHENTICATED`. `window`: token obrigatório, fechamento 4401. */
  transport?: Transport;
  /** Token esperado no `hello` da janela (64 hex). */
  token?: string;
  /** Validação das mensagens (testes: `loadProtocolSchema()` de `schema.ts`). Mensagem inválida do dublê lança. */
  validator?: MessageValidator;
  runtimeVersion?: string;
  godotVersion?: string;
  /** Plataforma informada na janela; no painel é sempre `web`. */
  platform?: 'windows' | 'macos' | 'linux';
  /** Prazo do `hello` (§1.2: 5 s). `null` desliga. */
  helloTimeoutMs?: number | null;
  /** Atraso das respostas de `load` e `reload`, para exercitar `BUSY`. Padrão 0 (sem atraso). */
  longRequestMs?: number;
}

interface Waiting {
  kind: 'line' | 'choice' | 'interact' | 'activity';
  node: SceneNode;
}

interface RunningActivity {
  id: string;
  plugin: string;
  def: DoubleActivity;
  mode: 'story' | 'free_play';
  scene?: string;
  node?: SceneNode;
}

interface StageCharacter {
  id: string;
  expression?: string;
  position?: string | number;
}

type Until = 'wait' | 'node' | 'blocking' | 'scene_end' | 'selection';

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function toBase64(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

const isObject = (v: unknown): v is JsonObject => typeof v === 'object' && v !== null && !Array.isArray(v);
const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined);

export class FakePreviewRuntime {
  /** A ponte entrega cada mensagem do runtime aqui, em texto (como `vnPreview.onmessage`). */
  onmessage: ((text: string) => void) | null = null;
  /** Janela: o runtime fechou a conexão com este código (§1.2). */
  onclose: ((code: number) => void) | null = null;

  /** Toda mensagem que o dublê mandou, em ordem (para os testes). */
  readonly sent: OutgoingMessage[] = [];
  /** Método da requisição a que cada resposta de `sent` responde. */
  readonly respondsTo = new WeakMap<OutgoingMessage, string>();
  /** Arquivos do `VNStorage` do Preview: caminho relativo → base64 (§1.4). */
  readonly storage = new Map<string, string>();
  /** Tela aberta por `preview.show_screen`, com os valores fingidos. */
  screen: { screen: string; simulate?: JsonObject } | null = null;

  private readonly opts: Required<Omit<FakePreviewRuntimeOptions, 'validator' | 'token' | 'platform'>> &
    Pick<FakePreviewRuntimeOptions, 'validator' | 'token' | 'platform'>;
  private previewState: PreviewState = 'CONNECTED';
  private helloTimer: ReturnType<typeof setTimeout> | null = null;
  private busyTimer = false;
  private seq = 0;

  // Conteúdo carregado (cópia da história, alterada pelas recargas).
  private story: DoubleStory | null = null;
  private userData: 'memory' | 'project' = 'memory';
  private locale = '';
  private settings: Record<string, Literal> = {};
  private profileEndings: string[] = [];

  // Jogo em andamento.
  private phase: EnginePhase = 'BOOT';
  private vars = new VariableStore();
  private chapter: DoubleChapter | null = null;
  private scene: SceneEntity | null = null;
  private cursor: string | null = null;
  private waiting: Waiting | null = null;
  private activity: RunningActivity | null = null;
  private contentFilter = false;
  private usedHotspots = new Set<string>();
  private selectionIndex = new Map<string, number>();
  private history = {
    selection_count: 0,
    scenes: {} as Record<string, { plays: number; starts: number; last_selection?: number }>,
    chapters: {} as Record<string, { entries: number; completed: boolean }>,
  };
  private stage = {
    background: null as string | null,
    set: null as string | null,
    set_states: {} as Record<string, string>,
    characters: [] as StageCharacter[],
    audio: {} as Record<string, { asset: string; loop?: boolean; volume?: number }>,
  };
  private backlog: { speaker: string | null; text: string }[] = [];
  private rng: { seed: string; state: string } | null = null;
  private autosaveSlot = 0;

  constructor(options: FakePreviewRuntimeOptions) {
    this.opts = {
      transport: 'panel',
      runtimeVersion: '1.0.0',
      godotVersion: '4.7.2',
      helloTimeoutMs: 5000,
      longRequestMs: 0,
      ...options,
    };
    if (this.opts.helloTimeoutMs !== null) {
      this.helloTimer = setTimeout(() => this.helloExpired(), this.opts.helloTimeoutMs);
    }
  }

  /** Estado atual do Preview (§2). */
  get state(): PreviewState {
    return this.previewState;
  }

  /** Recebe uma mensagem do Studio, em texto (como `vnPreview.send`). */
  send(text: string): void {
    if (this.previewState === 'CLOSED') return;
    let message: unknown;
    try {
      message = JSON.parse(text);
    } catch {
      this.respondError(null, { code: RpcCode.PARSE_ERROR, message: 'JSON inválido' });
      return;
    }
    if (Array.isArray(message)) {
      this.respondError(null, { code: RpcCode.INVALID_REQUEST, message: 'lotes não são aceitos (§1.1, §1.2)' });
      return;
    }
    const id = isObject(message) && (typeof message.id === 'number' || typeof message.id === 'string') ? message.id : null;
    if (!isObject(message) || message.jsonrpc !== '2.0' || typeof message.method !== 'string' || id === null) {
      this.respondError(id, { code: RpcCode.INVALID_REQUEST, message: 'requisição JSON-RPC 2.0 inválida' });
      return;
    }
    if ('params' in message && !isObject(message.params)) {
      this.respondError(id, { code: RpcCode.INVALID_PARAMS, message: 'params deve ser um objeto' });
      return;
    }
    const request = message as unknown as RpcRequest;
    const method = request.method;

    if (this.previewState === 'CONNECTED' && method !== 'session.hello') {
      this.unauthenticated(id, 'mensagem antes do session.hello');
      return;
    }
    if (!(method in METHOD_STATES)) {
      this.respondError(id, { code: RpcCode.METHOD_NOT_FOUND, message: `método inexistente: ${method}` });
      return;
    }
    const shapeError = this.opts.validator?.checkRequest(request);
    if (shapeError) {
      this.respondError(id, { code: RpcCode.INVALID_PARAMS, message: `parâmetros inválidos: ${shapeError}`, data: { detail: shapeError } }, method);
      return;
    }
    if (this.busyTimer) {
      this.respondError(id, { code: RpcCode.BUSY, message: 'outra requisição longa ainda em curso', data: { code: 'BUSY' } }, method);
      return;
    }

    try {
      const allowed = METHOD_STATES[method] as PreviewState[];
      if (!allowed.includes(this.previewState)) {
        fail('INVALID_PREVIEW_STATE', `${method} não é aceito em ${this.previewState}`, { state: this.previewState });
      }
      const result = this.dispatch(method, request.params ?? {});
      if (result === CLOSED_SILENTLY) return;
      if (LONG_METHODS.has(method) && this.opts.longRequestMs > 0) {
        this.busyTimer = true;
        const response = this.validated({ jsonrpc: '2.0', id, result }, method);
        setTimeout(() => {
          this.busyTimer = false;
          this.deliver(response);
        }, this.opts.longRequestMs);
        return;
      }
      this.respond(id, result, method);
    } catch (err) {
      if (err instanceof RpcFailure) {
        this.respondError(id, err.error, method);
        return;
      }
      throw err;
    }
  }

  /**
   * Manda uma notificação gravada (por exemplo, `plugin.faulted` ou um `error` de conteúdo), com `seq` e `phase`
   * da sessão quando não vierem. Lança se ela não validar.
   */
  notify(method: string, params: JsonObject = {}): void {
    this.emit(method, params);
  }

  /** Manda uma sequência gravada de notificações, renumerando `seq` na ordem da sessão. */
  replay(recording: { method: string; params?: JsonObject }[]): void {
    for (const { method, params } of recording) {
      const { seq: _seq, ...rest } = params ?? {};
      void _seq;
      this.emit(method, rest);
    }
  }

  /** O runtime vai fechar (§1.2, passo 5): `session.closing`, e na janela fecha com 1000. */
  close(reason: 'window_closed' | 'stop' | 'error' = 'window_closed'): void {
    if (this.previewState === 'CLOSED') return;
    if (this.previewState !== 'CONNECTED') this.emit('session.closing', { reason });
    this.shutdown(CloseCode.NORMAL);
  }

  // ---------------------------------------------------------------------------------------------------------
  // Transporte

  private helloExpired(): void {
    this.helloTimer = null;
    if (this.previewState !== 'CONNECTED') return;
    this.unauthenticated(null, 'session.hello não chegou em 5 segundos');
  }

  private unauthenticated(id: number | string | null, message: string): void {
    if (this.opts.transport === 'window') {
      this.shutdown(CloseCode.UNAUTHENTICATED);
      return;
    }
    this.respondError(id, { code: RpcCode.UNAUTHENTICATED, message, data: { code: 'UNAUTHENTICATED' } });
  }

  private shutdown(code: number): void {
    if (this.helloTimer) clearTimeout(this.helloTimer);
    this.helloTimer = null;
    this.previewState = 'CLOSED';
    if (this.opts.transport === 'window') queueMicrotask(() => this.onclose?.(code));
  }

  private respond(id: number | string, result: unknown, method: string): void {
    this.deliver(this.validated({ jsonrpc: '2.0', id, result }, method));
  }

  private respondError(id: number | string | null, error: RpcErrorObject, method?: string): void {
    this.deliver(this.validated({ jsonrpc: '2.0', id, error }, method));
  }

  private emit(method: string, params: JsonObject): void {
    const message: OutgoingMessage = { jsonrpc: '2.0', method, params: { seq: this.seq + 1, phase: this.phase, ...params } };
    this.deliver(this.validated(message));
    this.seq += 1;
  }

  private validated(message: OutgoingMessage, requestMethod?: string): OutgoingMessage {
    if (requestMethod) this.respondsTo.set(message, requestMethod);
    const problem = this.opts.validator?.checkOutgoing(message, requestMethod);
    if (problem) {
      throw new Error(`o dublê do Preview montou uma mensagem inválida (${JSON.stringify(message).slice(0, 300)}): ${problem}`);
    }
    return message;
  }

  private deliver(message: OutgoingMessage): void {
    this.sent.push(message);
    const text = JSON.stringify(message);
    queueMicrotask(() => this.onmessage?.(text));
  }

  // ---------------------------------------------------------------------------------------------------------
  // Métodos (§3)

  private dispatch(method: string, p: JsonObject): unknown {
    switch (method) {
      case 'session.hello':
        return this.hello(p);
      case 'preview.load':
        return this.load(p);
      case 'preview.start':
        return this.start(p);
      case 'preview.stop':
        this.endGameSession();
        this.previewState = 'LOADED';
        return {};
      case 'preview.pause':
        this.previewState = 'PAUSED';
        return { node: this.cursor };
      case 'preview.resume':
        this.previewState = 'RUNNING';
        this.run('wait');
        return { node: this.cursor };
      case 'preview.step':
        return this.step(str(p.until) ?? 'node');
      case 'preview.input':
        return this.input(p);
      case 'preview.set_variables':
        return this.setVariables(p);
      case 'preview.get_state':
        return this.gameState(Array.isArray(p.include) ? (p.include as string[]) : undefined);
      case 'preview.explain_selection':
        return this.explainSelection(str(p.scene));
      case 'preview.reload':
        return this.reload(p);
      case 'preview.reload_plugins':
        return this.reloadPlugins(p);
      case 'preview.show_screen':
        return this.showScreen(p);
      case 'preview.set_setting':
        return this.setSetting(p);
      case 'preview.set_locale':
        return this.setLocale(p);
    }
    throw new RpcFailure({ code: RpcCode.METHOD_NOT_FOUND, message: `método inexistente: ${method}` });
  }

  private hello(p: JsonObject): unknown {
    const protocol = str(p.protocol);
    if (!protocol || !/^[0-9]+\.[0-9]+$/.test(protocol)) invalidParams('protocol é obrigatório (MAJOR.MINOR)');
    if (this.opts.transport === 'window' && p.token !== this.opts.token) {
      this.shutdown(CloseCode.UNAUTHENTICATED);
      return CLOSED_SILENTLY;
    }
    if (protocol.split('.')[0] !== PROTOCOL_VERSION.split('.')[0]) {
      fail('UNSUPPORTED_VERSION', `protocolo ${protocol} sem suporte; o runtime fala ${PROTOCOL_VERSION}`);
    }
    if (this.helloTimer) clearTimeout(this.helloTimer);
    this.helloTimer = null;
    this.previewState = 'READY';
    const features = ['show_screen'];
    if (this.opts.story.reproducible_rng) features.unshift('reproducible_rng');
    return {
      runtime_version: this.opts.runtimeVersion,
      godot_version: this.opts.godotVersion,
      protocol: PROTOCOL_VERSION,
      platform: this.opts.transport === 'panel' ? 'web' : (this.opts.platform ?? 'linux'),
      features,
    };
  }

  private checkBundleLocation(p: JsonObject, field: 'bundle_path' | 'bundle_url'): void {
    const value = str(p[field]);
    if (value === undefined) return;
    const expected = this.opts.transport === 'window' ? 'bundle_path' : 'bundle_url';
    if (field !== expected) {
      fail('BUNDLE_INVALID', `${field} não é usado no transporte ${this.opts.transport}; use ${expected}`, { path: field, detail: 'wrong_transport' });
    }
    // §7: o bundle DEVE estar na pasta de build temporária do Studio.
    const inPreviewDir = field === 'bundle_url' ? value.includes('/project/preview/') : /(^|[\\/])\.vnstudio[\\/]preview([\\/]|$)/.test(value);
    if (!inPreviewDir) {
      fail('BUNDLE_INVALID', `${field} fora de .vnstudio/preview/`, { path: field, detail: 'outside_preview_dir' });
    }
  }

  private load(p: JsonObject): unknown {
    this.checkBundleLocation(p, 'bundle_path');
    this.checkBundleLocation(p, 'bundle_url');
    if (p.bundle_path === undefined && p.bundle_url === undefined) invalidParams('bundle_path ou bundle_url é obrigatório');
    const story = clone(this.opts.story);
    const locale = str(p.locale) ?? story.default_locale;
    if (!story.locales.includes(locale)) fail('NOT_FOUND', `idioma ${locale} não está no projeto`, { kind: 'locale', id: locale });

    this.endGameSession();
    this.story = story;
    this.locale = locale;
    this.userData = p.user_data === 'project' ? 'project' : 'memory';
    this.storage.clear();
    if (this.userData === 'project' && isObject(p.user_files)) {
      for (const [path, data] of Object.entries(p.user_files)) if (typeof data === 'string') this.storage.set(path, data);
    }
    this.settings = { ...story.settings, ...this.storedSettings() };
    this.profileEndings = [];
    this.contentFilter = this.settings.content_filter === true;
    this.resetVariables();
    this.screen = null;
    this.previewState = 'LOADED';
    this.phase = 'TITLE';
    const enabled = Object.entries(story.plugins).filter(([, plugin]) => plugin.enabled !== false);
    return {
      content_hash: story.content_hash,
      format_version: story.format_version,
      chapters: story.chapters.length,
      scenes: story.scenes.length,
      plugins: enabled.map(([id]) => id),
    };
  }

  private storedSettings(): Record<string, Literal> {
    const data = this.storage.get('settings.json');
    if (!data) return {};
    try {
      const bytes = Uint8Array.from(atob(data), (c) => c.charCodeAt(0));
      const parsed: unknown = JSON.parse(new TextDecoder().decode(bytes));
      return isObject(parsed) ? (parsed as Record<string, Literal>) : {};
    } catch {
      return {};
    }
  }

  private start(p: JsonObject): unknown {
    const story = this.requireStory();
    const sceneId = str(p.scene);
    const nodeId = str(p.node);
    const chapterId = str(p.chapter);
    const scene = sceneId ? story.scenes.find((s) => s.id === sceneId) : undefined;
    if (sceneId && !scene) fail('NOT_FOUND', `cena ${sceneId} não existe`, { kind: 'scene', id: sceneId });
    if (nodeId && !scene) invalidParams('node só vale junto com scene');
    if (nodeId && scene && !scene.nodes.some((n) => n.id === nodeId)) {
      fail('NOT_FOUND', `nó ${nodeId} não existe na cena`, { kind: 'node', id: nodeId });
    }
    const chapter = this.findChapter(scene?.chapter ?? chapterId ?? story.start_chapter);
    if (!chapter) {
      const id = scene?.chapter ?? chapterId ?? story.start_chapter;
      fail('NOT_FOUND', `capítulo ${id} não existe`, { kind: 'chapter', id });
    }

    // Variáveis do perfil e do pedido valem depois dos defaults; um valor inválido recusa o start inteiro.
    this.endGameSession();
    this.resetVariables();
    if (isObject(p.profile)) {
      const profile = p.profile as { variables?: JsonObject; endings?: string[] };
      this.profileEndings = Array.isArray(profile.endings) ? [...profile.endings] : [];
      this.applyStartValues(profile.variables, false);
    }
    this.contentFilter = typeof p.content_filter === 'boolean' ? p.content_filter : this.settings.content_filter === true;
    this.vars.setSys('sys.content_filter', this.contentFilter);
    if (typeof p.seed === 'string' && story.reproducible_rng) this.rng = { seed: p.seed, state: p.seed };

    this.previewState = p.paused === true ? 'PAUSED' : 'RUNNING';
    if (scene) {
      this.enterChapter(chapter, false);
      this.startScene(scene, 'start');
      if (nodeId) this.cursor = nodeId;
    } else {
      this.phase = 'NEW_GAME';
      this.enterChapter(chapter, true);
    }
    try {
      this.applyStartValues(p.variables, true);
    } catch (err) {
      this.endGameSession();
      this.previewState = 'LOADED';
      throw err;
    }
    if (this.previewState === 'RUNNING') this.run('wait');
    return this.gameState();
  }

  private applyStartValues(values: unknown, strict: boolean): void {
    if (!isObject(values)) return;
    try {
      this.vars.commit(Object.entries(values).map(([variable, value]) => ({ variable, value: value as Literal })));
    } catch (err) {
      if (err instanceof WriteError && strict) this.rejectWrite(err);
      if (!(err instanceof WriteError)) throw err;
    }
  }

  private rejectWrite(err: WriteError): never {
    fail('STATE_REJECTED', err.message, { vn_code: err.vnCode, detail: err.variable });
  }

  private step(until: string): unknown {
    if (this.waiting?.kind === 'line') this.leaveLine();
    if (!this.waiting) this.run(until as Until);
    return { node: this.cursor, phase: this.phase };
  }

  private input(p: JsonObject): unknown {
    const action = str(p.action);
    if (this.previewState === 'LOADED' && !['play_activity', 'complete_activity', 'cancel_activity', 'skip_activity'].includes(action ?? '')) {
      fail('INVALID_PREVIEW_STATE', `${action} não é aceito em LOADED`, { state: 'LOADED' });
    }
    const accepted = this.handleInput(action, p);
    if (accepted && this.previewState === 'RUNNING') this.run('wait');
    return { accepted };
  }

  private handleInput(action: string | undefined, p: JsonObject): boolean {
    const w = this.waiting;
    switch (action) {
      case 'advance':
        if (w?.kind === 'line') {
          this.leaveLine();
          return true;
        }
        if (w?.kind === 'interact' && isObject(w.node.exit)) {
          this.waiting = null;
          this.goto(w.node, str(w.node.exit.goto));
          return true;
        }
        return false;
      case 'choose':
        return this.choose(str(p.option) ?? '');
      case 'click':
        return this.click(str(p.hotspot) ?? '');
      case 'complete_activity': {
        const outcome = str(p.outcome) ?? '';
        if (!this.activity || !this.activity.def.outcomes.includes(outcome)) return false;
        this.finishActivity(outcome, isObject(p.payload) ? p.payload : {}, false);
        return true;
      }
      case 'skip_activity': {
        const a = this.activity;
        if (!a || a.mode !== 'story' || !a.def.skippable) return false;
        this.finishActivity(a.def.default_outcome ?? null, {}, true);
        return true;
      }
      case 'cancel_activity':
        if (!this.activity || this.activity.mode !== 'free_play') return false;
        this.finishActivity('cancelled', {}, false);
        return true;
      case 'play_activity':
        return this.playActivity(str(p.activity) ?? '', isObject(p.params) ? p.params : {});
    }
    invalidParams(`ação desconhecida: ${String(action)}`);
  }

  private choose(optionId: string): boolean {
    const w = this.waiting;
    if (w?.kind !== 'choice') return false;
    const options = Array.isArray(w.node.options) ? (w.node.options as JsonObject[]) : [];
    const option = options.find((o) => o.id === optionId);
    if (!option) fail('NOT_FOUND', `opção ${optionId} não está na escolha atual`, { kind: 'option', id: optionId });
    if (!evalCondition(option.visible_if, this.ctx()) || !evalCondition(option.enabled_if, this.ctx())) return false;
    const writes = effectWrites(option.effects, this.vars, this.ctx());
    const record = str(w.node.record);
    if (record) writes.unshift({ variable: record, value: str(option.value) ?? optionId });
    this.waiting = null;
    this.applyWrites(writes, 'choice', w.node);
    this.goto(w.node, str(option.goto));
    return true;
  }

  private click(hotspotId: string): boolean {
    const w = this.waiting;
    if (w?.kind !== 'interact') return false;
    const hotspots = Array.isArray(w.node.hotspots) ? (w.node.hotspots as JsonObject[]) : [];
    const hotspot = hotspots.find((h) => h.id === hotspotId);
    if (!hotspot) fail('NOT_FOUND', `hotspot ${hotspotId} não está na interação atual`, { kind: 'hotspot', id: hotspotId });
    if (!this.hotspotVisible(hotspot) || !evalCondition(hotspot.enabled_if, this.ctx())) return false;
    if (hotspot.once === true) this.usedHotspots.add(hotspotId);
    const writes = effectWrites(hotspot.effects, this.vars, this.ctx());
    const record = str(w.node.record);
    if (record) writes.unshift({ variable: record, value: str(hotspot.value) ?? hotspotId });
    this.waiting = null;
    this.applyWrites(writes, 'choice', w.node);
    // Sem goto, volta à mesma interação.
    this.cursor = str(hotspot.goto) ?? w.node.id;
    return true;
  }

  private hotspotVisible(h: JsonObject): boolean {
    return !this.usedHotspots.has(String(h.id)) && evalCondition(h.visible_if, this.ctx());
  }

  private playActivity(id: string, params: JsonObject): boolean {
    if (this.previewState !== 'LOADED' || this.activity) return false;
    const found = this.findActivity(id);
    if (!found) fail('NOT_FOUND', `atividade ${id} não existe`, { kind: 'activity', id });
    if (!found.def.free_play) return false;
    void params;
    this.activity = { id, plugin: found.plugin, def: found.def, mode: 'free_play' };
    this.phase = 'ACTIVITY';
    this.emit('activity.started', { activity: id, mode: 'free_play' });
    return true;
  }

  private setVariables(p: JsonObject): unknown {
    if (this.phase === 'ACTIVITY' && this.previewState === 'RUNNING') {
      fail('INVALID_PREVIEW_STATE', 'set_variables não é aceito em RUNNING durante uma atividade', { state: 'RUNNING' });
    }
    const values = isObject(p.variables) ? p.variables : {};
    let changes: Change[];
    try {
      changes = this.vars.commit(Object.entries(values).map(([variable, value]) => ({ variable, value: value as Literal })));
    } catch (err) {
      if (err instanceof WriteError) this.rejectWrite(err);
      throw err;
    }
    if (changes.length > 0) this.emit('state.changed', { changes, source: 'preview' });
    return { changes };
  }

  private explainSelection(sceneId: string | undefined): SchedulerEvaluation {
    const story = this.requireStory();
    if (sceneId && !story.scenes.some((s) => s.id === sceneId)) {
      fail('NOT_FOUND', `cena ${sceneId} não existe`, { kind: 'scene', id: sceneId });
    }
    const chapter = this.chapter;
    if (!chapter) fail('INVALID_PREVIEW_STATE', 'nenhum capítulo em andamento', { state: this.previewState });
    const recorded = this.peekSelection(chapter);
    const evaluation: SchedulerEvaluation = { ...recorded, selection_count: this.history.selection_count, chapter: chapter.id };
    if (sceneId) evaluation.candidates = evaluation.candidates.filter((c) => c.scene === sceneId);
    return evaluation;
  }

  private reload(p: JsonObject): unknown {
    const story = this.requireStory();
    if (Array.isArray(p.patch)) return this.applyPatch(story, p.patch);
    this.checkBundleLocation(p, 'bundle_path');
    this.checkBundleLocation(p, 'bundle_url');
    const running = this.previewState === 'RUNNING' || this.previewState === 'PAUSED';
    return { content_hash: story.content_hash, resumed: running ? 'node' : 'not_running' };
  }

  private applyPatch(story: DoubleStory, patch: unknown[]): unknown {
    // Valida a lista inteira antes de aplicar qualquer troca (§3: com erro, nada é aplicado).
    const ops = patch.map((raw, i) => {
      const item = raw as { file: string; pointer: string; value?: unknown };
      const path = `/patch/${i}`;
      const parts = item.pointer.split('/').slice(1).map((s) => s.replace(/~1/g, '/').replace(/~0/g, '~'));
      const [collection, key] = parts;
      if (item.file === 'bundle.json') {
        if (collection === 'project' || collection === 'variables' || collection === 'aliases') {
          fail('BUNDLE_INVALID', `${item.pointer} exige a recarga completa`, { path, detail: 'full_reload_required' });
        }
        const whole = collection === 'theme' ? parts.length === 1 : parts.length === 2;
        if (!whole || !['scenes', 'chapters', 'characters', 'ui', 'sets', 'assets', 'theme'].includes(collection ?? '')) {
          fail('BUNDLE_INVALID', `${item.pointer} não aponta uma entidade inteira do bundle`, { path: `${path}/pointer`, detail: 'pointer' });
        }
        if (collection === 'scenes' && item.value !== undefined) {
          const v = item.value as Partial<SceneEntity>;
          const nodesOk = Array.isArray(v.nodes) && v.nodes.length > 0 && v.nodes.every((n) => isObject(n) && ENTITY_ID.test(String(n.id)) && typeof n.type === 'string');
          if (!isObject(item.value) || v.id !== key || !nodesOk) {
            fail('BUNDLE_INVALID', `cena inválida em ${item.pointer}`, { path: `${path}/value`, detail: 'schema' });
          }
        }
        if (collection === 'chapters' && item.value !== undefined && (!isObject(item.value) || item.value.id !== key)) {
          fail('BUNDLE_INVALID', `capítulo inválido em ${item.pointer}`, { path: `${path}/value`, detail: 'schema' });
        }
      } else if (item.file === 'licenses.json') {
        if (item.pointer !== '/entries') fail('BUNDLE_INVALID', 'licenses.json só aceita /entries', { path: `${path}/pointer`, detail: 'pointer' });
      } else if (collection !== 'strings') {
        fail('BUNDLE_INVALID', `${item.pointer} não é um texto do idioma`, { path: `${path}/pointer`, detail: 'pointer' });
      }
      return { collection: item.file === 'bundle.json' ? collection : 'text', key: key ?? '', value: item.value };
    });

    let structural = false;
    let currentSceneChanged: 'kept' | 'replaced' | 'removed' = 'kept';
    for (const op of ops) {
      if (op.collection === 'scenes') {
        structural = true;
        const index = story.scenes.findIndex((s) => s.id === op.key);
        if (op.value === undefined) {
          if (index >= 0) story.scenes.splice(index, 1);
        } else if (index >= 0) story.scenes[index] = clone(op.value as SceneEntity);
        else story.scenes.push(clone(op.value as SceneEntity));
        if (this.scene?.id === op.key) currentSceneChanged = op.value === undefined ? 'removed' : 'replaced';
      } else if (op.collection === 'chapters') {
        structural = true;
        this.patchChapter(story, op.key, op.value);
      } else if (op.collection === 'ui') {
        story.screens = story.screens.filter((s) => s !== op.key);
        if (op.value !== undefined) story.screens.push(op.key);
      } else if (op.collection === 'characters' && isObject(op.value)) {
        const ch = { id: op.key, key: String(op.value.key ?? ''), name: String(op.value.name ?? '') };
        story.characters = [...story.characters.filter((c) => c.id !== op.key), ch];
      }
    }

    const running = this.previewState === 'RUNNING' || this.previewState === 'PAUSED';
    if (!running) return { resumed: 'not_running' };
    if (!structural) return { resumed: 'ui_only' };
    if (currentSceneChanged === 'removed') {
      this.waiting = null;
      this.endScene({ then: 'schedule' }, true);
      if (this.previewState === 'RUNNING') this.run('wait');
      return { resumed: 'selection_point' };
    }
    if (currentSceneChanged === 'replaced' && this.scene) {
      const fresh = story.scenes.find((s) => s.id === this.scene?.id) as SceneEntity;
      this.scene = fresh;
      const node = fresh.nodes.find((n) => n.id === this.cursor);
      if (node) {
        if (this.waiting) this.waiting = { ...this.waiting, node };
        return { resumed: 'node' };
      }
      this.waiting = null;
      this.activity = null;
      this.vars.dropScope('scene.');
      this.startScene(fresh, 'start');
      if (this.previewState === 'RUNNING') this.run('wait');
      return { resumed: 'scene_restarted' };
    }
    return { resumed: 'node' };
  }

  private patchChapter(story: DoubleStory, id: string, value: unknown): void {
    const index = story.chapters.findIndex((c) => c.id === id);
    if (value === undefined) {
      if (index >= 0) story.chapters.splice(index, 1);
      return;
    }
    const v = value as JsonObject;
    const old = index >= 0 ? story.chapters[index] : undefined;
    const next = Array.isArray(v.next) && isObject(v.next[0]) ? str(v.next[0].chapter) : old?.next;
    const updated: DoubleChapter = { ...old, id, title: str(v.title), entry_scene: str(v.entry_scene), next: next ?? null };
    if (index >= 0) story.chapters[index] = updated;
    else story.chapters.push(updated);
  }

  private reloadPlugins(p: JsonObject): unknown {
    const story = this.requireStory();
    const ids = (p.ids as string[]) ?? [];
    for (const id of ids) if (!story.plugins[id]) fail('NOT_FOUND', `plugin ${id} não existe`, { kind: 'plugin', id });
    return { reloaded: ids, activity_restarted: !!this.activity && ids.includes(this.activity.plugin) };
  }

  private showScreen(p: JsonObject): unknown {
    const story = this.requireStory();
    const screen = str(p.screen) ?? '';
    if (!story.screens.includes(screen)) fail('NOT_FOUND', `tela ${screen} não existe em ui/`, { kind: 'screen', id: screen });
    this.screen = { screen, ...(isObject(p.simulate) ? { simulate: p.simulate } : {}) };
    return {};
  }

  private setSetting(p: JsonObject): unknown {
    const setting = str(p.setting) ?? '';
    const value = p.value;
    if (!(setting in this.settings)) invalidParams(`configuração desconhecida: ${setting}`);
    if (typeof value !== typeof this.settings[setting]) invalidParams(`${setting} espera ${typeof this.settings[setting]}`);
    this.settings[setting] = value as Literal;
    if (setting === 'content_filter') {
      this.contentFilter = value === true;
      this.vars.setSys('sys.content_filter', this.contentFilter);
      this.emit('event.emitted', { name: 'sys.content_filter_changed', payload: { enabled: this.contentFilter }, source: 'ui' });
    }
    if (setting === 'locale' && typeof value === 'string' && this.story?.locales.includes(value)) this.locale = value;
    this.writeStorage('settings.json', JSON.stringify(this.changedSettings()));
    return {};
  }

  private changedSettings(): Record<string, Literal> {
    const base = this.story?.settings ?? {};
    return Object.fromEntries(Object.entries(this.settings).filter(([k, v]) => base[k] !== v || k === 'content_filter'));
  }

  private setLocale(p: JsonObject): unknown {
    const locale = str(p.locale) ?? '';
    if (!this.requireStory().locales.includes(locale)) fail('NOT_FOUND', `idioma ${locale} não está no projeto`, { kind: 'locale', id: locale });
    this.locale = locale;
    return {};
  }

  // ---------------------------------------------------------------------------------------------------------
  // Jogo

  private requireStory(): DoubleStory {
    if (!this.story) fail('INVALID_PREVIEW_STATE', 'nenhum bundle carregado', { state: this.previewState });
    return this.story;
  }

  private findChapter(id: string): DoubleChapter | undefined {
    return this.story?.chapters.find((c) => c.id === id);
  }

  private findActivity(id: string): { plugin: string; def: DoubleActivity } | null {
    const [namespace, name] = id.split('.');
    for (const [pluginId, plugin] of Object.entries(this.story?.plugins ?? {})) {
      if (plugin.namespace !== namespace || plugin.enabled === false) continue;
      const def = name ? plugin.activities[name] : undefined;
      if (def) return { plugin: pluginId, def };
    }
    return null;
  }

  private ctx() {
    return { get: (ref: string) => this.vars.get(ref) };
  }

  private resetVariables(): void {
    const story = this.story;
    this.vars = new VariableStore();
    if (!story) return;
    for (const [ref, def] of Object.entries(story.variables)) this.vars.define(ref, def);
    this.vars.setSys('sys.content_filter', this.contentFilter);
    this.vars.setSys('sys.locale', this.locale);
    this.vars.setSys('sys.selection_count', 0);
  }

  /** Volta ao estado sem jogo (`LOADED`): limpa posição, palco, atividade e histórico. */
  private endGameSession(): void {
    this.chapter = null;
    this.scene = null;
    this.cursor = null;
    this.waiting = null;
    this.activity = null;
    this.usedHotspots.clear();
    this.selectionIndex.clear();
    this.history = { selection_count: 0, scenes: {}, chapters: {} };
    this.stage = { background: null, set: null, set_states: {}, characters: [], audio: {} };
    this.backlog = [];
    this.rng = null;
    this.autosaveSlot = 0;
    this.phase = this.story ? 'TITLE' : 'BOOT';
  }

  private enterChapter(chapter: DoubleChapter, runEntry: boolean): void {
    this.chapter = chapter;
    this.vars.dropScope('chapter.');
    for (const [key, def] of Object.entries(chapter.variables ?? {})) this.vars.define(`chapter.${key}`, def);
    const h = (this.history.chapters[chapter.id] ??= { entries: 0, completed: false });
    h.entries += 1;
    this.phase = 'CHAPTER_ENTER';
    this.emit('chapter.started', { chapter: chapter.id });
    if (!runEntry) return;
    const entry = chapter.entry_scene ? this.story?.scenes.find((s) => s.id === chapter.entry_scene) : undefined;
    if (entry) this.startScene(entry, 'entry');
    else this.selectionPoint();
  }

  private startScene(scene: SceneEntity, reason: string): void {
    this.scene = scene;
    this.usedHotspots.clear();
    this.vars.dropScope('scene.');
    for (const v of scene.variables ?? []) {
      this.vars.define(`scene.${v.key}`, { type: v.type as never, default: v.default as Literal, constraints: v.constraints as never });
    }
    const h = (this.history.scenes[scene.id] ??= { plays: 0, starts: 0 });
    h.starts += 1;
    h.last_selection = this.history.selection_count;
    this.cursor = scene.start ?? scene.nodes[0]?.id ?? null;
    this.phase = 'SCENE_RUNNING';
    this.emit('scene.started', {
      scene: scene.id,
      chapter: this.chapter?.id ?? null,
      selection_count: this.history.selection_count,
      reason,
    });
  }

  /** Roda nós a partir do cursor até a condição de parada (§3, `preview.step.until`; `wait` é o RUNNING). */
  private run(until: Until): void {
    const startCount = this.history.selection_count;
    const startScene = this.scene?.id;
    for (let guard = 0; guard < 10_000; guard++) {
      if (this.waiting || this.phase === 'GAME_END' || !this.scene || !this.cursor) return;
      const sceneBefore = this.scene;
      this.execute();
      if (until === 'node') return;
      if (until === 'scene_end' && (this.scene !== sceneBefore || this.scene?.id !== startScene)) return;
      if (until === 'selection' && this.history.selection_count !== startCount) return;
    }
    this.emit('log', { level: 'error', message: 'o dublê parou um laço de 10000 nós sem bloqueio' });
  }

  private currentNode(): SceneNode | undefined {
    return this.scene?.nodes.find((n) => n.id === this.cursor);
  }

  private nodeSkipped(node: SceneNode): boolean {
    return (node.censor === 'skip' && this.contentFilter) || (node.censor === 'only' && !this.contentFilter);
  }

  /** Executa o nó do cursor (RT §5): `node.entered` → `state.changed` → `event.emitted` (§4.2). */
  private execute(): void {
    const node = this.currentNode();
    if (!node || !this.scene) {
      this.emit('error', { code: 'NODE_NOT_FOUND', message: `nó ${String(this.cursor)} não existe`, ...(this.scene ? { scene: this.scene.id } : {}) });
      this.endScene({ then: 'schedule' });
      return;
    }
    if (this.nodeSkipped(node)) {
      this.goto(node);
      return;
    }
    this.emit('node.entered', { scene: this.scene.id, node: node.id, type: node.type });
    switch (node.type) {
      case 'background':
        if (typeof node.set === 'string') {
          this.stage.background = null;
          this.stage.set = node.set;
          this.stage.set_states = {};
        } else {
          this.stage.background = str(node.asset) ?? null;
          this.stage.set = null;
          this.stage.set_states = {};
        }
        return this.goto(node);
      case 'show': {
        const id = String(node.character);
        const others = this.stage.characters.filter((c) => c.id !== id);
        const prev = this.stage.characters.find((c) => c.id === id);
        const entry: StageCharacter = { id };
        const expression = str(node.expression) ?? prev?.expression;
        const position = (node.position as string | number | undefined) ?? prev?.position;
        if (expression) entry.expression = expression;
        if (position !== undefined) entry.position = position;
        this.stage.characters = [...others, entry];
        return this.goto(node);
      }
      case 'hide':
        this.stage.characters = node.character === '*' ? [] : this.stage.characters.filter((c) => c.id !== node.character);
        return this.goto(node);
      case 'audio': {
        const channel = String(node.channel);
        if (node.action === 'stop' || typeof node.asset !== 'string') delete this.stage.audio[channel];
        else {
          const entry: { asset: string; loop?: boolean; volume?: number } = { asset: node.asset };
          if (typeof node.loop === 'boolean') entry.loop = node.loop;
          if (typeof node.volume === 'number') entry.volume = node.volume;
          this.stage.audio[channel] = entry;
        }
        return this.goto(node);
      }
      case 'line': {
        const raw = this.contentFilter && typeof node.censored_text === 'string' ? node.censored_text : String(node.text ?? '');
        const speakerId = str(node.speaker);
        const speaker = speakerId ? (this.story?.characters.find((c) => c.id === speakerId)?.name ?? null) : null;
        this.backlog.push({ speaker, text: interpolate(raw, (r) => this.vars.get(r)) });
        if (this.backlog.length > 50) this.backlog.shift();
        if (speakerId && typeof node.expression === 'string') {
          this.stage.characters = this.stage.characters.map((c) => (c.id === speakerId ? { ...c, expression: node.expression as string } : c));
        }
        this.waiting = { kind: 'line', node };
        return;
      }
      case 'choice': {
        const options = Array.isArray(node.options) ? (node.options as JsonObject[]) : [];
        if (!options.some((o) => evalCondition(o.visible_if, this.ctx()))) return this.goto(node);
        this.waiting = { kind: 'choice', node };
        return;
      }
      case 'interact': {
        const hotspots = Array.isArray(node.hotspots) ? (node.hotspots as JsonObject[]) : [];
        if (!hotspots.some((h) => this.hotspotVisible(h)) && !isObject(node.exit)) return this.goto(node);
        this.waiting = { kind: 'interact', node };
        return;
      }
      case 'effects': {
        const ok = this.applyWrites(effectWrites(node.effects, this.vars, this.ctx()), 'scene', node);
        return this.goto(node, ok ? undefined : str(node.on_fail));
      }
      case 'branch': {
        const cases = Array.isArray(node.cases) ? (node.cases as JsonObject[]) : [];
        const hit = cases.find((c) => evalCondition(c.conditions, this.ctx()));
        return this.goto(node, hit ? str(hit.goto) : str(node.else));
      }
      case 'jump':
        return this.goto(node, str(node.goto));
      case 'emit': {
        const payload: JsonObject = {};
        if (isObject(node.payload)) {
          for (const [k, expr] of Object.entries(node.payload)) payload[k] = evalValue(expr, this.ctx()) ?? null;
        }
        this.emit('event.emitted', { name: String(node.event), payload, source: 'scene' });
        return this.goto(node);
      }
      case 'plugin':
        return this.startStoryActivity(node);
      case 'end':
        this.endScene({ then: node.then ?? 'schedule', ending: str(node.ending) });
        return;
      default:
        // wait e tipos que o dublê não desenha: seguem o fluxo.
        return this.goto(node);
    }
  }

  /** Aplica escritas como uma transação. Falha de restrição devolve `false` (vai para `on_fail`); outras viram `error`. */
  private applyWrites(writes: { variable: string; value: Literal }[], source: string, node: SceneNode): boolean {
    if (writes.length === 0) return true;
    try {
      const changes = this.vars.commit(writes);
      if (changes.length > 0) this.emit('state.changed', { changes, source });
      return true;
    } catch (err) {
      if (!(err instanceof WriteError)) throw err;
      if (err.vnCode !== 'CONSTRAINT_VIOLATION') {
        this.emit('error', { code: err.vnCode, message: err.message, scene: this.scene?.id, node: node.id, variable: err.variable });
      }
      return false;
    }
  }

  /** Vai para `target`, ou para `next`, ou para o nó seguinte do array; sem nenhum, a cena termina. */
  private goto(node: SceneNode, target?: string): void {
    const scene = this.scene;
    if (!scene) return;
    let next = target ?? node.next;
    if (!next) {
      const index = scene.nodes.findIndex((n) => n.id === node.id);
      next = scene.nodes[index + 1]?.id;
    }
    if (!next) {
      this.endScene({ then: 'schedule' });
      return;
    }
    this.cursor = next;
  }

  private leaveLine(): void {
    const w = this.waiting;
    if (w?.kind !== 'line') return;
    this.waiting = null;
    this.goto(w.node);
  }

  private startStoryActivity(node: SceneNode): void {
    const id = String(node.activity);
    const found = this.findActivity(id);
    if (!found) {
      this.emit('error', { code: 'PLUGIN_MISSING', message: `atividade ${id} não está disponível`, scene: this.scene?.id, node: node.id });
      this.goto(node, str(node.on_error));
      return;
    }
    this.activity = { id, plugin: found.plugin, def: found.def, mode: 'story', scene: this.scene?.id, node };
    this.phase = 'ACTIVITY';
    this.waiting = { kind: 'activity', node };
    this.emit('activity.started', { activity: id, mode: 'story', scene: this.scene?.id, node: node.id });
  }

  private finishActivity(outcome: string | null, payload: JsonObject, skipped: boolean): void {
    const a = this.activity;
    if (!a) return;
    this.activity = null;
    if (a.mode === 'free_play') {
      this.phase = 'TITLE';
      this.emit('activity.ended', { activity: a.id, mode: 'free_play', outcome, skipped: false, failed: false });
      return;
    }
    const node = a.node as SceneNode;
    this.phase = 'SCENE_RUNNING';
    this.waiting = null;
    this.emit('activity.ended', { activity: a.id, mode: 'story', scene: a.scene, node: node.id, outcome, skipped, failed: false });
    const onResult = isObject(node.on_result) ? node.on_result : {};
    // Atividade pulada não aplica os efeitos de on_result (vetor flow plugin_pulado_sem_efeitos).
    if (!skipped) this.applyWrites(effectWrites(onResult.effects, this.vars, { ...this.ctx(), result: payload }), 'scene', node);
    const outcomes = isObject(onResult.outcomes) ? onResult.outcomes : {};
    this.goto(node, outcome ? str(outcomes[outcome]) : undefined);
  }

  /** Fim de cena (RT §5.4) e o que vem depois (`then`). `removed`: a cena sumiu numa recarga. */
  private endScene(end: { then: unknown; ending?: string }, removed = false): void {
    const scene = this.scene;
    if (!scene) return;
    this.phase = 'SCENE_END';
    if (!removed) {
      const h = (this.history.scenes[scene.id] ??= { plays: 0, starts: 0 });
      h.plays += 1;
      this.vars.setSys(`sys.scenes.${scene.id}.plays`, h.plays);
      this.emit('scene.ended', { scene: scene.id, then: end.then });
    }
    this.vars.dropScope('scene.');
    this.scene = null;
    this.cursor = null;
    this.waiting = null;
    const then = end.then;
    if (then === 'end_game') this.endGame(end.ending ?? null);
    else if (then === 'end_chapter') this.exitChapter();
    else if (isObject(then) && typeof then.scene === 'string') this.selectionPoint(then.scene);
    else this.selectionPoint();
  }

  private peekSelection(chapter: DoubleChapter): RecordedSelection {
    const index = this.selectionIndex.get(chapter.id) ?? 0;
    return chapter.selections?.[index] ?? { action: 'exit_chapter', chosen: null, reason: 'completion', candidates: [] };
  }

  /** Ponto de seleção (RT §4): usa a próxima avaliação gravada do capítulo, ou um pedido de cena (`then.scene`). */
  private selectionPoint(requested?: string): void {
    const chapter = this.chapter;
    if (!chapter) return this.endGame(null);
    this.phase = 'SELECTION_POINT';
    this.history.selection_count += 1;
    this.vars.setSys('sys.selection_count', this.history.selection_count);
    let recorded: RecordedSelection;
    if (requested) recorded = { action: 'start_scene', chosen: requested, reason: 'request', candidates: [] };
    else {
      recorded = this.peekSelection(chapter);
      this.selectionIndex.set(chapter.id, (this.selectionIndex.get(chapter.id) ?? 0) + 1);
    }
    this.autosave();
    this.emit('scheduler.evaluated', { ...recorded, selection_count: this.history.selection_count, chapter: chapter.id });
    if (recorded.action === 'start_scene' && recorded.chosen) {
      const scene = this.story?.scenes.find((s) => s.id === recorded.chosen);
      if (scene) {
        this.startScene(scene, recorded.reason);
        return;
      }
      this.emit('error', { code: 'SCENE_NOT_FOUND', message: `cena ${recorded.chosen} da avaliação gravada não existe` });
      return this.exitChapter();
    }
    if (recorded.action === 'end_game') return this.endGame(null);
    this.exitChapter();
  }

  private exitChapter(): void {
    const chapter = this.chapter;
    if (!chapter) return this.endGame(null);
    this.phase = 'CHAPTER_EXIT';
    const h = (this.history.chapters[chapter.id] ??= { entries: 1, completed: false });
    h.completed = true;
    this.emit('chapter.ended', { chapter: chapter.id });
    this.vars.dropScope('chapter.');
    this.chapter = null;
    const next = chapter.next ? this.findChapter(chapter.next) : undefined;
    if (next) this.enterChapter(next, true);
    else this.endGame(null);
  }

  private endGame(ending: string | null): void {
    this.phase = 'GAME_END';
    this.scene = null;
    this.cursor = null;
    this.waiting = null;
    if (ending && !this.profileEndings.includes(ending)) {
      this.profileEndings.push(ending);
      this.profileEndings.sort();
    }
    this.writeStorage(
      'profile.json',
      JSON.stringify({ save_format: '1.0.0', project_id: this.story?.project_id, variables: {}, endings: this.profileEndings }),
    );
    this.emit('event.emitted', { name: 'sys.game_ended', payload: { ending }, source: 'system' });
    this.emit('game.ended', { ending });
  }

  private autosave(): void {
    if (this.story?.autosave !== 'selection_point') return;
    this.autosaveSlot = (this.autosaveSlot % 3) + 1;
    this.writeStorage(
      `saves/auto_${this.autosaveSlot}.json`,
      JSON.stringify({ chapter: this.chapter?.id, selection_count: this.history.selection_count, variables: this.vars.snapshot() }),
    );
  }

  /** `VNStorage` do Preview (§1.4): guarda na memória e, no painel com `user_data: "project"`, avisa o Studio. */
  private writeStorage(path: string, text: string): void {
    const data = toBase64(text);
    this.storage.set(path, data);
    if (this.opts.transport === 'panel' && this.userData === 'project') this.emit('storage.write', { path, data });
  }

  private gameState(include?: string[]): GameState {
    const want = (field: string) => !include || include.includes(field);
    const inGame = this.previewState === 'RUNNING' || this.previewState === 'PAUSED';
    const state: GameState = {
      phase: this.phase,
      // Em LOADED não há jogo: o schema só aceita RUNNING ou PAUSED, e o dublê responde PAUSED.
      preview: this.previewState === 'RUNNING' ? 'RUNNING' : 'PAUSED',
      chapter: inGame ? (this.chapter?.id ?? null) : null,
      scene: inGame ? (this.scene?.id ?? null) : null,
      node: inGame ? this.cursor : null,
    };
    if (want('variables')) state.variables = this.vars.snapshot();
    if (want('history')) state.history = clone(this.history);
    if (want('stage')) {
      const stage: NonNullable<GameState['stage']> = {
        background: this.stage.background,
        characters: clone(this.stage.characters) as NonNullable<GameState['stage']>['characters'],
        audio: clone(this.stage.audio),
      };
      if (this.stage.set) {
        stage.set = this.stage.set;
        stage.set_states = { ...this.stage.set_states };
      }
      state.stage = stage;
    }
    if (want('backlog')) state.backlog = this.backlog.slice(-50).map((b) => ({ ...b }));
    if (want('plugins')) {
      const plugins: NonNullable<GameState['plugins']> = {};
      for (const [id, plugin] of Object.entries(this.story?.plugins ?? {})) {
        plugins[id] = { enabled: plugin.enabled !== false, faulted: false, activity: this.activity?.plugin === id ? this.activity.id : null };
      }
      state.plugins = plugins;
    }
    if (this.rng) state.rng = { ...this.rng };
    return state;
  }
}
