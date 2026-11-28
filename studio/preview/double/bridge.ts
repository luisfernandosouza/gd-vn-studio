/**
 * A ponte do painel (spec 07 §1.1, item 2) servida pelo dublê: `vnPreview.send(text)` leva uma requisição ao
 * runtime, e o runtime entrega respostas e notificações chamando `vnPreview.onmessage(text)`, que o Studio
 * registra antes de iniciar o motor. Com `installFakeBridge(window)`, o código do Studio que fala com o painel
 * roda igual contra o dublê e contra o runtime Web.
 */
import { FakePreviewRuntime, type FakePreviewRuntimeOptions } from './FakePreviewRuntime';
import { demoStory } from './story';

export interface VnPreviewBridge {
  send(text: string): void;
  onmessage: ((text: string) => void) | null;
}

export function installFakeBridge(
  target: { vnPreview?: VnPreviewBridge },
  options: Partial<FakePreviewRuntimeOptions> = {},
): { bridge: VnPreviewBridge; runtime: FakePreviewRuntime } {
  const runtime = new FakePreviewRuntime({ story: demoStory(), ...options, transport: 'panel' });
  const bridge: VnPreviewBridge = {
    send: (text) => runtime.send(text),
    onmessage: target.vnPreview?.onmessage ?? null,
  };
  runtime.onmessage = (text) => bridge.onmessage?.(text);
  target.vnPreview = bridge;
  return { bridge, runtime };
}
