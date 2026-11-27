/// <reference types="node" />
// @vitest-environment node
/**
 * Aceite do M7-10: um `project.json` com todas as opções preenchidas pela camada de configurações
 * passa no validador de referência (`docs/specs/tools/validate.py`). Pulado sem Python com jsonschema,
 * exceto na CI (VNSTUDIO_REQUIRE_VALIDATOR=1).
 */
import { execFileSync, spawnSync } from 'node:child_process';
import { promises as nodeFs } from 'node:fs';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import type { Project } from '@vnstudio/plugin-schema';
import { afterAll, describe, expect, it } from 'vitest';
import { createProject } from '../project-manager/create';
import type { DirEntry, ProjectFs } from '../project-manager/fs';
import { openProject } from '../project-manager/open';
import { fieldsToPayload, loadSettingsContext, saveProjectSettings, validateSettings } from './model';

const VALIDATE = resolve(__dirname, '../../../docs/specs/tools/validate.py');
const PYTHON = process.platform === 'win32' ? 'python' : 'python3';
const hasValidator = spawnSync(PYTHON, ['-c', 'import jsonschema, referencing'], { stdio: 'ignore' }).status === 0;
if (!hasValidator && process.env.VNSTUDIO_REQUIRE_VALIDATOR === '1') {
  throw new Error('VNSTUDIO_REQUIRE_VALIDATOR=1, mas não há Python com jsonschema para rodar validate.py');
}

const diskFs: ProjectFs = {
  readText: (p) => nodeFs.readFile(p, 'utf8'),
  writeText: async (p, text) => {
    await nodeFs.mkdir(resolve(p, '..'), { recursive: true });
    await nodeFs.writeFile(p, text, 'utf8');
  },
  exists: (p) => nodeFs.access(p).then(() => true, () => false),
  createDir: async (p) => void (await nodeFs.mkdir(p, { recursive: true })),
  readDir: async (p) =>
    (await nodeFs.readdir(p, { withFileTypes: true })).map((e): DirEntry => ({ name: e.name, isDir: e.isDirectory() })).sort((a, b) => (a.name < b.name ? -1 : 1)),
  removeFile: (p) => nodeFs.rm(p, { force: true }),
  copyFile: async (from, to) => void (await nodeFs.copyFile(from, to)),
};

const temp: string[] = [];
afterAll(async () => {
  for (const dir of temp) await rm(dir, { recursive: true, force: true });
});

describe.skipIf(!hasValidator)('Configurações do projeto passam no validador (aceite do M7-10)', () => {
  it('todas as opções de project.json preenchidas', async () => {
    const base = await mkdtemp(join(tmpdir(), 'vnstudio-config-'));
    temp.push(base);
    const root = join(base, 'jogo');
    await createProject(diskFs, { root, title: 'Jogo', defaultLocale: 'pt-BR' });
    const opened = await openProject(diskFs, root);
    if (opened.status !== 'opened') throw new Error('não abriu');
    const ctx = await loadSettingsContext(diskFs, opened.project);
    const chapter = ctx.chapters[0]!.id;

    const edited: Project = {
      ...opened.project.project,
      title: 'Jogo Configurado',
      version: '1.2.3',
      authors: ['Luis', 'Ana'],
      locales: ['pt-BR', 'en', 'ko'],
      chapters: [chapter],
      runtime: { min_version: '1.0.0', godot: '>=4.7.0 <5.0.0' },
      scheduler: { tie_breaker: 'weighted_random', include_global_scenes: false },
      exclusive_groups: [{ id: 'encontros', description: 'Só um', max_plays: 2 }],
      events: [{ name: 'story.met_master', description: 'Conheceu', payload: fieldsToPayload([{ name: 'skill', type: 'integer', required: true }]) }],
      settings: {
        resolution: [1920, 1080],
        text_speed: 30,
        auto_delay: 2,
        autosave: 'scene_start',
        activity_timeout_seconds: 60,
        reproducible_rng: true,
        display: { resolutions: [[1280, 720], [1920, 1080]], display_mode: 'borderless', vsync: false, fps_limit_vn: 30, fps_limit_activity: 144 },
        number_formats: { ko: { decimal: '.', group: ',', min_grouping: 5 } },
      },
      endings: [{ id: 'final_bom', title: 'Final bom', description: 'Tudo certo', order: 1 }],
      content_filter: { default: true, ask_on_first_launch: true },
      gallery: { sections: ['endings'] },
      theme: 'theme.json',
      build: {
        executable_name: 'Jogo Configurado',
        company: 'Equipe',
        platforms: ['windows', 'web'],
        locales: ['pt-BR', 'en'],
        textures: 'lossy',
        protection: { encrypt_pck: false, save_tamper: 'reject' },
        allow_urls: false,
        edition: 'standard',
        signing: { windows: 'perfil-win' },
      },
    };
    expect(validateSettings(edited, ctx)).toEqual([]);
    await saveProjectSettings(diskFs, root, edited);

    const out = execFileSync(PYTHON, [VALIDATE, root], { encoding: 'utf8' });
    expect(out).toContain('0 erro(s)');
    expect(execFileSync(PYTHON, [VALIDATE, '--export', root], { encoding: 'utf8' })).toContain('0 erro(s)');
  });
});
