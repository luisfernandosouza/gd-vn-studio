import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { useI18n } from '../src/i18n';
import { PreviewPanel } from './PreviewPanel';
import { usePreviewStore } from './store';
import { doubleTransport } from './transport';
import { PLUGIN_DIR, PROJECT_ROOT, demoMemoryFs } from './testing';
import { detectPlatform } from './urls';

beforeEach(() => useI18n.setState({ locale: 'en' }));

afterEach(() => {
  cleanup();
  usePreviewStore.setState({ session: null });
});

describe('PreviewPanel', () => {
  it('abre o Preview contra o dublê, mostra o estado e a barra com o modo stream', async () => {
    const fs = demoMemoryFs();
    // o projeto de teste guarda o plugin fora dele; o leitor acha o manifesto pela origem path: de plugins.json
    await fs.writeText(`${PROJECT_ROOT}/plugins.json`, await fs.readText(`${PROJECT_ROOT}/plugins.json`));
    render(
      <PreviewPanel
        fs={fs}
        root={PROJECT_ROOT}
        createTransport={async () => ({ transport: doubleTransport({ helloTimeoutMs: null }), kind: 'double' })}
      />,
    );
    expect(screen.queryByRole('toolbar')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Open Preview' }));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Project loaded'));
    expect(screen.getByRole('status')).toHaveTextContent('test runtime (double)');

    fireEvent.click(screen.getByRole('button', { name: 'Start' }));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Game running'));

    const stream = screen.getByRole('button', { name: 'Stream mode' });
    expect(stream).toHaveAttribute('aria-pressed', 'false');
    fireEvent.click(stream);
    await waitFor(() => expect(stream).toHaveAttribute('aria-pressed', 'true'));

    fireEvent.click(screen.getByRole('button', { name: 'Pause' }));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Game paused'));
    fireEvent.click(screen.getByRole('button', { name: 'Step' }));
    fireEvent.click(screen.getByRole('button', { name: 'Resume' }));
    fireEvent.click(screen.getByRole('button', { name: 'Stop' }));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Project loaded'));

    fireEvent.click(screen.getByRole('button', { name: 'Reload from disk' }));
    fireEvent.click(screen.getByRole('button', { name: 'Close Preview' }));
    expect(screen.getByRole('button', { name: 'Open Preview' })).toBeInTheDocument();
    expect(usePreviewStore.getState().session).toBeNull();
  });

  it('mostra o erro quando o projeto não abre', async () => {
    const fs = demoMemoryFs();
    render(<PreviewPanel fs={fs} root="/nao-existe" createTransport={async () => ({ transport: doubleTransport({ helloTimeoutMs: null }), kind: 'double' })} />);
    fireEvent.click(screen.getByRole('button', { name: 'Open Preview' }));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Preview error'));
  });
});

describe('detectPlatform', () => {
  it('reconhece o sistema do webview', () => {
    expect(detectPlatform({ userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Edg/130' })).toBe('windows');
    expect(detectPlatform({ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit' })).toBe('macos');
    expect(detectPlatform({ userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit' })).toBe('linux');
  });
});

void PLUGIN_DIR;
