/**
 * Transportes do painel do Preview (PP §1.1). `IframeTransport` fala com a página do runtime Web, servida
 * por `vnpreview://` num iframe de outra origem: a ponte `vnPreview.send` / `vnPreview.onmessage` mora na
 * página do iframe e o Studio chega a ela por `postMessage` (mesma convenção do spike M4-02,
 * `spikes/preview-pck/host/shell.html`). `DoubleTransport` liga o painel ao dublê do M0-09.
 */
import type { PreviewTransport } from './client';
import { installFakeBridge, type FakePreviewRuntimeOptions } from './double';

/** Mensagens trocadas com a página do runtime. */
export const TO_RUNTIME = 'to-runtime';
export const FROM_RUNTIME = 'from-runtime';

export class IframeTransport implements PreviewTransport {
  onmessage: ((text: string) => void) | null = null;
  private readonly queue: string[] = [];
  private loaded = false;
  private readonly listener: (ev: MessageEvent) => void;
  private readonly onLoad: () => void;

  constructor(
    private readonly frame: HTMLIFrameElement,
    private readonly host: Pick<Window, 'addEventListener' | 'removeEventListener'> = window,
  ) {
    // Só vale mensagem que veio da janela do iframe; o que a página manda por ali é código não confiável.
    this.listener = (ev) => {
      if (ev.source !== frame.contentWindow) return;
      const data: unknown = ev.data;
      if (typeof data !== 'object' || data === null) return;
      const { vn, text } = data as { vn?: unknown; text?: unknown };
      if (vn === FROM_RUNTIME && typeof text === 'string') this.onmessage?.(text);
    };
    this.onLoad = () => {
      this.loaded = true;
      for (const text of this.queue.splice(0)) this.post(text);
    };
    host.addEventListener('message', this.listener as EventListener);
    frame.addEventListener('load', this.onLoad);
  }

  send(text: string): void {
    if (this.loaded) this.post(text);
    else this.queue.push(text);
  }

  private post(text: string): void {
    this.frame.contentWindow?.postMessage({ vn: TO_RUNTIME, text }, '*');
  }

  close(): void {
    this.host.removeEventListener('message', this.listener as EventListener);
    this.frame.removeEventListener('load', this.onLoad);
    this.onmessage = null;
    this.frame.src = 'about:blank';
  }
}

/** O dublê do runtime (M0-09) como transporte: o painel roda sem o runtime Web. */
export function doubleTransport(options: Partial<FakePreviewRuntimeOptions> = {}): PreviewTransport & { runtime: ReturnType<typeof installFakeBridge>['runtime'] } {
  const target: { vnPreview?: { send(text: string): void; onmessage: ((text: string) => void) | null } } = {};
  const { bridge, runtime } = installFakeBridge(target, options);
  return {
    runtime,
    send: (text) => bridge.send(text),
    get onmessage() {
      return bridge.onmessage;
    },
    set onmessage(handler) {
      bridge.onmessage = handler;
    },
    close: () => runtime.close('stop'),
  };
}
