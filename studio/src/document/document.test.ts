/// <reference types="node" />
// @vitest-environment node
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createProject } from '../project-manager/create';
import { MemoryFs } from '../project-manager/memory-fs';
import { openProject } from '../project-manager/open';
import { VNError } from './errors';
import { cloneDiskState, loadLogicalDocument, planSave, commitSave, type LogicalDocument } from './logical-document';
import { applyPatch, deepEqual, withTests, type Operation } from './patch';
import { createDocumentStore, type Command } from './store';

const DEMO = resolve(__dirname, '../../../docs/specs/examples/demo-project');

function copyDir(fs: MemoryFs, from: string, to: string) {
  for (const name of readdirSync(from)) {
    const p = join(from, name);
    if (statSync(p).isDirectory()) copyDir(fs, p, `${to}/${name}`);
    else if (name !== 'SOURCE.json') fs.files.set(`${to}/${name}`, readFileSync(p, 'utf8'));
  }
}

async function demo() {
  const fs = new MemoryFs();
  copyDir(fs, DEMO, '/demo');
  for (const f of [...fs.files.keys()]) {
    const parts = f.split('/');
    for (let i = 1; i < parts.length; i++) fs.dirs.add(parts.slice(0, i).join('/'));
  }
  const result = await openProject(fs, '/demo');
  if (result.status !== 'opened') throw new Error('demo não abriu');
  const loaded = await loadLogicalDocument(fs, result.project);
  return { fs, opened: result.project, ...loaded };
}

const sceneId = '019a7a00-1388-7f6b-b667-94bbd1305982';
const err = (fn: () => unknown): VNError => {
  try {
    fn();
  } catch (e) {
    return e as VNError;
  }
  throw new Error('não lançou');
};

const sample = () => ({
  project: { id: 'p', build: { signing: { key: 'x' } } },
  variables: { global: [{ key: 'money', type: 'int', access: { r: 1 } }, { key: 'luck', type: 'int' }] },
  plugins: { 'a.b': { version: '1' } },
  scenes: { s1: { id: 's1', nodes: [{ id: 'n1', text: 'a' }, { id: 'n2', text: 'b' }] } },
});

describe('applyPatch', () => {
  it('resolve @<id> e insere antes do elemento ou no fim', () => {
    const r = applyPatch(sample(), [
      { op: 'add', path: '/scenes/s1/nodes/@n2', value: { id: 'n3', text: 'c' } },
      { op: 'add', path: '/scenes/s1/nodes/-', value: { id: 'n4', text: 'd' } },
    ]);
    expect(r.doc.scenes.s1.nodes.map((n: { id: string }) => n.id)).toEqual(['n1', 'n3', 'n2', 'n4']);
    expect(r.forward.map((o) => (o as { path: string }).path)).toEqual(['/scenes/s1/nodes/1', '/scenes/s1/nodes/3']);
  });

  it('endereça definições de variável por @<key>', () => {
    const doc = sample();
    const ops = withTests(doc, [{ op: 'replace', path: '/variables/global/@luck/type', value: 'float' }]);
    expect(applyPatch(doc, ops).doc.variables.global[1]?.type).toBe('float');
  });

  it('exige test antes de replace, remove e move', () => {
    for (const op of [
      { op: 'replace', path: '/scenes/s1/nodes/@n1/text', value: 'x' },
      { op: 'remove', path: '/scenes/s1/nodes/@n1' },
      { op: 'move', from: '/scenes/s1/nodes/@n1', path: '/scenes/s1/nodes/-' },
    ] as Operation[]) {
      expect(err(() => applyPatch(sample(), [op])).code).toBe('INVALID_PATCH');
    }
  });

  it('recusa o patch inteiro com CONFLICT quando o test não confere', () => {
    const doc = sample();
    const e = err(() =>
      applyPatch(doc, [
        { op: 'add', path: '/project/title', value: 't' },
        { op: 'test', path: '/scenes/s1/nodes/@n1/text', value: 'outro' },
        { op: 'replace', path: '/scenes/s1/nodes/@n1/text', value: 'x' },
      ]),
    );
    expect(e.code).toBe('CONFLICT');
    expect(doc.project).not.toHaveProperty('title');
  });

  it('inverte add, replace, remove, move e copy', () => {
    const doc = sample();
    const ops: Operation[] = [
      { op: 'add', path: '/project/title', value: 'T' },
      { op: 'add', path: '/scenes/s1/nodes/@n1', value: { id: 'n0', text: 'z' } },
      { op: 'test', path: '/scenes/s1/nodes/@n2/text', value: 'b' },
      { op: 'replace', path: '/scenes/s1/nodes/@n2/text', value: 'B' },
      { op: 'test', path: '/scenes/s1/nodes/@n1', value: { id: 'n1', text: 'a' } },
      { op: 'move', from: '/scenes/s1/nodes/@n1', path: '/scenes/s1/nodes/-' },
      { op: 'copy', from: '/scenes/s1/nodes/0', path: '/scenes/s1/nodes/-' },
      { op: 'test', path: '/variables/global/@luck', value: { key: 'luck', type: 'int' } },
      { op: 'remove', path: '/variables/global/@luck' },
    ];
    const r = applyPatch(doc, ops);
    expect(deepEqual(r.doc, doc)).toBe(false);
    const back = applyPatch(r.doc, r.inverse);
    expect(deepEqual(back.doc, doc)).toBe(true);
    expect(deepEqual(applyPatch(back.doc, r.forward).doc, r.doc)).toBe(true);
  });

  it('o inverso também respeita a regra do test', () => {
    const r = applyPatch(sample(), withTests(sample(), [{ op: 'remove', path: '/scenes/s1/nodes/@n1' }]));
    expect(() => applyPatch(r.doc, r.inverse)).not.toThrow();
    expect(err(() => applyPatch({ x: 1 }, r.inverse)).code).toMatch(/CONFLICT|NOT_FOUND/);
  });

  it('plugins não tocam os ponteiros proibidos', () => {
    const forbidden: Operation[] = [
      { op: 'add', path: '/plugins/x.y', value: {} },
      { op: 'test', path: '/plugins/a.b/version', value: '1' },
      { op: 'add', path: '/project/build/target', value: 'x' },
      { op: 'add', path: '/project/runtime', value: {} },
      { op: 'add', path: '/project/id', value: 'z' },
      { op: 'add', path: '/project/format_version', value: '1.0.0' },
      { op: 'add', path: '/variables/global/@luck/access', value: {} },
      { op: 'add', path: '/variables/global/-', value: { key: 'k', type: 'int', access: {} } },
      { op: 'move', from: '/project', path: '/scenes/copia' },
    ];
    for (const op of forbidden) expect(err(() => applyPatch(sample(), [op], { source: 'plugin' })).code).toBe('FORBIDDEN_PATH');
    expect(() => applyPatch(sample(), [{ op: 'add', path: '/project/title', value: 'ok' }], { source: 'plugin' })).not.toThrow();
    expect(() => applyPatch(sample(), forbidden.slice(0, 1))).not.toThrow(); // o Studio pode
  });

  it('entidade nova precisa carregar o id da chave', () => {
    expect(err(() => applyPatch(sample(), [{ op: 'add', path: '/scenes/s2', value: { id: 'outro', nodes: [] } }])).code).toBe('INVALID_PATCH');
    expect(() => applyPatch(sample(), [{ op: 'add', path: '/scenes/s2', value: { id: 's2', nodes: [] } }])).not.toThrow();
  });
});

describe('documento lógico e gravação', () => {
  it('abrir e gravar sem editar não grava nada, e a regravação total mantém o conteúdo da demo', async () => {
    const { fs, doc, disk } = await demo();
    expect(Object.keys(doc.scenes)).toContain(sceneId);
    expect(Object.keys(doc.locales)).toEqual(['en']);
    const plan = planSave(doc, cloneDiskState(disk));
    expect([...plan.writes.keys(), ...plan.deletes]).toEqual([]);
    // e a serialização reproduz os arquivos: forçar a regravação de tudo
    const forced = cloneDiskState(disk);
    forced.savedRefs.clear();
    const all = planSave(structuredClone(doc), forced);
    // Arquivos escritos à mão na demo (JSON compacto, sem $schema) são regravados no formato do Studio,
    // mas com o mesmo conteúdo.
    const noSchema = (text: string) => {
      const { $schema: _s, ...rest } = JSON.parse(text) as Record<string, unknown>;
      void _s;
      return rest;
    };
    for (const [rel, text] of all.writes) expect(noSchema(text)).toEqual(noSchema(fs.files.get(`/demo/${rel}`) as string));
    expect(all.writes.size).toBeGreaterThan(0);
  });

  it('grava só o arquivo editado, no caminho de origem', async () => {
    const { fs, opened, doc, disk } = await demo();
    const store = createDocumentStore({ fs, root: '/demo', doc, disk });
    store.applyEdit([{ op: 'add', path: `/scenes/${sceneId}/title`, value: 'Novo título' }]);
    const before = new Map(fs.files);
    await store.flush();
    const changed = [...fs.files].filter(([k, v]) => before.get(k) !== v).map(([k]) => k);
    expect(changed).toHaveLength(1);
    expect(opened.entities.scenes.some((f) => changed[0] === `/demo/${f}`)).toBe(true);
    expect(JSON.parse(fs.files.get(changed[0] as string) as string).title).toBe('Novo título');
    expect(store.getState().saveStatus).toBe('saved');
  });

  it('cria, move de capítulo e apaga arquivos de entidades; traduções vão para o arquivo da tabela', async () => {
    const fs = new MemoryFs();
    await createProject(fs, { root: '/p', title: 'Teste', defaultLocale: 'en' });
    const opened = await openProject(fs, '/p');
    if (opened.status !== 'opened') throw new Error();
    const { doc, disk } = await loadLogicalDocument(fs, opened.project);
    const store = createDocumentStore({ fs, root: '/p', doc, disk });
    const ch = Object.keys(doc.chapters)[0] as string;
    const id = '019a7a00-0000-7000-8000-000000000001';
    store.applyEdit([
      { op: 'add', path: `/scenes/${id}`, value: { id, chapter: ch, title: 'Praia', nodes: [] } },
      { op: 'add', path: '/locales/en', value: {} },
      { op: 'add', path: `/locales/en/${id}~1n1`, value: 'Hi' },
      { op: 'add', path: '/locales/en/ui~1title~1btn', value: 'Start' },
    ]);
    await store.flush();
    expect(fs.files.has('/p/scenes/chapter_1/praia.json')).toBe(true);
    expect(JSON.parse(fs.files.get(`/p/locales/en/scenes/${id}.json`) as string)).toMatchObject({ locale: 'en', strings: { [`${id}/n1`]: 'Hi' } });
    expect(fs.files.has('/p/locales/en/ui/title.json')).toBe(true);
    store.undo();
    await store.flush();
    expect(fs.files.has('/p/scenes/chapter_1/praia.json')).toBe(false);
    expect(fs.files.has(`/p/locales/en/scenes/${id}.json`)).toBe(false);
    expect(fs.files.has('/p/locales/en/ui/title.json')).toBe(false);
  });

  it('um fechamento forçado no meio da gravação é refeito na abertura', async () => {
    const { fs, opened, doc, disk } = await demo();
    const store = createDocumentStore({ fs, root: '/demo', doc, disk });
    store.applyEdit([{ op: 'add', path: `/scenes/${sceneId}/title`, value: 'Salvo' }]);
    store.applyEdit([{ op: 'add', path: '/project/title', value: 'Jogo' }]);
    // simula a queda: o diário foi gravado, mas só o primeiro arquivo chegou ao disco
    const plan = planSave(store.getState().doc, cloneDiskState(disk));
    const realWrite = fs.writeText.bind(fs);
    let writes = 0;
    fs.writeText = async (p, t) => {
      if (writes++ === 2) throw new Error('queda de energia');
      return realWrite(p, t);
    };
    await expect(commitSave(fs, '/demo', plan, cloneDiskState(disk))).rejects.toThrow('queda');
    fs.writeText = realWrite;
    const reopened = await loadLogicalDocument(fs, opened);
    expect(reopened.doc.project.title).toBe('Jogo');
    expect((reopened.doc.scenes[sceneId] as { title: string }).title).toBe('Salvo');
    expect(fs.files.has('/demo/.vnstudio/journal.json')).toBe(false);
  });
});

describe('undo/redo e autosave', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const rename: Command<{ id: string; title: string }> = {
    id: 'scene.rename',
    label: ({ title }) => `Renomear cena para ${title}`,
    build: (_doc, { id, title }) => [{ op: 'replace', path: `/scenes/${id}/title`, value: title }],
  };

  it('todo comando desfaz e refaz, e o documento volta exatamente igual', async () => {
    const { fs, doc, disk } = await demo();
    const store = createDocumentStore({ fs, root: '/demo', doc, disk });
    const first = store.getState().doc;
    const nodes = `/scenes/${sceneId}/nodes`;
    const nodeId = (doc.scenes[sceneId] as unknown as { nodes: { id: string }[] }).nodes[0]?.id as string;
    store.run(rename, { id: sceneId, title: 'A' });
    store.applyEdit([{ op: 'add', path: `${nodes}/@${nodeId}`, value: { id: '019a7a00-0000-7000-8000-0000000000aa', type: 'line', text: 'oi' } }]);
    store.applyEdit([{ op: 'move', from: `${nodes}/@${nodeId}`, path: `${nodes}/-` }], { autoTest: true });
    store.applyEdit([{ op: 'remove', path: `/variables/global/0` }], { autoTest: true });
    const last = store.getState().doc;
    expect(store.getState().undoStack).toHaveLength(4);
    while (store.canUndo()) store.undo();
    expect(deepEqual(store.getState().doc, first)).toBe(true);
    while (store.canRedo()) store.redo();
    expect(deepEqual(store.getState().doc, last)).toBe(true);
    expect(store.undo()?.label).toBe('Edição');
  });

  it('uma edição nova limpa o redo; edições do mesmo campo em sequência viram um passo', async () => {
    const { fs, doc, disk } = await demo();
    let t = 1000;
    const store = createDocumentStore({ fs, root: '/demo', doc, disk, now: () => t });
    const path = `/scenes/${sceneId}/title`;
    for (const title of ['A', 'Ab', 'Abc']) {
      store.applyEdit([{ op: 'add', path, value: title }], { coalesceKey: 'title', label: 'Digitar título' });
      t += 100;
    }
    expect(store.getState().undoStack).toHaveLength(1);
    store.undo();
    expect((store.getState().doc.scenes[sceneId] as { title?: string }).title).toBe((doc.scenes[sceneId] as { title?: string }).title);
    store.applyEdit([{ op: 'add', path: '/project/title', value: 'x' }]);
    expect(store.canRedo()).toBe(false);
  });

  it('grava em até 2 s depois da edição e nada se perde ao fechar logo em seguida', async () => {
    const { fs, doc, disk } = await demo();
    const store = createDocumentStore({ fs, root: '/demo', doc, disk });
    store.applyEdit([{ op: 'add', path: '/project/title', value: 'Rápido' }]);
    expect(store.getState().saveStatus).toBe('dirty');
    expect(fs.files.get('/demo/project.json')).not.toContain('Rápido');
    await vi.advanceTimersByTimeAsync(2000);
    expect(fs.files.get('/demo/project.json')).toContain('Rápido');
    expect(store.getState().saveStatus).toBe('saved');
    store.applyEdit([{ op: 'add', path: '/project/title', value: 'Última' }]);
    await store.dispose();
    expect(fs.files.get('/demo/project.json')).toContain('Última');
  });

  it('falha ao gravar mantém o estado sujo e tenta de novo', async () => {
    const { fs, doc, disk } = await demo();
    const store = createDocumentStore({ fs, root: '/demo', doc, disk });
    const realWrite = fs.writeText.bind(fs);
    fs.writeText = async () => {
      throw new Error('disco cheio');
    };
    store.applyEdit([{ op: 'add', path: '/project/title', value: 'Persistente' }]);
    await vi.advanceTimersByTimeAsync(1500);
    expect(store.getState().saveStatus).toBe('error');
    expect(store.getState().saveError).toBe('disco cheio');
    fs.writeText = realWrite;
    await vi.advanceTimersByTimeAsync(2500);
    expect(store.getState().saveStatus).toBe('saved');
    expect(fs.files.get('/demo/project.json')).toContain('Persistente');
  });

  it('getDocument esconde a chave de assinatura dos plugins; o guard recusa o resultado inválido', async () => {
    const { fs, doc, disk } = await demo();
    const store = createDocumentStore({ fs, root: '/demo', doc, disk, guard: (next) => ((next.project as { title?: string }).title === 'ruim' ? 'título ruim' : null) });
    const build = store.getDocument('/project', 'plugin') as { build?: { signing?: unknown } };
    expect(build.build?.signing).toBeUndefined();
    expect(err(() => store.getDocument('/project/build/signing', 'plugin')).code).toBe('FORBIDDEN_PATH');
    expect(err(() => store.applyEdit([{ op: 'add', path: '/project/title', value: 'ruim' }])).code).toBe('VALIDATION_FAILED');
    expect(store.canUndo()).toBe(false);
    void (null as unknown as LogicalDocument);
  });
});
