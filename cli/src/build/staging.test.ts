// Build Staging (BS §4, M5-06): project.godot e build_config.gd gerados, plugins e assets no staging.
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { compileProject, loadProject } from '../bundle/index.js';
import { packPluginFolder } from '../plugins/pack.js';
import type { PreparedPlugin } from '../plugins/dependencies.js';
import { generateBuildConfig } from './build-config.js';
import { gdColor, gdString, generateProjectGodot, templateSection } from './godot-project.js';
import { checkEngineConstraints, defaultTemplateDirs, makeBuildId, stageBuild, StagingError } from './staging.js';

const repo = join(dirname(defaultTemplateDirs().runtimeDir));
const example = join(repo, 'docs', 'specs', 'examples', 'demo-project');
const fishing = join(repo, 'docs', 'specs', 'examples', 'fishing-plugin');

let tmp: string;
let template: { runtimeDir: string; sdkDir: string };

function put(path: string, text = ''): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
}

beforeAll(() => {
  tmp = mkdtempSync(join(tmpdir(), 'vn-staging-'));
  // Template mínimo: o project.godot de verdade (seções [input] e [rendering]) e uma árvore pequena.
  const runtimeDir = join(tmp, 'runtime');
  const sdkDir = join(tmp, 'sdk');
  put(join(runtimeDir, 'project.godot'), readFileSync(join(defaultTemplateDirs().runtimeDir, 'project.godot'), 'utf8'));
  put(join(runtimeDir, 'vn_runtime', 'boot.tscn'), '[gd_scene format=3]\n');
  put(join(runtimeDir, 'vn_runtime', 'presets', 'fonts', 'NotoSans-Regular.ttf'), 'x');
  put(join(runtimeDir, 'vn_runtime', 'README.md'), 'não entra');
  put(join(runtimeDir, 'tests', 'a.gd'), 'não entra');
  put(join(sdkDir, 'addons', 'vn_runtime_sdk', 'vn_result.gd'), 'x');
  template = { runtimeDir, sdkDir };
});
afterAll(() => rmSync(tmp, { recursive: true, force: true }));

describe('project.godot gerado (BS §4.3)', () => {
  const tpl = readFileSync(join(defaultTemplateDirs().runtimeDir, 'project.godot'), 'utf8');
  const base = { project: { version: '0.1.0', settings: { resolution: [1280, 720] } }, title: 'Seaside "Story"', template: tpl };

  it('põe nome, versão, cena principal, resolução e esticamento do projeto', () => {
    const g = generateProjectGodot(base);
    expect(g).toContain('config/name="Seaside \\"Story\\""');
    expect(g).toContain('config/version="0.1.0"');
    expect(g).toContain('run/main_scene="res://vn_runtime/boot.tscn"');
    expect(g).toContain('window/size/viewport_width=1280');
    expect(g).toContain('window/size/viewport_height=720');
    expect(g).toContain('window/stretch/mode="canvas_items"');
    expect(g).toContain('window/stretch/aspect="expand"');
    expect(g).toContain('locale/translations=PackedStringArray()');
    expect(g).toContain('default_texture_filter=1');
    expect(g).not.toContain('[autoload]');
  });
  it('traz as ações vn_* do template', () => {
    const g = generateProjectGodot(base);
    for (const a of ['vn_advance', 'vn_cancel', 'vn_quick_load']) expect(g).toContain(`${a}={`);
  });
  it('splash ausente: só a cor de fundo, sem a logo do Godot; com splash e ícone: os caminhos', () => {
    expect(generateProjectGodot(base)).toContain('boot_splash/show_image=false');
    const g = generateProjectGodot({ ...base, splashPath: 'res://vn_content/assets/ui/s.png', iconPath: 'res://vn_content/assets/ui/i.png' });
    expect(g).toContain('boot_splash/image="res://vn_content/assets/ui/s.png"');
    expect(g).toContain('config/icon="res://vn_content/assets/ui/i.png"');
    expect(g).not.toContain('show_image=false');
  });
  it('recusa resolução inválida e template sem [input]', () => {
    expect(() => generateProjectGodot({ ...base, project: { settings: { resolution: [0, 720] } } })).toThrow(/resolution/);
    expect(() => generateProjectGodot({ ...base, template: '[rendering]\nx=1\n' })).toThrow(/\[input\]/);
  });
  it('auxiliares', () => {
    expect(gdString('a\\b"c\nd')).toBe('"a\\\\b\\"c\\nd"');
    expect(gdColor('#ff000080')).toBe('Color(1, 0, 0, 0.502)');
    expect(templateSection('[a]\nx=1\n\n[b]\ny=2\n', 'a')).toBe('x=1');
  });
});

describe('build_config.gd (BS §4.4)', () => {
  it('gera as constantes que o VNBuildConfig lê', () => {
    const t = generateBuildConfig({
      buildId: 'id',
      contentHash: 'sha256-x',
      contentHashes: { 'narrative.vnb': 'sha256-a', 'locales/en.vnb': 'sha256-b' },
      runtimeVersion: '1.0.0',
      debug: true,
      saveTamperPolicy: 'flag',
    });
    for (const k of ['BUILD_ID', 'CONTENT_HASH', 'CONTENT_HASHES', 'RUNTIME_VERSION', 'DEBUG_BUILD', 'CONTENT_KEY', 'SAVE_KEY', 'SAVE_TAMPER_POLICY'])
      expect(t).toContain(`const ${k} =`);
    expect(t.indexOf('"locales/en.vnb"')).toBeLessThan(t.indexOf('"narrative.vnb"')); // ordem estável
  });
});

describe('B014 e build_id', () => {
  it('runtime e Godot fora da faixa do projeto dão B014', () => {
    const p = { runtime: { min_version: '1.0.0', godot: '>=4.7.0 <5.0.0' } };
    expect(() => checkEngineConstraints(p, '1.0.0', '4.7.2')).not.toThrow();
    expect(() => checkEngineConstraints(p, '0.9.0', '4.7.2')).toThrow(/B014/);
    expect(() => checkEngineConstraints(p, '1.0.0', '5.0.0')).toThrow(/B014/);
  });
  it('build_id = data UTC + 8 hex do hash do bundle', () => {
    const hash = `sha256-${Buffer.from('0123456789abcdef0123456789abcdef').toString('base64')}`;
    expect(makeBuildId(new Date('2026-11-13T22:15:00Z'), hash)).toBe('20261113-221500-30313233');
  });
});

describe('stageBuild com o exemplo das specs e o plugin fishing', () => {
  async function stage(extra: Partial<Parameters<typeof stageBuild>[0]> = {}) {
    const dir = join(tmp, `out-${Math.random().toString(36).slice(2)}`);
    // O exemplo das specs não traz os binários dos assets: aponta para uma cópia com arquivos vazios.
    const project = join(tmp, 'project');
    if (!existsSync(project)) {
      const compiledForAssets = compileProject(loadProject(example, { pluginDirs: [fishing] }));
      for (const a of Object.values(compiledForAssets.bundle.assets) as { path: string }[])
        if (a.path.startsWith('res://vn_content/assets/')) put(join(project, 'assets', a.path.slice('res://vn_content/assets/'.length)), 'x');
      put(join(project, 'project.json'), readFileSync(join(example, 'project.json'), 'utf8'));
    }
    const compiled = compileProject(loadProject(example, { pluginDirs: [fishing] }));
    const plugin: PreparedPlugin = {
      id: 'vnstudio.fishing',
      version: '1.0.0',
      namespace: 'fishing',
      trust: 'official',
      from: 'embedded',
      folder: fishing,
      package: await packPluginFolder(fishing),
    };
    const r = await stageBuild({ projectDir: project, compiled, plugins: [plugin], stagingDir: dir, now: new Date('2026-11-24T10:00:00Z'), ...template, ...extra });
    return { r, dir, compiled };
  }

  it('monta a estrutura do BS §4.2', async () => {
    const { r, dir, compiled } = await stage();
    expect(r.buildId).toMatch(/^20261124-100000-[0-9a-f]{8}$/);
    for (const f of [
      'project.godot',
      'addons/vn_runtime_sdk/vn_result.gd',
      'vn_runtime/boot.tscn',
      'vn_runtime/build_config.gd',
      'vn_content/bundle.json',
      'vn_content/plugins.json',
      'vn_content/licenses.json',
      'vn_content/build.json',
      'vn_content/locales/en.json',
      'vn_plugins/fishing/plugin.json',
      'vn_plugins/fishing/runtime/src/fishing_plugin.gd',
    ])
      expect(existsSync(join(dir, f)), f).toBe(true);
    // template: nada de testes nem .md; plugin: nada de editor/, tests/, README, CHANGELOG
    for (const f of ['vn_runtime/README.md', 'tests', 'vn_plugins/fishing/editor', 'vn_plugins/fishing/tests', 'vn_plugins/fishing/README.md', 'vn_plugins/fishing/CHANGELOG.md', 'export_presets.cfg'])
      expect(existsSync(join(dir, f)), f).toBe(false);
    const bundle = JSON.parse(readFileSync(join(dir, 'vn_content', 'bundle.json'), 'utf8'));
    expect(bundle.content_hash).toBe(compiled.bundle.content_hash);
    expect(JSON.parse(readFileSync(join(dir, 'vn_content', 'build.json'), 'utf8')).build_id).toBe(r.buildId);
    expect(readFileSync(join(dir, 'vn_runtime', 'build_config.gd'), 'utf8')).toContain(`CONTENT_HASH = "${compiled.bundle.content_hash}"`);
  });

  it('copia só os assets do jogo, na mesma árvore', async () => {
    const { dir, compiled } = await stage();
    for (const a of Object.values(compiled.bundle.assets) as { path: string }[])
      if (a.path.startsWith('res://vn_content/assets/')) expect(existsSync(join(dir, 'vn_content', 'assets', a.path.slice(24))), a.path).toBe(true);
  });

  it('é determinístico e refaz a pasta do zero', async () => {
    const a = await stage({ stagingDir: join(tmp, 'same') });
    put(join(tmp, 'same', 'velho.txt'), 'x');
    const b = await stage({ stagingDir: join(tmp, 'same') });
    expect(b.r.buildId).toBe(a.r.buildId);
    expect(existsSync(join(tmp, 'same', 'velho.txt'))).toBe(false);
  });

  it('release é recusado até o .vnb (M5-03)', async () => {
    await expect(stage({ type: 'release' })).rejects.toThrow(StagingError);
  });

  it('asset ausente é B005 e template sem presets é recusado', async () => {
    const empty = join(tmp, 'noassets');
    put(join(empty, 'project.json'), readFileSync(join(example, 'project.json'), 'utf8'));
    await expect(stage({ projectDir: empty })).rejects.toThrow(/B005/);
    const bad = join(tmp, 'badtpl');
    put(join(bad, 'project.godot'), '[input]\n');
    put(join(bad, 'vn_runtime', 'boot.tscn'), '');
    await expect(stage({ runtimeDir: bad })).rejects.toThrow(/incompleto/);
  });
});
