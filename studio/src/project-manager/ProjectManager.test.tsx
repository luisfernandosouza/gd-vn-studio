import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { App } from '../App';
import { createProject } from './create';
import { MemoryFs } from './memory-fs';
import { useProjectSession } from './session';

describe('Project Manager na janela', () => {
  afterEach(cleanup);
  beforeEach(() => {
    useProjectSession.setState({ current: null });
    try {
      localStorage.clear();
    } catch {
      // sem armazenamento
    }
  });

  it('cria um projeto pela tela e o abre', async () => {
    const fs = new MemoryFs();
    render(<App io={{ fs, pickFolder: async () => '/jogos' }} />);
    fireEvent.change(screen.getByLabelText('Nome do jogo'), { target: { value: 'Verão na Praia' } });
    fireEvent.change(screen.getByLabelText('Idioma em que você escreve'), { target: { value: 'pt-BR' } });
    fireEvent.click(screen.getByRole('button', { name: 'Escolher pasta…' }));
    expect(await screen.findByText('/jogos/verao_na_praia')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Criar projeto' }));
    expect(await screen.findByRole('heading', { name: 'Verão na Praia' })).toBeInTheDocument();
    expect(screen.getByText('1 capítulo(s)')).toBeInTheDocument();
    expect(await fs.exists('/jogos/verao_na_praia/project.json')).toBe(true);

    // fechar volta ao Project Manager, com o projeto nos recentes
    fireEvent.click(screen.getByRole('button', { name: 'Fechar projeto' }));
    expect(await screen.findByRole('button', { name: /Verão na Praia/ })).toBeInTheDocument();
  });

  it('abre um projeto existente pelo seletor de pasta', async () => {
    const fs = new MemoryFs();
    await createProject(fs, { root: '/jogos/outro', title: 'Outro Jogo', defaultLocale: 'en' });
    render(<App io={{ fs, pickFolder: async () => '/jogos/outro' }} />);
    fireEvent.click(screen.getByRole('button', { name: 'Abrir projeto…' }));
    expect(await screen.findByRole('heading', { name: 'Outro Jogo' })).toBeInTheDocument();
  });

  it('mostra a mensagem quando a pasta não é um projeto', async () => {
    const fs = new MemoryFs();
    await fs.createDir('/vazia');
    render(<App io={{ fs, pickFolder: async () => '/vazia' }} />);
    fireEvent.click(screen.getByRole('button', { name: 'Abrir projeto…' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('não tem um project.json');
  });

  it('recusa formato de um Studio mais novo', async () => {
    const fs = new MemoryFs();
    await createProject(fs, { root: '/jogos/novo', title: 'Novo', defaultLocale: 'en' });
    const project = JSON.parse(await fs.readText('/jogos/novo/project.json'));
    await fs.writeText('/jogos/novo/project.json', JSON.stringify({ ...project, format_version: '2.0.0' }));
    render(<App io={{ fs, pickFolder: async () => '/jogos/novo' }} />);
    fireEvent.click(screen.getByRole('button', { name: 'Abrir projeto…' }));
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('versão mais nova do Studio'));
  });
});
