import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it } from 'vitest';
import { App } from './App';
import { useStudioStore } from './state/studio';

describe('App', () => {
  beforeEach(() => useStudioStore.setState({ ready: false }));

  it('abre a janela vazia e marca o Studio como pronto', () => {
    render(<App />);
    expect(screen.getByRole('heading', { name: 'Visual Novel Studio' })).toBeInTheDocument();
    expect(screen.getByRole('main')).toHaveAttribute('data-ready', 'true');
  });
});
