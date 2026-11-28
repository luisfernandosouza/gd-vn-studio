import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { closeDocumentSession, openDocumentSession } from '../document/session';
import { createProject } from '../project-manager/create';
import { MemoryFs } from '../project-manager/memory-fs';
import { openProject } from '../project-manager/open';
import { useProjectSession } from '../project-manager/session';
import { ProjectSettings } from './ProjectSettings';

const ROOT = '/jogos/verao';

async function setup() {
  const fs = new MemoryFs();
  await createProject(fs, { root: ROOT, title: 'Verão', defaultLocale: 'pt-BR' });
  const opened = await openProject(fs, ROOT);
  if (opened.status !== 'opened') throw new Error('não abriu');
  useProjectSession.setState({ current: opened.project });
  await openDocumentSession(fs, opened.project);
  render(<ProjectSettings fs={fs} />);
  // espera o contexto (capítulos, assets, tema) carregar: o botão Salvar só liga depois
  await screen.findByRole('option', { name: 'Capítulo 1' });
  return fs;
}

const saved = async (fs: MemoryFs) => JSON.parse(await fs.readText(`${ROOT}/project.json`));

describe('ProjectSettings (M7-10)', () => {
  beforeEach(() => useProjectSession.setState({ current: null }));
  afterEach(async () => {
    cleanup();
    await closeDocumentSession();
  });

  it('edita título, resolução, FPS e sorteios sem JSON e grava em project.json', async () => {
    const fs = await setup();
    const save = screen.getByRole('button', { name: 'Salvar configurações' });
    expect(save).toBeDisabled();

    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Verão 2' } });
    fireEvent.change(screen.getByLabelText('Largura base (px)'), { target: { value: '1920' } });
    fireEvent.change(screen.getByLabelText('Altura base (px)'), { target: { value: '1080' } });
    fireEvent.change(screen.getByLabelText('Limite de FPS da novel'), { target: { value: '30' } });
    fireEvent.click(screen.getByLabelText('Sorteios reproduzíveis'));
    expect(save).toBeEnabled();
    fireEvent.click(save);

    await waitFor(async () => expect((await saved(fs)).title).toBe('Verão 2'));
    const json = await saved(fs);
    expect(json.settings.resolution).toEqual([1920, 1080]);
    expect(json.settings.display.fps_limit_vn).toBe(30);
    expect(json.settings.reproducible_rng).toBe(true);
    expect(useProjectSession.getState().current?.project.title).toBe('Verão 2');
    expect(await screen.findByText('Configurações salvas em project.json.')).toBeInTheDocument();
  });

  it('adiciona idioma e final, e o salvamento fica bloqueado com valor inválido', async () => {
    const fs = await setup();
    fireEvent.change(screen.getByLabelText('Outro idioma (etiqueta BCP 47)'), { target: { value: 'ko' } });
    fireEvent.click(screen.getByRole('button', { name: 'Adicionar idioma' }));
    fireEvent.click(screen.getByRole('button', { name: 'Adicionar final' }));
    fireEvent.change(screen.getByLabelText('Título do final 1'), { target: { value: 'Final feliz' } });
    fireEvent.change(screen.getByLabelText('Identificador do final 1'), { target: { value: 'Final Feliz' } });
    expect(screen.getByText(/o identificador "Final Feliz" usa minúsculas/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Salvar configurações' })).toBeDisabled();

    fireEvent.change(screen.getByLabelText('Identificador do final 1'), { target: { value: 'final_feliz' } });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar configurações' }));
    await waitFor(async () => expect((await saved(fs)).endings).toHaveLength(1));
    const json = await saved(fs);
    expect(json.locales).toEqual(['pt-BR', 'ko']);
    expect(json.endings[0]).toEqual({ id: 'final_feliz', title: 'Final feliz' });
  });

  it('não deixa remover um final que uma cena usa', async () => {
    const fs = new MemoryFs();
    await createProject(fs, { root: ROOT, title: 'Verão', defaultLocale: 'pt-BR' });
    const project = JSON.parse(await fs.readText(`${ROOT}/project.json`));
    project.endings = [{ id: 'bom', title: 'Final bom' }];
    await fs.writeText(`${ROOT}/project.json`, JSON.stringify(project));
    const sceneFile = (await fs.readDir(`${ROOT}/scenes/capitulo_1`))[0]!.name;
    const scenePath = `${ROOT}/scenes/capitulo_1/${sceneFile}`;
    const scene = JSON.parse(await fs.readText(scenePath));
    scene.nodes.push({ id: '019a7a00-0000-7000-8000-000000000001', type: 'end', then: 'end_game', ending: 'bom' });
    await fs.writeText(scenePath, JSON.stringify(scene));
    const opened = await openProject(fs, ROOT);
    if (opened.status !== 'opened') throw new Error('não abriu');
    useProjectSession.setState({ current: opened.project });
    await openDocumentSession(fs, opened.project);
    render(<ProjectSettings fs={fs} />);
    await screen.findByText('Usado em 1 cena(s).');
    fireEvent.click(screen.getByRole('button', { name: 'Remover final 1' }));
    expect(await screen.findByText(/é usado em 1 cena/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Salvar configurações' })).toBeDisabled();
  });

  it('avisa contraste baixo do tema e confirma quando passa', async () => {
    const fs = await setup();
    expect(screen.getByText(/acima do mínimo de 4,5:1/)).toBeInTheDocument();
    cleanup();

    const theme = JSON.parse(await fs.readText(`${ROOT}/theme.json`));
    theme.colors = { text: '#cccccc', panel: '#ffffff' };
    await fs.writeText(`${ROOT}/theme.json`, JSON.stringify(theme));
    const opened = await openProject(fs, ROOT);
    if (opened.status !== 'opened') throw new Error('não abriu');
    useProjectSession.setState({ current: opened.project });
    await openDocumentSession(fs, opened.project);
    render(<ProjectSettings fs={fs} />);
    expect(await screen.findByText(/Contraste baixo/)).toBeInTheDocument();
  });

  it('descarta mudanças', async () => {
    await setup();
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Outro' } });
    expect(screen.getByText('Há mudanças não salvas.')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Descartar mudanças' }));
    await waitFor(() => expect(screen.getByLabelText('Título')).toHaveValue('Verão'));
  });
});
