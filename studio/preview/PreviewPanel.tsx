import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from 'react';
import type { ProjectFs } from '../src/project-manager/fs';
import type { PreviewTransport } from './client';
import { closePreviewProject, openPreviewProject, runtimeAvailable } from './native';
import { readProjectInput } from './project-input';
import { PreviewSession } from './session';
import { usePreviewStore } from './store';
import { IframeTransport, doubleTransport } from './transport';
import { detectPlatform, previewUrls } from './urls';
import './preview-panel.css';

export interface PreviewPanelProps {
  fs: ProjectFs;
  root: string;
  /** Transporte do runtime. Padrão: o runtime Web no iframe se estiver embutido, senão o dublê (M0-09). */
  createTransport?: (frameHost: HTMLElement) => Promise<{ transport: PreviewTransport; kind: 'runtime' | 'double' }>;
  keepSaves?: boolean;
}

async function defaultTransport(host: HTMLElement, urls: ReturnType<typeof previewUrls>): Promise<{ transport: PreviewTransport; kind: 'runtime' | 'double' }> {
  if (!(await runtimeAvailable())) return { transport: doubleTransport(), kind: 'double' };
  const frame = document.createElement('iframe');
  frame.title = 'Preview do jogo';
  frame.className = 'preview-frame';
  const transport = new IframeTransport(frame);
  frame.src = urls.runtimePage;
  host.appendChild(frame);
  return { transport, kind: 'runtime' };
}

/** Painel do Preview (M6-10): barra com os controles e o modo stream, e a página do runtime ao lado do editor. */
export function PreviewPanel({ fs, root, createTransport, keepSaves = false }: PreviewPanelProps) {
  const session = usePreviewStore((s) => s.session);
  const setSession = usePreviewStore((s) => s.setSession);
  const frameHost = useRef<HTMLDivElement>(null);
  const [kind, setKind] = useState<'runtime' | 'double' | null>(null);
  const [opening, setOpening] = useState(false);

  const snap = useSyncExternalStore(
    session?.subscribe ?? noSubscribe,
    session?.getSnapshot ?? noSnapshot,
  );

  const open = useCallback(async () => {
    if (!frameHost.current || opening) return;
    setOpening(true);
    const urls = previewUrls(detectPlatform());
    try {
      await openPreviewProject(root);
      const { transport, kind } = await (createTransport ? createTransport(frameHost.current) : defaultTransport(frameHost.current, urls));
      setKind(kind);
      const next = new PreviewSession({ fs, root, transport, urls, keepSaves });
      setSession(next);
      await next.open(() => readProjectInput(fs, root));
    } catch {
      // o motivo fica no snapshot da sessão (status "error") e no log
    } finally {
      setOpening(false);
    }
  }, [createTransport, fs, keepSaves, opening, root, setSession]);

  const close = useCallback(() => {
    usePreviewStore.getState().session?.dispose();
    setSession(null);
    setKind(null);
    frameHost.current?.replaceChildren();
    void closePreviewProject();
  }, [setSession]);

  useEffect(() => () => {
    usePreviewStore.getState().session?.dispose();
    usePreviewStore.getState().setSession(null);
    void closePreviewProject();
  }, []);

  const reloadFromDisk = useCallback(async () => {
    if (session) await session.update(await readProjectInput(fs, root)).catch(() => undefined);
  }, [fs, root, session]);

  const live = snap.status === 'ready';
  const running = snap.runState === 'RUNNING' || snap.runState === 'PAUSED';
  const run = (f: () => Promise<unknown>) => () => void f().catch(() => undefined);

  return (
    <section className="preview-panel" aria-label="Preview">
      <div className="preview-bar" role="toolbar" aria-label="Barra do Preview">
        {!session ? (
          <button type="button" onClick={() => void open()} disabled={opening}>
            Abrir Preview
          </button>
        ) : (
          <>
            <button type="button" disabled={!live || running} onClick={run(() => session.start())}>
              Iniciar
            </button>
            <button type="button" disabled={!live || !running} onClick={run(() => session.stop())}>
              Parar
            </button>
            {snap.runState === 'PAUSED' ? (
              <button type="button" onClick={run(() => session.resume())}>
                Continuar
              </button>
            ) : (
              <button type="button" disabled={snap.runState !== 'RUNNING'} onClick={run(() => session.pause())}>
                Pausar
              </button>
            )}
            <button type="button" disabled={snap.runState !== 'PAUSED'} onClick={run(() => session.step())}>
              Passo
            </button>
            <button type="button" aria-pressed={snap.contentFilter} disabled={!live} onClick={run(() => session.setContentFilter(!snap.contentFilter))}>
              Modo stream
            </button>
            <button type="button" disabled={!live} onClick={() => void reloadFromDisk()}>
              Recarregar do disco
            </button>
            <button type="button" onClick={close}>
              Fechar Preview
            </button>
          </>
        )}
      </div>
      {session && (
        <p className="preview-status" role="status">
          {statusText(snap.status, snap.runState)}
          {kind === 'double' && ' · runtime de teste (dublê)'}
          {snap.reloads.lastMs !== null && ` · última recarga ${snap.reloads.lastKind === 'full' ? 'completa' : 'incremental'}: ${Math.round(snap.reloads.lastMs)} ms`}
          {snap.error && ` · ${snap.error}`}
        </p>
      )}
      <div ref={frameHost} className="preview-frame-host" />
      {session && snap.log.length > 0 && (
        <ul className="preview-log" aria-label="Log do Preview">
          {snap.log.slice(-8).map((entry, i) => (
            <li key={`${entry.at}-${i}`} data-level={entry.level}>
              {entry.message}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

const noSubscribe = (): (() => void) => () => undefined;
const emptySnapshot = { status: 'idle', runState: null, contentFilter: false, reloads: { lastMs: null, lastKind: null }, log: [], error: null } as never;
const noSnapshot = () => emptySnapshot;

function statusText(status: string, run: string | null): string {
  switch (status) {
    case 'connecting':
      return 'Abrindo o runtime…';
    case 'ready':
      return run === 'RUNNING' ? 'Jogo em andamento' : run === 'PAUSED' ? 'Jogo pausado' : 'Projeto carregado';
    case 'closed':
      return 'Preview fechado';
    case 'error':
      return 'Erro no Preview';
    default:
      return '';
  }
}
