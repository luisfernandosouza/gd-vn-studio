import { createStore, type StoreApi } from 'zustand/vanilla';
import type { ProjectFs } from '../project-manager/fs';
import { VNError } from './errors';
import { applyPatch, withTests, type EditSource, type Operation } from './patch';
import { cloneDiskState, commitSave, planSave, type DiskState, type LogicalDocument } from './logical-document';
import { getValue, parsePointer } from './pointer';

/** Um passo de undo: o patch aplicado, o inverso e o que o autor vê no menu ("Desfazer <label>"). */
export interface HistoryEntry {
  label: string;
  source: EditSource;
  forward: Operation[];
  inverse: Operation[];
  at: number;
  coalesceKey?: string;
}

export type SaveStatus = 'saved' | 'dirty' | 'saving' | 'error';

export interface DocumentState {
  doc: LogicalDocument;
  undoStack: readonly HistoryEntry[];
  redoStack: readonly HistoryEntry[];
  saveStatus: SaveStatus;
  saveError: string | null;
  /** Sobe a cada mudança do documento (edição, undo, redo ou recarga). */
  revision: number;
}

export interface EditOptions {
  label?: string;
  source?: EditSource;
  /**
   * Edições seguidas com a mesma chave em até `coalesceWindowMs` viram um passo só (digitar numa fala
   * não enche o histórico de uma letra por passo).
   */
  coalesceKey?: string;
  /** Acrescenta os `test` que faltam (comandos do Studio). Plugins mandam os próprios `test`. */
  autoTest?: boolean;
}

/** Comando do Studio: recebe o documento e devolve operações; o inverso vem do patch aplicado. */
export interface Command<A = void> {
  id: string;
  label: string | ((args: A) => string);
  build(doc: LogicalDocument, args: A): Operation[];
}

/** Valida o documento resultante; devolve a mensagem de recusa ou `null` (ligado ao validador no M6-03). */
export type DocumentGuard = (next: LogicalDocument, prev: LogicalDocument, source: EditSource) => string | null;

export interface DocumentStoreOptions {
  fs: ProjectFs;
  root: string;
  doc: LogicalDocument;
  disk: DiskState;
  /** Quanto esperar entre a primeira edição não gravada e a gravação. Req §8: até 2 s; o padrão deixa folga. */
  saveDelayMs?: number;
  /** Tempo até tentar de novo depois de uma gravação que falhou. */
  retryDelayMs?: number;
  coalesceWindowMs?: number;
  maxHistory?: number;
  guard?: DocumentGuard;
  now?: () => number;
}

export interface DocumentStore extends StoreApi<DocumentState> {
  applyEdit(ops: readonly Operation[], options?: EditOptions): HistoryEntry;
  run<A>(command: Command<A>, ...args: A extends void ? [] : [A]): HistoryEntry;
  undo(): HistoryEntry | null;
  redo(): HistoryEntry | null;
  canUndo(): boolean;
  canRedo(): boolean;
  /** Trecho do documento lógico (SDK §10.3 `getDocument`); para plugins, sem `/project/build/signing`. */
  getDocument(pointer?: string, source?: EditSource): unknown;
  /** Grava o que estiver pendente agora e espera terminar. */
  flush(): Promise<void>;
  /** Troca o documento (recarga do disco ou restauração de versão); zera o histórico. */
  replaceDocument(doc: LogicalDocument, disk: DiskState): void;
  /** Grava o que falta e para os timers. */
  dispose(): Promise<void>;
}

const SIGNING = ['project', 'build', 'signing'];

function redact(pointer: string, value: unknown): unknown {
  const seg = parsePointer(pointer);
  if (seg.length > SIGNING.length && SIGNING.every((s, i) => seg[i] === s)) return value;
  if (seg.length >= SIGNING.length && SIGNING.every((s, i) => seg[i] === s)) throw new VNError('FORBIDDEN_PATH', `${pointer}: este trecho não é exposto a plugins.`);
  if (typeof value !== 'object' || value === null) return value;
  const copy = structuredClone(value) as Record<string, unknown>;
  let node: unknown = copy;
  const rest = SIGNING.slice(seg.length);
  if (!SIGNING.slice(0, seg.length).every((s, i) => seg[i] === s)) return copy;
  for (let i = 0; i < rest.length - 1; i++) {
    node = typeof node === 'object' && node !== null ? (node as Record<string, unknown>)[rest[i] as string] : undefined;
  }
  if (typeof node === 'object' && node !== null) delete (node as Record<string, unknown>)[rest[rest.length - 1] as string];
  return copy;
}

export function createDocumentStore(options: DocumentStoreOptions): DocumentStore {
  const { fs, root } = options;
  const saveDelay = options.saveDelayMs ?? 1000;
  const retryDelay = options.retryDelayMs ?? 2000;
  const coalesceWindow = options.coalesceWindowMs ?? 1000;
  const maxHistory = options.maxHistory ?? 1000;
  const now = options.now ?? Date.now;
  let disk = options.disk;
  let savedRevision = 0;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let inFlight: Promise<void> | null = null;
  let disposed = false;

  const store = createStore<DocumentState>()(() => ({
    doc: options.doc,
    undoStack: [],
    redoStack: [],
    saveStatus: 'saved',
    saveError: null,
    revision: 0,
  }));

  const schedule = (delay: number) => {
    if (timer || disposed) return;
    timer = setTimeout(() => {
      timer = null;
      void save();
    }, delay);
  };

  /** Grava em laço até alcançar a revisão atual; uma gravação por vez. */
  const save = (): Promise<void> => {
    if (inFlight) return inFlight;
    inFlight = (async () => {
      try {
        while (savedRevision !== store.getState().revision) {
          const { doc, revision } = store.getState();
          store.setState({ saveStatus: 'saving' });
          const trial = cloneDiskState(disk);
          try {
            await commitSave(fs, root, planSave(doc, trial), trial);
          } catch (e) {
            store.setState({ saveStatus: 'error', saveError: e instanceof Error ? e.message : String(e) });
            schedule(retryDelay);
            return;
          }
          disk = trial;
          savedRevision = revision;
          store.setState({ saveStatus: savedRevision === store.getState().revision ? 'saved' : 'dirty', saveError: null });
        }
      } finally {
        inFlight = null;
      }
    })();
    return inFlight;
  };

  const commit = (patch: Partial<DocumentState>) => {
    store.setState((s) => ({ ...patch, revision: s.revision + 1, saveStatus: 'dirty' }));
    schedule(saveDelay);
  };

  const applyEdit: DocumentStore['applyEdit'] = (ops, edit = {}) => {
    const source = edit.source ?? 'studio';
    const prev = store.getState();
    const input = edit.autoTest ? withTests(prev.doc, ops) : ops;
    const result = applyPatch(prev.doc, input, { source });
    const refusal = options.guard?.(result.doc, prev.doc, source);
    if (refusal) throw new VNError('VALIDATION_FAILED', refusal);
    let entry: HistoryEntry = { label: edit.label ?? 'Edição', source, forward: result.forward, inverse: result.inverse, at: now(), coalesceKey: edit.coalesceKey };
    if (result.forward.every((op) => op.op === 'test')) return entry;
    const top = prev.undoStack[prev.undoStack.length - 1];
    let undoStack = [...prev.undoStack];
    if (top && edit.coalesceKey && top.coalesceKey === edit.coalesceKey && entry.at - top.at <= coalesceWindow) {
      entry = { ...top, forward: [...top.forward, ...entry.forward], inverse: [...entry.inverse, ...top.inverse], at: entry.at };
      undoStack.pop();
    }
    undoStack.push(entry);
    if (undoStack.length > maxHistory) undoStack = undoStack.slice(undoStack.length - maxHistory);
    commit({ doc: result.doc, undoStack, redoStack: [] });
    return entry;
  };

  const undo = (): HistoryEntry | null => {
    const { doc, undoStack, redoStack } = store.getState();
    const entry = undoStack[undoStack.length - 1];
    if (!entry) return null;
    const result = applyPatch(doc, entry.inverse);
    commit({ doc: result.doc, undoStack: undoStack.slice(0, -1), redoStack: [...redoStack, entry] });
    return entry;
  };

  const redo = (): HistoryEntry | null => {
    const { doc, undoStack, redoStack } = store.getState();
    const entry = redoStack[redoStack.length - 1];
    if (!entry) return null;
    const result = applyPatch(doc, entry.forward);
    commit({ doc: result.doc, undoStack: [...undoStack, entry], redoStack: redoStack.slice(0, -1) });
    return entry;
  };

  return Object.assign(store, {
    applyEdit,
    run<A>(command: Command<A>, ...args: A extends void ? [] : [A]): HistoryEntry {
      const arg = args[0] as A;
      const label = typeof command.label === 'function' ? command.label(arg) : command.label;
      return applyEdit(command.build(store.getState().doc, arg), { label, autoTest: true });
    },
    undo,
    redo,
    canUndo: () => store.getState().undoStack.length > 0,
    canRedo: () => store.getState().redoStack.length > 0,
    getDocument(pointer = '', source: EditSource = 'studio') {
      if (source === 'plugin') {
        const seg = parsePointer(pointer);
        if (seg.length >= SIGNING.length && SIGNING.every((x, i) => seg[i] === x)) throw new VNError('FORBIDDEN_PATH', `${pointer}: este trecho não é exposto a plugins.`);
      }
      const value = getValue(store.getState().doc, pointer);
      if (value === undefined) throw new VNError('NOT_FOUND', `${pointer || '/'}: caminho não existe.`);
      return source === 'plugin' ? redact(pointer, value) : structuredClone(value);
    },
    async flush() {
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
      await save();
      if (inFlight) await inFlight;
    },
    replaceDocument(doc: LogicalDocument, nextDisk: DiskState) {
      disk = nextDisk;
      store.setState((s) => ({ doc, undoStack: [], redoStack: [], revision: s.revision + 1, saveStatus: 'saved', saveError: null }));
      savedRevision = store.getState().revision;
    },
    async dispose() {
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
      await save();
      disposed = true;
    },
  } satisfies Omit<DocumentStore, keyof StoreApi<DocumentState>>);
}
