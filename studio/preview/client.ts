/**
 * Cliente JSON-RPC 2.0 do Preview (PP §1.1, §3, §4, §6): manda requisições pela ponte do painel e junta
 * respostas e notificações. Fala igual com o dublê (M0-09) e com o runtime Web (M6-14): só o transporte muda.
 *
 * O que chega pela ponte vem de uma página onde também roda código de plugin (PP §1.1, item 3); por isso
 * toda mensagem é lida com cuidado: texto que não é JSON, ou que não tem a forma de resposta ou de
 * notificação, é ignorado e vira um aviso, nunca uma exceção.
 */
import type {
  PreviewExplainSelectionParams,
  PreviewExplainSelectionResult,
  PreviewGetStateParams,
  PreviewGetStateResult,
  PreviewInputParams,
  PreviewInputResult,
  PreviewLoadParams,
  PreviewLoadResult,
  PreviewPauseResult,
  PreviewReloadParams,
  PreviewReloadPluginsParams,
  PreviewReloadPluginsResult,
  PreviewReloadResult,
  PreviewResumeResult,
  PreviewSetLocaleParams,
  PreviewSetLocaleResult,
  PreviewSetSettingParams,
  PreviewSetSettingResult,
  PreviewSetVariablesParams,
  PreviewSetVariablesResult,
  PreviewShowScreenParams,
  PreviewShowScreenResult,
  PreviewStartParams,
  PreviewStartResult,
  PreviewStepParams,
  PreviewStepResult,
  PreviewStopResult,
  SessionHelloParams,
  SessionHelloResult,
} from '@vnstudio/plugin-schema';

/** A ponte do painel (PP §1.1, item 2): uma mensagem JSON-RPC em texto por chamada, nos dois sentidos. */
export interface PreviewTransport {
  send(text: string): void;
  /** O cliente registra aqui o que fazer com cada mensagem do runtime, antes de iniciar o motor. */
  onmessage: ((text: string) => void) | null;
  /** O Studio fecha o painel: a página é descartada (PP §1.1, item 4). */
  close(): void;
}

/** Os métodos do §3, com parâmetros e resultado dos tipos gerados do schema. */
export interface PreviewMethods {
  'session.hello': [SessionHelloParams, SessionHelloResult];
  'preview.load': [PreviewLoadParams, PreviewLoadResult];
  'preview.start': [PreviewStartParams, PreviewStartResult];
  'preview.stop': [Record<string, never>, PreviewStopResult];
  'preview.pause': [Record<string, never>, PreviewPauseResult];
  'preview.resume': [Record<string, never>, PreviewResumeResult];
  'preview.step': [PreviewStepParams, PreviewStepResult];
  'preview.input': [PreviewInputParams, PreviewInputResult];
  'preview.set_variables': [PreviewSetVariablesParams, PreviewSetVariablesResult];
  'preview.get_state': [PreviewGetStateParams, PreviewGetStateResult];
  'preview.explain_selection': [PreviewExplainSelectionParams, PreviewExplainSelectionResult];
  'preview.reload': [PreviewReloadParams, PreviewReloadResult];
  'preview.reload_plugins': [PreviewReloadPluginsParams, PreviewReloadPluginsResult];
  'preview.show_screen': [PreviewShowScreenParams, PreviewShowScreenResult];
  'preview.set_setting': [PreviewSetSettingParams, PreviewSetSettingResult];
  'preview.set_locale': [PreviewSetLocaleParams, PreviewSetLocaleResult];
}

export type PreviewMethod = keyof PreviewMethods;

/** Notificação do runtime (PP §4): `seq` cresce na sessão a partir de 1 e `phase` é o estado do motor. */
export interface PreviewNotification {
  method: string;
  params: { seq?: number; phase?: string; [field: string]: unknown };
}

/** Resposta de erro do runtime (PP §6). `dataCode` é o `error.data.code`, que escolhe a mensagem ao autor. */
export class PreviewRpcError extends Error {
  readonly code: number;
  readonly dataCode: string | undefined;
  readonly data: Record<string, unknown> | undefined;
  readonly method: string;

  constructor(method: string, error: { code: number; message: string; data?: Record<string, unknown> }) {
    super(`${method}: ${error.message}`);
    this.name = 'PreviewRpcError';
    this.method = method;
    this.code = error.code;
    this.data = error.data;
    this.dataCode = typeof error.data?.code === 'string' ? error.data.code : undefined;
  }

  /** `data.detail` de `BUNDLE_INVALID`, por exemplo `full_reload_required`. */
  get detail(): string | undefined {
    return typeof this.data?.detail === 'string' ? this.data.detail : undefined;
  }
}

export interface PreviewClientOptions {
  /** Prazo de cada requisição. Padrão 60 s (abrir o motor e o bundle leva de 1 a 5 s, PP §1.1). */
  timeoutMs?: number;
  /** Mensagem do runtime que o cliente descartou (não é JSON, forma errada, resposta sem requisição). */
  onIgnored?: (reason: string) => void;
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);

interface Pending {
  method: string;
  resolve: (value: unknown) => void;
  reject: (reason: unknown) => void;
  timer: ReturnType<typeof setTimeout>;
}

export class PreviewClient {
  private nextId = 1;
  private readonly pending = new Map<number, Pending>();
  private readonly handlers = new Set<(n: PreviewNotification) => void>();
  private lastSeq = 0;
  private closed = false;

  /** Notificações cujo `seq` não seguiu o anterior (perda ou reordenação, PP §4). */
  readonly seqGaps: { expected: number; got: number }[] = [];

  constructor(
    private readonly transport: PreviewTransport,
    private readonly options: PreviewClientOptions = {},
  ) {
    transport.onmessage = (text) => this.receive(text);
  }

  /** Recebe cada notificação do runtime, na ordem. Devolve a função que cancela. */
  onNotification(handler: (n: PreviewNotification) => void): () => void {
    this.handlers.add(handler);
    return () => this.handlers.delete(handler);
  }

  request<M extends PreviewMethod>(method: M, params?: PreviewMethods[M][0]): Promise<PreviewMethods[M][1]> {
    if (this.closed) return Promise.reject(new Error(`${method}: o Preview está fechado`));
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${method}: sem resposta em ${(this.options.timeoutMs ?? 60_000) / 1000} s`));
      }, this.options.timeoutMs ?? 60_000);
      this.pending.set(id, { method, resolve: resolve as (v: unknown) => void, reject, timer });
      const message = { jsonrpc: '2.0', id, method, ...(params ? { params } : {}) };
      try {
        this.transport.send(JSON.stringify(message));
      } catch (err) {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(err);
      }
    });
  }

  /** Fecha o painel e recusa o que ainda esperava resposta. */
  close(reason = 'o Preview foi fechado'): void {
    if (this.closed) return;
    this.closed = true;
    this.transport.onmessage = null;
    for (const [id, p] of this.pending) {
      clearTimeout(p.timer);
      p.reject(new Error(`${p.method}: ${reason}`));
      this.pending.delete(id);
    }
    this.transport.close();
  }

  private ignored(reason: string): void {
    this.options.onIgnored?.(reason);
  }

  private receive(text: string): void {
    if (this.closed) return;
    let message: unknown;
    try {
      message = JSON.parse(text);
    } catch {
      this.ignored('mensagem do runtime que não é JSON');
      return;
    }
    if (!isObject(message) || message.jsonrpc !== '2.0') {
      this.ignored('mensagem do runtime que não é JSON-RPC 2.0');
      return;
    }
    if (typeof message.method === 'string') {
      if (!('id' in message) && isObject(message.params)) this.notify({ method: message.method, params: message.params });
      else this.ignored(`o runtime nunca faz requisições no v1 (${message.method})`);
      return;
    }
    const id = message.id;
    const pending = typeof id === 'number' ? this.pending.get(id) : undefined;
    if (!pending) {
      this.ignored('resposta sem requisição em curso');
      return;
    }
    this.pending.delete(id as number);
    clearTimeout(pending.timer);
    if (isObject(message.error) && typeof message.error.code === 'number' && typeof message.error.message === 'string') {
      pending.reject(
        new PreviewRpcError(pending.method, {
          code: message.error.code,
          message: message.error.message,
          ...(isObject(message.error.data) ? { data: message.error.data } : {}),
        }),
      );
    } else if ('result' in message) {
      pending.resolve(message.result);
    } else {
      pending.reject(new Error(`${pending.method}: resposta sem result nem error`));
    }
  }

  private notify(n: PreviewNotification): void {
    const seq = n.params.seq;
    if (typeof seq === 'number') {
      if (seq !== this.lastSeq + 1) this.seqGaps.push({ expected: this.lastSeq + 1, got: seq });
      this.lastSeq = seq;
    }
    for (const handler of this.handlers) handler(n);
  }
}
