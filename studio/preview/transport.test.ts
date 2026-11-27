import { describe, expect, it, vi } from 'vitest';
import { FROM_RUNTIME, IframeTransport, TO_RUNTIME } from './transport';

function setup() {
  const frame = document.createElement('iframe');
  document.body.appendChild(frame);
  const post = vi.spyOn(frame.contentWindow!, 'postMessage');
  const transport = new IframeTransport(frame, window);
  const received: string[] = [];
  transport.onmessage = (text) => received.push(text);
  const fromFrame = (data: unknown, source: MessageEventSource | null = frame.contentWindow) =>
    window.dispatchEvent(new MessageEvent('message', { data, source }));
  return { frame, post, transport, received, fromFrame };
}

describe('IframeTransport', () => {
  it('guarda o que o Studio manda até a página carregar, depois entrega em ordem', () => {
    const { frame, post, transport } = setup();
    transport.send('a');
    transport.send('b');
    expect(post).not.toHaveBeenCalled();
    frame.dispatchEvent(new Event('load'));
    expect(post.mock.calls.map((c) => c[0])).toEqual([
      { vn: TO_RUNTIME, text: 'a' },
      { vn: TO_RUNTIME, text: 'b' },
    ]);
    transport.send('c');
    expect(post).toHaveBeenLastCalledWith({ vn: TO_RUNTIME, text: 'c' }, '*');
    transport.close();
  });

  it('só aceita mensagem que veio do iframe, no formato da ponte', () => {
    const { received, fromFrame, transport } = setup();
    fromFrame({ vn: FROM_RUNTIME, text: '{"jsonrpc":"2.0"}' });
    fromFrame({ vn: FROM_RUNTIME, text: 42 });
    fromFrame({ vn: 'outra', text: 'x' });
    fromFrame('texto solto');
    fromFrame(null);
    fromFrame({ vn: FROM_RUNTIME, text: 'de outra janela' }, window);
    expect(received).toEqual(['{"jsonrpc":"2.0"}']);
    transport.close();
    fromFrame({ vn: FROM_RUNTIME, text: 'depois de fechar' });
    expect(received).toHaveLength(1);
  });
});
