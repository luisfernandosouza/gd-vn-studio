import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { PreviewPanel } from './PreviewPanel';
import { usePreviewStore } from './store';
import { doubleTransport } from './transport';
import { PLUGIN_DIR, PROJECT_ROOT, demoMemoryFs } from './testing';
import { detectPlatform } from './urls';

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
    fireEvent.click(screen.getByRole('button', { name: 'Abrir Preview' }));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Projeto carregado'));
    expect(screen.getByRole('status')).toHaveTextContent('runtime de teste (dublê)');

    fireEvent.click(screen.getByRole('button', { name: 'Iniciar' }));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Jogo em andamento'));

    const stream = screen.getByRole('button', { name: 'Modo stream' });
    expect(stream).toHaveAttribute('aria-pressed', 'false');
    fireEvent.click(stream);
    await waitFor(() => expect(stream).toHaveAttribute('aria-pressed', 'true'));

    fireEvent.click(screen.getByRole('button', { name: 'Pausar' }));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Jogo pausado'));
    fireEvent.click(screen.getByRole('button', { name: 'Passo' }));
    fireEvent.click(screen.getByRole('button', { name: 'Continuar' }));
    fireEvent.click(screen.getByRole('button', { name: 'Parar' }));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Projeto carregado'));

    fireEvent.click(screen.getByRole('button', { name: 'Recarregar do disco' }));
    fireEvent.click(screen.getByRole('button', { name: 'Fechar Preview' }));
    expect(screen.getByRole('button', { name: 'Abrir Preview' })).toBeInTheDocument();
    expect(usePreviewStore.getState().session).toBeNull();
  });

  it('mostra o erro quando o projeto não abre', async () => {
    const fs = demoMemoryFs();
    render(<PreviewPanel fs={fs} root="/nao-existe" createTransport={async () => ({ transport: doubleTransport({ helloTimeoutMs: null }), kind: 'double' })} />);
    fireEvent.click(screen.getByRole('button', { name: 'Abrir Preview' }));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Erro no Preview'));
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
