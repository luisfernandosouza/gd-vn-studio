import { beforeEach, describe, expect, it } from 'vitest';
import { canonicalize } from '../../cli/src/bundle/jcs';
import { compileProject } from '../../cli/src/bundle/compile';
import { loadProject } from '../../cli/src/bundle/load';
import type { ProjectInput } from '../../cli/src/bundle/input';
import type { MemoryFs } from '../src/project-manager/memory-fs';
import { PreviewRpcError } from './client';
import { FakePreviewRuntime, DEMO, demoStory } from './double';
import { loadProtocolSchema } from './double/schema';
import { readProjectInput } from './project-input';
import { FULL_RELOAD_EVERY, PreviewSession } from './session';
import { COMPILE_BASE, PLUGIN_DIR, PROJECT_ROOT, demoMemoryFs } from './testing';
import { toBase64 } from './user-files';
import { previewUrls } from './urls';
import { join } from 'node:path';

const schema = loadProtocolSchema();
const urls = previewUrls('linux');

interface Rig {
  fs: MemoryFs;
  runtime: FakePreviewRuntime;
  session: PreviewSession;
  /** Requisições que o Studio mandou, em ordem. */
  sent: { method: string; params?: Record<string, unknown> }[];
  input: ProjectInput;
}

async function rig(options: { keepSaves?: boolean; now?: () => number } = {}): Promise<Rig> {
  const fs = demoMemoryFs();
  const runtime = new FakePreviewRuntime({ story: demoStory(), validator: schema, helloTimeoutMs: null, transport: 'panel' });
  const sent: Rig['sent'] = [];
  const transport = {
    onmessage: null as ((text: string) => void) | null,
    send: (text: string) => {
      sent.push(JSON.parse(text) as Rig['sent'][number]);
      runtime.send(text);
    },
    close: () => runtime.close('stop'),
  };
  runtime.onmessage = (text) => transport.onmessage?.(text);
  const session = new PreviewSession({ fs, root: PROJECT_ROOT, transport, urls, ...options });
  const input = await readProjectInput(fs, PROJECT_ROOT, { pluginDirs: [PLUGIN_DIR] });
  await session.open(input);
  return { fs, runtime, session, sent, input };
}

/** A fala da primeira cena, trocada por outro texto (uma edição de um autor). */
function editLine(input: ProjectInput, text: string): ProjectInput {
  const copy = structuredClone(input);
  const scene = copy.scenes.find((s) => (s.nodes as { text?: unknown }[]).some((n) => typeof n.text === 'string'))!;
  const node = (scene.nodes as { text?: string }[]).find((n) => typeof n.text === 'string')!;
  node.text = text;
  return copy;
}

describe('leitura do projeto pelo ProjectFs', () => {
  it('dá o mesmo bundle (content_hash e arquivos) que a CLI lendo do disco', async () => {
    const fs = demoMemoryFs();
    const mine = compileProject(await readProjectInput(fs, PROJECT_ROOT, { pluginDirs: [PLUGIN_DIR] }));
    const reference = compileProject(
      loadProject(join(COMPILE_BASE, 'demo-project'), { pluginDirs: [join(COMPILE_BASE, 'fishing-plugin')] }),
    );
    expect(mine.bundle.content_hash).toBe(reference.bundle.content_hash);
    expect(canonicalize(mine.plugins)).toBe(canonicalize(reference.plugins));
    expect(canonicalize(mine.licenses)).toBe(canonicalize(reference.licenses));
    expect(canonicalize(mine.locales)).toBe(canonicalize(reference.locales));
  });
});

describe('abertura', () => {
  it('faz hello sem token, grava o bundle canônico e carrega pela URL do protocolo vnpreview', async () => {
    const { fs, sent, session, input } = await rig();
    expect(sent.map((m) => m.method)).toEqual(['session.hello', 'preview.load']);
    expect(sent[0]!.params).toEqual({ protocol: '1.0', studio_version: '0.0.0' });
    expect(sent[1]!.params).toEqual({
      bundle_url: 'vnpreview://localhost/project/preview/narrative/',
      assets_base: 'vnpreview://localhost/project/assets/',
      user_data: 'memory',
    });
    const compiled = compileProject(input);
    const dir = `${PROJECT_ROOT}/.vnstudio/preview/narrative`;
    expect(await fs.readText(`${dir}/bundle.json`)).toBe(canonicalize(compiled.bundle));
    expect(await fs.readText(`${dir}/plugins.json`)).toBe(canonicalize(compiled.plugins));
    expect(await fs.readText(`${dir}/licenses.json`)).toBe(canonicalize(compiled.licenses));
    for (const lang of Object.keys(compiled.locales)) expect(await fs.readText(`${dir}/locales/${lang}.json`)).toBe(canonicalize(compiled.locales[lang]));
    const snap = session.getSnapshot();
    expect(snap).toMatchObject({ status: 'ready', runState: 'LOADED', hello: { platform: 'web', protocol: '1.0' } });
  });

  it('no Windows a origem é http://vnpreview.localhost', () => {
    expect(previewUrls('windows')).toMatchObject({
      bundleUrl: 'http://vnpreview.localhost/project/preview/narrative/',
      assetsBase: 'http://vnpreview.localhost/project/assets/',
      runtimePage: 'http://vnpreview.localhost/runtime/index.html',
    });
  });

  it('recusa um runtime de outro MAJOR do protocolo', async () => {
    const fs = demoMemoryFs();
    const transport = {
      onmessage: null as ((t: string) => void) | null,
      send(text: string) {
        const { id } = JSON.parse(text) as { id: number };
        queueMicrotask(() =>
          transport.onmessage?.(JSON.stringify({ jsonrpc: '2.0', id, result: { runtime_version: '9', godot_version: '4.7.2', protocol: '2.0', platform: 'web', features: [] } })),
        );
      },
      close() {},
    };
    const session = new PreviewSession({ fs, root: PROJECT_ROOT, transport, urls });
    await expect(session.open(await readProjectInput(fs, PROJECT_ROOT, { pluginDirs: [PLUGIN_DIR] }))).rejects.toThrow(/não é compatível/);
    expect(session.getSnapshot()).toMatchObject({ status: 'error' });
  });
});

describe('o painel conversa com o dublê em todos os métodos', () => {
  it('hello, load, start, pause, step, input, set_variables, get_state, explain_selection, reload, reload_plugins, show_screen, set_setting, set_locale, resume, stop', async () => {
    const { session, sent } = await rig();
    const state = await session.start({ scene: DEMO.scenes.beach, paused: true });
    expect(state).toMatchObject({ preview: 'PAUSED', scene: DEMO.scenes.beach });
    expect(session.getSnapshot()).toMatchObject({ runState: 'PAUSED', scene: DEMO.scenes.beach });
    const stepped = await session.step('blocking');
    expect(session.getSnapshot().node).toBe(stepped.node);
    expect(await session.setVariables({ 'global.player_money': 30 })).toMatchObject({ changes: expect.any(Array) });
    expect((await session.getState(['variables'])).variables).toMatchObject({ 'global.player_money': 30 });
    expect(await session.explainSelection()).toMatchObject({ candidates: expect.any(Array) });
    expect(await session.input({ action: 'advance' })).toEqual({ accepted: expect.any(Boolean) });
    expect(await session.reloadPlugins([DEMO.plugin])).toMatchObject({ reloaded: [DEMO.plugin] });
    await session.showScreen('title', { has_save: true });
    await session.setLocale('en');
    await session.setSetting('text_speed', 10);
    await session.resume();
    expect(session.getSnapshot().runState).toBe('RUNNING');
    await session.pause();
    expect(session.getSnapshot().runState).toBe('PAUSED');
    await session.stop();
    expect(session.getSnapshot()).toMatchObject({ runState: 'LOADED', scene: null });
    const methods = new Set(sent.map((m) => m.method));
    for (const m of [
      'session.hello', 'preview.load', 'preview.start', 'preview.pause', 'preview.resume', 'preview.step', 'preview.input', 'preview.set_variables',
      'preview.get_state', 'preview.explain_selection', 'preview.reload_plugins', 'preview.show_screen', 'preview.set_setting', 'preview.set_locale', 'preview.stop',
    ]) expect(methods, m).toContain(m);
  });

  it('acompanha as notificações do jogo (cena, nó) e junta o log do runtime', async () => {
    const { session, runtime } = await rig();
    await session.start({ scene: DEMO.scenes.beach });
    expect(session.getSnapshot().scene).toBe(DEMO.scenes.beach);
    runtime.notify('log', { level: 'warning', message: 'asset sem versão censurada' });
    runtime.notify('plugin.faulted', { plugin: DEMO.plugin, error: 'boom' });
    await Promise.resolve();
    const messages = session.getSnapshot().log.map((l) => l.message);
    expect(messages).toContain('asset sem versão censurada');
    expect(messages.some((m) => m.includes('boom'))).toBe(true);
    expect(session.client.seqGaps).toEqual([]);
  });

  it('erro do runtime vira PreviewRpcError com o código legível', async () => {
    const { session } = await rig();
    const err = await session.step().catch((e: unknown) => e);
    expect(err).toBeInstanceOf(PreviewRpcError);
    expect((err as PreviewRpcError).dataCode).toBe('INVALID_PREVIEW_STATE');
  });
});

describe('modo stream', () => {
  it('o botão liga e desliga content_filter no jogo em execução (preview.set_setting)', async () => {
    const { session, sent } = await rig();
    await session.start({ scene: DEMO.scenes.beach });
    await session.setContentFilter(true);
    expect(sent.at(-1)).toMatchObject({ method: 'preview.set_setting', params: { setting: 'content_filter', value: true } });
    expect(session.getSnapshot().contentFilter).toBe(true);
    await session.setContentFilter(false);
    expect(session.getSnapshot().contentFilter).toBe(false);
  });
});

describe('recarga incremental a cada edição', () => {
  let r: Rig;
  beforeEach(async () => {
    r = await rig();
    await r.session.start({ scene: DEMO.scenes.beach });
  });

  it('uma fala editada vai como um patch só, com a cena inteira, e o disco fica igual ao build', async () => {
    const edited = editLine(r.input, 'Texto novo da fala');
    const out = await r.session.update(edited);
    expect(out).toMatchObject({ kind: 'incremental', ops: 1 });
    const reload = r.sent.at(-1)!;
    expect(reload.method).toBe('preview.reload');
    const patch = (reload.params as { patch: { file: string; pointer: string; value?: unknown }[] }).patch;
    expect(patch).toHaveLength(1);
    expect(patch[0]).toMatchObject({ file: 'bundle.json' });
    expect(patch[0]!.pointer).toMatch(/^\/scenes\/[0-9a-f-]{36}$/);
    expect(reload.params).not.toHaveProperty('bundle_url');
    // regra de equivalência incremental (BS §5.1): o bundle em disco é o do build completo
    const full = compileProject(edited);
    expect(await r.fs.readText(`${PROJECT_ROOT}/.vnstudio/preview/narrative/bundle.json`)).toBe(canonicalize(full.bundle));
    expect(r.session.getSnapshot().reloads).toMatchObject({ incremental: 1, full: 0, sinceFull: 1, lastKind: 'incremental', lastResumed: expect.any(String) });
  });

  it('sem mudança não manda nada', async () => {
    const before = r.sent.length;
    expect(await r.session.update(structuredClone(r.input))).toEqual({ kind: 'none' });
    expect(r.sent.length).toBe(before);
  });

  it('um texto de idioma editado vai pelo arquivo do idioma', async () => {
    const edited = structuredClone(r.input);
    const lang = Object.keys(edited.localeFiles)[0]!;
    const doc = edited.localeFiles[lang]![0] as { strings?: Record<string, string> };
    const key = Object.keys(doc.strings ?? {})[0];
    if (!key) return; // o caso base pode não ter texto de idioma
    doc.strings![key] = 'outro texto';
    const out = await r.session.update(edited);
    expect(out.kind).toBe('incremental');
    const patch = (r.sent.at(-1)!.params as { patch: { file: string }[] }).patch;
    expect(patch[0]!.file).toBe(`locales/${lang}.json`);
  });

  it('mudança em /project pede a recarga completa, com bundle_url e changed', async () => {
    const edited = structuredClone(r.input);
    edited.project = { ...edited.project, title: 'Outro título' };
    const out = await r.session.update(edited);
    expect(out.kind).toBe('full');
    expect(r.sent.at(-1)).toMatchObject({ method: 'preview.reload', params: { bundle_url: urls.bundleUrl, changed: ['project.json'] } });
    expect(r.session.getSnapshot().reloads).toMatchObject({ full: 1, sinceFull: 0, lastKind: 'full' });
  });

  it('patch recusado com BUNDLE_INVALID cai na recarga completa', async () => {
    // o dublê recusa uma cena sem nós; o compilador a manda do jeito que o autor a deixou
    const edited = structuredClone(r.input);
    const scene = edited.scenes.find((s) => s.id === DEMO.scenes.quietDay)!;
    scene.nodes = [];
    const out = await r.session.update(edited);
    expect(out.kind).toBe('full');
    expect(r.session.getSnapshot().log.some((l) => l.message.includes('recarregando por completo'))).toBe(true);
  });

  it('a cada 50 incrementais faz uma completa para conferir memória e disco', async () => {
    let input = r.input;
    for (let i = 1; i <= FULL_RELOAD_EVERY; i++) {
      input = editLine(input, `fala ${i}`);
      await r.session.update(input);
    }
    const reloads = r.session.getSnapshot().reloads;
    expect(reloads).toMatchObject({ incremental: FULL_RELOAD_EVERY, full: 1, sinceFull: 0, lastKind: 'full' });
    expect(r.sent.at(-1)!.params).toHaveProperty('bundle_url');
  });

  it('edições em sequência são serializadas: só a última vale quando chegam várias juntas', async () => {
    const a = editLine(r.input, 'A');
    const b = editLine(r.input, 'B');
    const c = editLine(r.input, 'C');
    const before = r.sent.length;
    const results = await Promise.all([r.session.update(a), r.session.update(b), r.session.update(c)]);
    expect(results.map((x) => x.kind)).toEqual(['none', 'none', 'incremental']);
    expect(r.sent.length - before).toBe(1);
    expect(await r.fs.readText(`${PROJECT_ROOT}/.vnstudio/preview/narrative/bundle.json`)).toBe(canonicalize(compileProject(c).bundle));
  });
});

describe('dados do jogador no painel (PP §1.4)', () => {
  it('padrão em memória: não manda user_files e recusa storage.write', async () => {
    const { session, runtime, fs } = await rig();
    runtime.notify('storage.write', { path: 'saves/slot_1.json', data: toBase64('{}') });
    await new Promise((r) => setTimeout(r, 0));
    expect(await fs.exists(`${PROJECT_ROOT}/.vnstudio/preview/user/saves/slot_1.json`)).toBe(false);
    expect(session.getSnapshot().log.some((l) => l.message.includes('"Manter saves do Preview" está desligado'))).toBe(true);
  });

  it('com "Manter saves", manda o conteúdo da pasta e aplica write e delete dentro dela', async () => {
    const fs = demoMemoryFs();
    await fs.writeText(`${PROJECT_ROOT}/.vnstudio/preview/user/profile.json`, '{"a":1}');
    const runtime = new FakePreviewRuntime({ story: demoStory(), validator: schema, helloTimeoutMs: null });
    const sent: { method: string; params?: Record<string, unknown> }[] = [];
    const transport = {
      onmessage: null as ((t: string) => void) | null,
      send: (t: string) => {
        sent.push(JSON.parse(t) as (typeof sent)[number]);
        runtime.send(t);
      },
      close() {},
    };
    runtime.onmessage = (t) => transport.onmessage?.(t);
    const session = new PreviewSession({ fs, root: PROJECT_ROOT, transport, urls, keepSaves: true });
    await session.open(await readProjectInput(fs, PROJECT_ROOT, { pluginDirs: [PLUGIN_DIR] }));
    expect(sent[1]!.params).toMatchObject({ user_data: 'project', user_files: { 'profile.json': toBase64('{"a":1}') } });

    const user = `${PROJECT_ROOT}/.vnstudio/preview/user`;
    runtime.notify('storage.write', { path: 'saves/slot_1.json', data: toBase64('{"x":"ã"}') });
    await new Promise((r) => setTimeout(r, 0));
    expect(await fs.readText(`${user}/saves/slot_1.json`)).toBe('{"x":"ã"}');
    runtime.notify('storage.delete', { path: 'saves/slot_1.json' });
    await new Promise((r) => setTimeout(r, 0));
    expect(await fs.exists(`${user}/saves/slot_1.json`)).toBe(false);
  });

  it('recusa caminho absoluto, com .. ou fora da pasta, e registra no log', async () => {
    const fs = demoMemoryFs();
    const runtime = new FakePreviewRuntime({ story: demoStory(), helloTimeoutMs: null });
    const transport = { onmessage: null as ((t: string) => void) | null, send: (t: string) => runtime.send(t), close() {} };
    runtime.onmessage = (t) => transport.onmessage?.(t);
    const session = new PreviewSession({ fs, root: PROJECT_ROOT, transport, urls, keepSaves: true });
    await session.open(await readProjectInput(fs, PROJECT_ROOT, { pluginDirs: [PLUGIN_DIR] }));
    for (const path of ['/etc/passwd', '../project.json', 'saves/../../x', 'C:/x', 'a\\b', '', 'a//b', './x']) {
      runtime.notify('storage.write', { path, data: toBase64('x') });
    }
    await new Promise((r) => setTimeout(r, 0));
    const refused = session.getSnapshot().log.filter((l) => l.message.includes('caminho inválido'));
    expect(refused).toHaveLength(8);
    expect([...fs.files.keys()].filter((p) => p.includes('/user/'))).toEqual([]);
    expect(await fs.exists(`${PROJECT_ROOT}/x`)).toBe(false);
  });
});

describe('mensagens da página (código não confiável)', () => {
  it('ignora texto que não é JSON, formas erradas e respostas sem requisição', async () => {
    const { session, runtime } = await rig();
    const t = session.client as unknown as { receive(text: string): void };
    t.receive('não é json');
    t.receive('[]');
    t.receive(JSON.stringify({ jsonrpc: '2.0', id: 999, result: {} }));
    t.receive(JSON.stringify({ jsonrpc: '2.0', id: 5, method: 'preview.start', params: {} }));
    const warnings = session.getSnapshot().log.filter((l) => l.source === 'studio');
    expect(warnings).toHaveLength(4);
    expect(runtime.state).toBe('LOADED');
  });
});
