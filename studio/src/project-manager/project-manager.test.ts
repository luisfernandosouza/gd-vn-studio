import type { Project, Scene } from '@vnstudio/plugin-schema';
import { describe, expect, it } from 'vitest';
import { createProject } from './create';
import { GITIGNORE_BLOCK } from './gitignore';
import { MemoryFs } from './memory-fs';
import { applyMigration, planMigration, type Migrator } from './migrate';
import { openProject } from './open';

const ROOT = '/jogos/verao';

async function newProject(fs = new MemoryFs(), locale = 'pt-BR') {
  const created = await createProject(fs, { root: ROOT, title: 'Verão na Praia', defaultLocale: locale });
  return { fs, created };
}

const read = async (fs: MemoryFs, rel: string) => JSON.parse(await fs.readText(`${ROOT}/${rel}`));

describe('createProject', () => {
  it('grava a estrutura do Data Model §2, um arquivo por entidade', async () => {
    const { fs, created } = await newProject();
    expect(created.files).toEqual([
      'project.json',
      'variables.json',
      'assets.json',
      'plugins.json',
      'plugin-lock.json',
      'theme.json',
      'chapters/capitulo_1.json',
      'scenes/capitulo_1/inicio.json',
      '.gitignore',
    ]);
    for (const dir of ['characters', 'ui', 'sets', 'scenes/_global', 'locales/pt-BR', 'assets', '.vnstudio']) {
      expect(await fs.exists(`${ROOT}/${dir}`)).toBe(true);
    }
    expect(await fs.readText(`${ROOT}/.gitignore`)).toBe(`${GITIGNORE_BLOCK}\n`);
  });

  it('liga projeto, capítulo e cena pelos UUIDs', async () => {
    const { fs } = await newProject();
    const project = (await read(fs, 'project.json')) as Project;
    const chapter = await read(fs, 'chapters/capitulo_1.json');
    const scene = (await read(fs, 'scenes/capitulo_1/inicio.json')) as Scene;
    expect(project).toMatchObject({ format_version: '1.0.0', id: 'verao_na_praia', title: 'Verão na Praia', default_locale: 'pt-BR' });
    expect(project.start_chapter).toBe(chapter.id);
    expect(project.chapters).toEqual([chapter.id]);
    expect(chapter.entry_scene).toBe(scene.id);
    expect(scene.chapter).toBe(chapter.id);
    expect(project).not.toHaveProperty('gallery');
    expect(await read(fs, 'theme.json')).toMatchObject({ preset: 'classic' });
  });

  it('grava JSON com 2 espaços, UTF-8 sem escapes e \\n no fim', async () => {
    const { fs } = await newProject();
    const text = await fs.readText(`${ROOT}/project.json`);
    expect(text.endsWith('}\n')).toBe(true);
    expect(text).toContain('\n  "title": "Verão na Praia",\n');
  });

  it('usa os textos iniciais do idioma-fonte', async () => {
    const { fs, created } = await newProject(new MemoryFs(), 'en-GB');
    expect(created.files).toContain('scenes/chapter_1/beginning.json');
    expect(await read(fs, 'chapters/chapter_1.json')).toMatchObject({ title: 'Chapter 1' });
  });

  it('recusa pasta com arquivos, mas aceita um repositório recém-clonado', async () => {
    const fs = new MemoryFs();
    await fs.writeText(`${ROOT}/README.md`, '# Verão\n');
    await fs.writeText(`${ROOT}/.gitignore`, 'notas/\n');
    await fs.createDir(`${ROOT}/.git`);
    await newProject(fs);
    expect(await fs.readText(`${ROOT}/.gitignore`)).toBe(`notas/\n\n${GITIGNORE_BLOCK}\n`);

    const busy = new MemoryFs();
    await busy.writeText(`${ROOT}/roteiro.txt`, '...');
    await expect(newProject(busy)).rejects.toMatchObject({ code: 'folder_not_empty' });
  });

  it('recusa nome vazio e idioma inválido', async () => {
    const fs = new MemoryFs();
    await expect(createProject(fs, { root: ROOT, title: '  ', defaultLocale: 'pt-BR' })).rejects.toMatchObject({ code: 'invalid_title' });
    await expect(createProject(fs, { root: ROOT, title: 'X', defaultLocale: 'Português' })).rejects.toMatchObject({ code: 'invalid_locale' });
  });
});

describe('openProject', () => {
  it('abre um projeto novo e lista os arquivos de entidade', async () => {
    const { fs } = await newProject();
    const result = await openProject(fs, ROOT);
    expect(result.status).toBe('opened');
    if (result.status !== 'opened') return;
    expect(result.project.project.title).toBe('Verão na Praia');
    expect(result.project.entities.chapters).toEqual(['chapters/capitulo_1.json']);
    expect(result.project.entities.scenes).toEqual(['scenes/capitulo_1/inicio.json']);
    expect(result.project.gitignoreUpdated).toBe(false);
    expect(result.project.newerMinor).toBe(false);
  });

  it('repõe o bloco do .gitignore apagado pelo autor', async () => {
    const { fs } = await newProject();
    await fs.writeText(`${ROOT}/.gitignore`, 'notas/\n');
    const result = await openProject(fs, ROOT);
    expect(result.status === 'opened' && result.project.gitignoreUpdated).toBe(true);
    expect(await fs.readText(`${ROOT}/.gitignore`)).toContain('.vnstudio/');
  });

  it('avisa quando o formato é de um MINOR mais novo e recusa um MAJOR mais novo', async () => {
    const { fs } = await newProject();
    const project = await read(fs, 'project.json');
    await fs.writeText(`${ROOT}/project.json`, JSON.stringify({ ...project, format_version: '1.3.0' }));
    const minor = await openProject(fs, ROOT);
    expect(minor.status === 'opened' && minor.project.newerMinor).toBe(true);
    await fs.writeText(`${ROOT}/project.json`, JSON.stringify({ ...project, format_version: '2.0.0' }));
    expect(await openProject(fs, ROOT)).toEqual({ status: 'too_new', root: ROOT, formatVersion: '2.0.0' });
  });

  it('explica quando a pasta não é um projeto', async () => {
    const fs = new MemoryFs();
    await fs.createDir(ROOT);
    await expect(openProject(fs, ROOT)).rejects.toMatchObject({ code: 'not_a_project' });
    await fs.writeText(`${ROOT}/project.json`, '{ quebrado');
    await expect(openProject(fs, ROOT)).rejects.toMatchObject({ code: 'unreadable' });
  });
});

describe('migração (Data Model §12)', () => {
  // Um Studio de formato 3 com migradores 1→2 (não destrutivo) e 2→3 (destrutivo).
  const migrators: Migrator[] = [
    {
      from: 1,
      to: 2,
      destructive: false,
      description: 'Capítulos ganham "kind"',
      migrate(files) {
        const out = new Map(files);
        for (const [path, data] of files) if (path.startsWith('chapters/')) out.set(path, { ...(data as object), kind: 'story' });
        return out;
      },
    },
    {
      from: 2,
      to: 3,
      destructive: true,
      description: 'plugin-lock.json sai do projeto',
      migrate(files) {
        const out = new Map(files);
        out.delete('plugin-lock.json');
        return out;
      },
    },
  ];
  const options = { migrators, formatVersion: '3.0.0' };

  it('encadeia os migradores e mostra o diff antes de gravar', async () => {
    const { fs } = await newProject();
    const before = await fs.readText(`${ROOT}/project.json`);
    const result = await openProject(fs, ROOT, options);
    expect(result.status).toBe('needs_migration');
    if (result.status !== 'needs_migration') return;
    const { plan } = result;
    expect(plan.fromVersion).toBe('1.0.0');
    expect(plan.toVersion).toBe('3.0.0');
    expect(plan.steps.map((s) => `${s.from}→${s.to}`)).toEqual(['1→2', '2→3']);
    expect(plan.destructive).toBe(true);
    expect(plan.changes.map((c) => `${c.kind} ${c.path}`)).toEqual([
      'changed chapters/capitulo_1.json',
      'removed plugin-lock.json',
      'changed project.json',
    ]);
    // nada foi gravado ainda
    expect(await fs.readText(`${ROOT}/project.json`)).toBe(before);
  });

  it('recusa migração destrutiva sem confirmação explícita', async () => {
    const { fs } = await newProject();
    const plan = await planMigration(fs, ROOT, options);
    await expect(applyMigration(fs, plan, { confirmed: false })).rejects.toMatchObject({ code: 'not_confirmed' });
    expect(await fs.exists(`${ROOT}/plugin-lock.json`)).toBe(true);
  });

  it('faz backup, grava e depois o projeto abre', async () => {
    const { fs } = await newProject();
    const original = await fs.readText(`${ROOT}/plugin-lock.json`);
    const plan = await planMigration(fs, ROOT, options);
    const backup = await applyMigration(fs, plan, { confirmed: true, now: new Date('2026-11-24T01:02:03.004Z') });
    expect(backup).toBe('.vnstudio/backups/2026-11-24T01-02-03-004Z-format-1.0.0-para-3.0.0');
    expect(await fs.readText(`${ROOT}/${backup}/plugin-lock.json`)).toBe(original);
    expect(await fs.exists(`${ROOT}/plugin-lock.json`)).toBe(false);
    expect(await read(fs, 'chapters/capitulo_1.json')).toMatchObject({ kind: 'story' });
    const reopened = await openProject(fs, ROOT, options);
    expect(reopened.status).toBe('opened');
  });

  it('migração não destrutiva não pede confirmação', async () => {
    const { fs } = await newProject();
    const plan = await planMigration(fs, ROOT, { migrators, formatVersion: '2.0.0' });
    expect(plan.destructive).toBe(false);
    await applyMigration(fs, plan, { confirmed: false });
    expect(await read(fs, 'project.json')).toMatchObject({ format_version: '2.0.0' });
  });

  it('para quando falta um migrador no caminho', async () => {
    const { fs } = await newProject();
    await expect(planMigration(fs, ROOT, { migrators: [], formatVersion: '2.0.0' })).rejects.toMatchObject({ code: 'unreadable' });
  });
});
