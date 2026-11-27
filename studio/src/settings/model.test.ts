import type { Project } from '@vnstudio/plugin-schema';
import { describe, expect, it } from 'vitest';
import { createProject } from '../project-manager/create';
import { MemoryFs } from '../project-manager/memory-fs';
import { openProject } from '../project-manager/open';
import { fieldsToPayload, loadSettingsContext, payloadToFields, prune, saveProjectSettings, validateSettings } from './model';

const ROOT = '/jogos/verao';
const noCtx = { chapters: [], endingUsage: {} };

async function fresh() {
  const fs = new MemoryFs();
  await createProject(fs, { root: ROOT, title: 'Verão', defaultLocale: 'pt-BR' });
  const opened = await openProject(fs, ROOT);
  if (opened.status !== 'opened') throw new Error('não abriu');
  return { fs, opened: opened.project };
}

describe('prune', () => {
  it('tira vazios opcionais mas mantém group vazio do number_formats', () => {
    const out = prune({
      title: 'x',
      authors: [],
      settings: { display: { resolutions: [] }, number_formats: { ko: { decimal: '.', group: '' } } },
      content_filter: {},
      build: { company: '' },
    } as unknown as Project);
    expect(out).toEqual({ title: 'x', settings: { number_formats: { ko: { decimal: '.', group: '' } } } });
  });
});

describe('validateSettings', () => {
  it('um projeto novo não tem problemas', async () => {
    const { fs, opened } = await fresh();
    const ctx = await loadSettingsContext(fs, opened);
    expect(ctx.chapters).toHaveLength(1);
    expect(validateSettings(opened.project, ctx)).toEqual([]);
  });

  it('acusa valores fora do schema', async () => {
    const { opened } = await fresh();
    const bad: Project = {
      ...opened.project,
      version: '1.0',
      locales: ['en', 'Português'],
      settings: { resolution: [0, 1080], text_speed: -1, display: { fps_limit_vn: 500, resolutions: [[1280, 720], [1280, 720]] } },
      endings: [{ id: 'Final 1', title: '' }],
      events: [{ name: 'evento' }],
      build: { executable_name: '!ruim', locales: ['en'] },
    };
    const fields = validateSettings(bad, noCtx).map((i) => i.field);
    expect(fields).toEqual(
      expect.arrayContaining(['Versão do jogo', 'Idiomas', 'Resolução base', 'Velocidade do texto', 'Limite de FPS da novel', 'Tamanhos de janela', 'Finais', 'Eventos', 'Nome do executável', 'Idiomas do build']),
    );
  });

  it('bloqueia remover um final usado por uma cena (R012)', () => {
    const issues = validateSettings({ title: 'x', default_locale: 'en', id: 'x', format_version: '1.0.0', start_chapter: 'a' } as Project, { chapters: [], endingUsage: { bom: ['Cena A'] } });
    expect(issues.some((i) => i.field === 'Finais' && i.message.includes('"bom"'))).toBe(true);
  });

  it('exige asset registrado quando a lista de assets é conhecida', async () => {
    const { opened } = await fresh();
    const p: Project = { ...opened.project, build: { icon: 'ui/icon' } };
    expect(validateSettings(p, { ...noCtx, assets: [] }).some((i) => i.field === 'Ícone')).toBe(true);
    expect(validateSettings(p, { ...noCtx, assets: [{ id: 'ui/icon', type: 'image' }] })).toEqual([]);
  });
});

describe('payload de evento', () => {
  it('ida e volta de campos simples', () => {
    const fields = [
      { name: 'skill', type: 'integer' as const, required: true },
      { name: 'nota', type: 'string' as const, required: false },
    ];
    const payload = fieldsToPayload(fields);
    expect(payload).toEqual({ type: 'object', properties: { skill: { type: 'integer' }, nota: { type: 'string' } }, required: ['skill'] });
    expect(payloadToFields(payload)).toEqual(fields);
    expect(fieldsToPayload([])).toBeUndefined();
  });

  it('payload avançado não é editável (devolve null) e fica como está', () => {
    expect(payloadToFields({ type: 'object', properties: { x: { type: 'integer', minimum: 1 } } })).toBeNull();
    expect(payloadToFields({ oneOf: [] })).toBeNull();
  });
});

describe('saveProjectSettings', () => {
  it('grava project.json no formato do Studio, sem vazios', async () => {
    const { fs, opened } = await fresh();
    const saved = await saveProjectSettings(fs, ROOT, { ...opened.project, version: '0.2.0', authors: [], settings: { reproducible_rng: true } });
    const text = await fs.readText(`${ROOT}/project.json`);
    expect(text.endsWith('}\n')).toBe(true);
    const json = JSON.parse(text);
    expect(json.version).toBe('0.2.0');
    expect(json.authors).toBeUndefined();
    expect(json.settings).toEqual({ reproducible_rng: true });
    expect(saved).toEqual(json);
  });
});
