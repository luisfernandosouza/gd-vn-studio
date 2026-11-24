import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it } from 'vitest';
import { App } from './App';
import { MemoryFs } from './project-manager/memory-fs';
import { useProjectSession } from './project-manager/session';
import { useStudioStore } from './state/studio';

describe('App', () => {
  beforeEach(() => {
    useStudioStore.setState({ ready: false });
    useProjectSession.setState({ current: null });
  });

  it('abre a janela no Project Manager e marca o Studio como pronto', () => {
    render(<App io={{ fs: new MemoryFs(), pickFolder: async () => null }} />);
    expect(screen.getByRole('heading', { name: 'Visual Novel Studio' })).toBeInTheDocument();
    expect(screen.getByRole('form', { name: 'Novo projeto' })).toBeInTheDocument();
    expect(screen.getByRole('main')).toHaveAttribute('data-ready', 'true');
  });
});
