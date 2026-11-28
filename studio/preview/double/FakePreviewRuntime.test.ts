import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { CloseCode, FakePreviewRuntime, RpcCode, type FakePreviewRuntimeOptions } from './FakePreviewRuntime';
import { installFakeBridge, type VnPreviewBridge } from './bridge';
import { loadProtocolSchema } from './schema';
import { DEMO, demoStory } from './story';
import { TestClient } from './testing';
import type { JsonObject } from './types';
import recording from './recordings/dev-notifications.json';

const schema = loadProtocolSchema();
const BUNDLE_URL = 'vnpreview://localhost/project/preview/narrative/';
const ASSETS = 'vnpreview://localhost/project/assets/';
const TOKEN = 'ab'.repeat(32);

let runtimes: FakePreviewRuntime[] = [];

function make(options: Partial<FakePreviewRuntimeOptions> = {}): { rt: FakePreviewRuntime; client: TestClient } {
  const rt = new FakePreviewRuntime({ story: demoStory(), validator: schema, helloTimeoutMs: null, ...options });
  runtimes.push(rt);
  return { rt, client: new TestClient(rt) };
}

async function loaded(options: Partial<FakePreviewRuntimeOptions> = {}, load: JsonObject = {}) {
  const made = make(options);
  await made.client.ok('session.hello', { protocol: '1.0', studio_version: '0.1.0' });
  await made.client.ok('preview.load', { bundle_url: BUNDLE_URL, assets_base: ASSETS, ...load });
  return made;
}

beforeEach(() => {
  runtimes = [];
});

afterEach(() => {
  for (const rt of runtimes) {
    // Revalida tudo o que o dublê mandou: forma geral e o resultado de cada método ($defs/<Método>_result).
    for (const message of rt.sent) {
      const method = rt.respondsTo.get(message);
      if ('result' in message) expect(method).toBeDefined();
      expect(schema.checkOutgoing(message, method), JSON.stringify(message)).toBeNull();
    }
    let seq = 0;
    for (const message of rt.sent) {
      if ('method' in message) {
        expect(message.params.seq).toBe(++seq);
      }
    }
  }
});

describe('sessão (§1, §2)', () => {
  it('responde ao hello do painel sem token, com plataforma web', async () => {
    const { rt, client } = make();
    const result = await client.ok('session.hello', { protocol: '1.0', studio_version: '0.1.0' });
    expect(result).toEqual({ runtime_version: '1.0.0', godot_version: '4.7.2', protocol: '1.0', platform: 'web', features: ['reproducible_rng', 'show_screen'] });
    expect(rt.state).toBe('READY');
  });

  it('recusa mensagem antes do hello com UNAUTHENTICATED no painel', async () => {
    const { client } = make();
    const response = await client.call('preview.get_state');
    expect(response.error).toMatchObject({ code: RpcCode.UNAUTHENTICATED, data: { code: 'UNAUTHENTICATED' } });
  });

  it('fecha a janela com 4401 quando o token está errado ou falta o hello', async () => {
    const { rt } = make({ transport: 'window', token: TOKEN, platform: 'windows' });
    const closed = vi.fn();
    rt.onclose = closed;
    rt.send(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'session.hello', params: { token: 'cd'.repeat(32), protocol: '1.0' } }));
    await Promise.resolve();
    expect(closed).toHaveBeenCalledWith(CloseCode.UNAUTHENTICATED);
    expect(rt.state).toBe('CLOSED');
    expect(rt.sent).toHaveLength(0);

    const other = make({ transport: 'window', token: TOKEN });
    const closed2 = vi.fn();
    other.rt.onclose = closed2;
    other.rt.send(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'preview.get_state' }));
    await Promise.resolve();
    expect(closed2).toHaveBeenCalledWith(CloseCode.UNAUTHENTICATED);
  });

  it('aceita o token certo na janela e informa a plataforma', async () => {
    const { client } = make({ transport: 'window', token: TOKEN, platform: 'windows' });
    const result = await client.ok('session.hello', { token: TOKEN, protocol: '1.0', studio_version: '0.1.0' });
    expect(result.platform).toBe('windows');
    const load = await client.ok('preview.load', { bundle_path: 'C:\\jogo\\.vnstudio\\preview\\narrative', assets_base: 'C:\\jogo\\assets' });
    expect(load.chapters).toBe(2);
  });

  it('expira o hello em 5 segundos', async () => {
    vi.useFakeTimers();
    try {
      const panel = make({ helloTimeoutMs: 5000 });
      const window = make({ transport: 'window', token: TOKEN, helloTimeoutMs: 5000 });
      const closed = vi.fn();
      window.rt.onclose = closed;
      vi.advanceTimersByTime(5000);
      await panel.client.flush();
      expect(panel.client.received[0]?.error?.data?.code).toBe('UNAUTHENTICATED');
      expect(closed).toHaveBeenCalledWith(CloseCode.UNAUTHENTICATED);
    } finally {
      vi.useRealTimers();
    }
  });

  it('recusa MAJOR diferente com UNSUPPORTED_VERSION', async () => {
    const { client, rt } = make();
    const response = await client.call('session.hello', { protocol: '2.0' });
    expect(response.error).toMatchObject({ code: RpcCode.UNSUPPORTED_VERSION, data: { code: 'UNSUPPORTED_VERSION' } });
    expect(rt.state).toBe('CONNECTED');
  });

  it('dá os erros padrão do JSON-RPC', async () => {
    const { rt, client } = make();
    await client.ok('session.hello', { protocol: '1.0' });
    rt.send('{não é json');
    rt.send('[]');
    rt.send(JSON.stringify({ jsonrpc: '2.0', id: 9, method: 'preview.voar' }));
    rt.send(JSON.stringify({ jsonrpc: '2.0', id: 10, method: 'preview.step', params: { until: 'sempre' } }));
    await client.flush();
    const codes = client.received.slice(1).map((m) => m.error?.code);
    expect(codes).toEqual([RpcCode.PARSE_ERROR, RpcCode.INVALID_REQUEST, RpcCode.METHOD_NOT_FOUND, RpcCode.INVALID_PARAMS]);
  });

  it('recusa método fora do estado com INVALID_PREVIEW_STATE e data.state', async () => {
    const { client } = make();
    await client.ok('session.hello', { protocol: '1.0' });
    const response = await client.call('preview.start', {});
    expect(response.error).toMatchObject({ code: RpcCode.INVALID_PREVIEW_STATE, data: { code: 'INVALID_PREVIEW_STATE', state: 'READY' } });
  });

  it('manda session.closing ao fechar', async () => {
    const { rt, client } = await loaded();
    rt.close('stop');
    await client.flush();
    expect(client.notifications('session.closing')[0]).toMatchObject({ reason: 'stop', phase: 'TITLE' });
    expect(rt.state).toBe('CLOSED');
  });
});

describe('preview.load (§1.3, §1.4, §7)', () => {
  it('devolve o resumo do bundle', async () => {
    const { client } = make();
    await client.ok('session.hello', { protocol: '1.0' });
    const result = await client.ok('preview.load', { bundle_url: BUNDLE_URL, assets_base: ASSETS, locale: 'en' });
    expect(result).toMatchObject({ format_version: '1.0.0', chapters: 2, scenes: 5, plugins: ['vnstudio.fishing'] });
  });

  it('recusa bundle fora de .vnstudio/preview/ e o transporte errado', async () => {
    const { client } = make({ transport: 'window', token: TOKEN });
    await client.ok('session.hello', { protocol: '1.0', token: TOKEN });
    const outside = await client.call('preview.load', { bundle_path: '/home/autor/jogo/build', assets_base: '/home/autor/jogo/assets' });
    expect(outside.error).toMatchObject({ code: RpcCode.BUNDLE_INVALID, data: { path: 'bundle_path' } });
    const wrong = await client.call('preview.load', { bundle_url: BUNDLE_URL, assets_base: ASSETS });
    expect(wrong.error?.data?.detail).toBe('wrong_transport');
  });

  it('responde BUSY enquanto um load longo não termina', async () => {
    vi.useFakeTimers();
    try {
      const { rt, client } = make({ longRequestMs: 100 });
      rt.send(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'session.hello', params: { protocol: '1.0' } }));
      rt.send(JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'preview.load', params: { bundle_url: BUNDLE_URL, assets_base: ASSETS } }));
      rt.send(JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'preview.get_state' }));
      await client.flush();
      expect(client.received.find((m) => m.id === 3)?.error?.data?.code).toBe('BUSY');
      expect(client.received.find((m) => m.id === 2)).toBeUndefined();
      vi.advanceTimersByTime(100);
      await client.flush();
      expect(client.received.find((m) => m.id === 2)?.result).toMatchObject({ chapters: 2 });
    } finally {
      vi.useRealTimers();
    }
  });
});

describe('jogo (§3, §4)', () => {
  it('joga a demo inteira na ordem do §4.2', async () => {
    const { client } = await loaded();
    const state = await client.ok('preview.start', {});
    expect(state).toMatchObject({ phase: 'SCENE_RUNNING', preview: 'RUNNING', chapter: DEMO.chapter1, scene: DEMO.scenes.arrival });
    expect(client.trace(2).slice(0, 4)).toEqual(['chapter.started', 'scene.started', 'node.entered', 'node.entered']);
    expect(client.notifications('scene.started')[0]).toMatchObject({ reason: 'entry', selection_count: 0 });

    // Chegada: avança a linha, efeito de dinheiro, fim implícito, seleção → Encontro no trem (priority).
    await client.ok('preview.input', { action: 'advance' });
    const evaluated = client.notifications('scheduler.evaluated');
    expect(evaluated[0]).toMatchObject({ chosen: DEMO.scenes.beach, reason: 'priority', selection_count: 1, chapter: DEMO.chapter1 });
    const trace = client.trace();
    const ended = trace.indexOf('scene.ended');
    expect(trace.slice(ended - 2, ended + 4)).toEqual(['node.entered', 'state.changed', 'scene.ended', 'scheduler.evaluated', 'scene.started', 'node.entered']);

    let current = await client.ok<JsonObject>('preview.get_state', {});
    expect(current.scene).toBe(DEMO.scenes.beach);
    expect(current.node).toBe(DEMO.nodes.beachGreeting);
    expect((current.variables as JsonObject)['global.player_money']).toBe(100);
    expect(current.backlog).toEqual([
      { speaker: null, text: 'O trem segue pela costa, e o mar aparece na janela.' },
      { speaker: 'Alice', text: 'Oi! Você é novo por aqui? Eu tenho 100 moedas, e você?' },
    ]);
    expect(current.stage).toMatchObject({ background: 'bg/train_beach', characters: [{ id: DEMO.alice, expression: 'happy', position: 'center' }], audio: { music: { asset: 'music/waves', loop: true } } });

    // Escolha "comprar sorvete": record + efeito, em uma transação de origem choice.
    await client.ok('preview.input', { action: 'advance' });
    const choice = await client.ok('preview.input', { action: 'choose', option: DEMO.options.icecream });
    expect(choice).toEqual({ accepted: true });
    const changes = client.notifications('state.changed').filter((n) => n.source === 'choice');
    expect(changes[0]?.changes).toEqual([{ variable: 'scene.current_choice', old: 'talk', new: 'icecream' }]);

    // Daí: efeitos, fim → fallback "Um dia tranquilo" → interação.
    current = await client.ok<JsonObject>('preview.get_state', { include: ['variables'] });
    expect(current.scene).toBe(DEMO.scenes.quietDay);
    expect((current.variables as JsonObject)['chapter.days_passed']).toBe(1);
    expect((current.variables as JsonObject)['global.player_money']).toBe(50);
    expect(current.history).toBeUndefined();
    await client.ok('preview.input', { action: 'advance' });
    expect(await client.ok('preview.input', { action: 'click', hotspot: DEMO.hotspots.lamp })).toEqual({ accepted: true });
    await client.ok('preview.input', { action: 'advance' });
    // "once": a lâmpada sumiu.
    expect(await client.ok('preview.input', { action: 'click', hotspot: DEMO.hotspots.lamp })).toEqual({ accepted: false });
    // Saída da interação → efeitos → fim → sai do capítulo → festival → final.
    await client.ok('preview.input', { action: 'advance' });
    await client.ok('preview.input', { action: 'advance' });
    const end = client.trace();
    expect(end.slice(end.lastIndexOf('chapter.ended') - 2)).toEqual([
      'scene.ended', 'scheduler.evaluated', 'chapter.ended', 'chapter.started', 'scene.started',
      'node.entered', 'node.entered', 'node.entered', 'scene.ended', 'event.emitted', 'game.ended',
    ]);
    expect(client.notifications('game.ended')[0]).toMatchObject({ ending: 'festival_ending', phase: 'GAME_END' });
  });

  it('começa pausado numa cena com variáveis e anda com step', async () => {
    const { client } = await loaded();
    const state = await client.ok('preview.start', { scene: DEMO.scenes.beach, variables: { 'global.player_money': 500 }, paused: true });
    expect(state).toMatchObject({ preview: 'PAUSED', scene: DEMO.scenes.beach, node: DEMO.nodes.beachFirst });
    expect(client.notifications('scene.started')[0]).toMatchObject({ reason: 'start' });
    expect(client.notifications('node.entered')).toHaveLength(0);

    expect(await client.ok('preview.step', {})).toEqual({ node: '019a7a00-32c8-7abc-bd4e-760003754829', phase: 'SCENE_RUNNING' });
    expect(await client.ok('preview.step', { until: 'blocking' })).toEqual({ node: DEMO.nodes.beachGreeting, phase: 'SCENE_RUNNING' });
    const step = await client.ok('preview.step', { until: 'blocking' });
    expect(step).toEqual({ node: DEMO.nodes.beachChoice, phase: 'SCENE_RUNNING' });
    expect(await client.ok('preview.resume')).toEqual({ node: DEMO.nodes.beachChoice });
    expect(await client.ok('preview.pause')).toEqual({ node: DEMO.nodes.beachChoice });
    await client.ok('preview.stop');
    const after = await client.ok('preview.get_state', {});
    expect(after).toMatchObject({ phase: 'TITLE', scene: null, node: null });
  });

  it('roda e pula atividades de plugin', async () => {
    const { client } = await loaded();
    await client.ok('preview.start', { scene: DEMO.scenes.beach, node: DEMO.nodes.beachChoice });
    await client.ok('preview.input', { action: 'choose', option: DEMO.options.fish });
    expect(client.notifications('activity.started')[0]).toMatchObject({ activity: DEMO.activity, mode: 'story', node: DEMO.nodes.beachFishing, phase: 'ACTIVITY' });
    const busy = await client.call('preview.set_variables', { variables: { 'global.player_money': 1 } });
    expect(busy.error?.data).toMatchObject({ code: 'INVALID_PREVIEW_STATE', state: 'RUNNING' });
    expect(await client.ok('preview.input', { action: 'complete_activity', outcome: 'empate' })).toEqual({ accepted: false });
    expect(await client.ok('preview.input', { action: 'cancel_activity' })).toEqual({ accepted: false });
    await client.ok('preview.input', { action: 'complete_activity', outcome: 'won', payload: { won: true, fish_count: 4, score: 1250 } });
    expect(client.notifications('activity.ended')[0]).toMatchObject({ outcome: 'won', skipped: false, failed: false, mode: 'story' });
    const state = await client.ok<JsonObject>('preview.get_state', { include: ['variables', 'plugins'] });
    expect(state.variables).toMatchObject({ 'global.fishing_won': true, 'global.fishing_skill': 12, 'global.player_money': 40 });
    expect(state.node).toBe('019a7a00-5dc0-7aff-afa3-e85b08375cdf');

    const skip = await loaded();
    await skip.client.ok('preview.start', { scene: DEMO.scenes.beach, node: DEMO.nodes.beachFishing });
    expect(await skip.client.ok('preview.input', { action: 'skip_activity' })).toEqual({ accepted: true });
    expect(skip.client.notifications('activity.ended')[0]).toMatchObject({ outcome: 'lost', skipped: true });
    expect(skip.client.notifications('state.changed')).toHaveLength(0);
  });

  it('roda a atividade no modo livre em LOADED', async () => {
    const { rt, client } = await loaded();
    const refused = await client.call('preview.input', { action: 'advance' });
    expect(refused.error?.data?.code).toBe('INVALID_PREVIEW_STATE');
    expect(await client.ok('preview.input', { action: 'play_activity', activity: DEMO.activity })).toEqual({ accepted: true });
    expect(await client.ok('preview.input', { action: 'skip_activity' })).toEqual({ accepted: false });
    expect(await client.ok('preview.input', { action: 'cancel_activity' })).toEqual({ accepted: true });
    expect(client.notifications('activity.ended')[0]).toMatchObject({ mode: 'free_play', outcome: 'cancelled' });
    expect(rt.state).toBe('LOADED');
    const missing = await client.call('preview.input', { action: 'play_activity', activity: 'fishing.voar' });
    expect(missing.error?.data).toMatchObject({ code: 'NOT_FOUND', kind: 'activity' });
  });

  it('valida escritas do set_variables como o State Manager', async () => {
    const { client } = await loaded();
    await client.ok('preview.start', { scene: DEMO.scenes.beach, paused: true });
    expect(await client.ok('preview.set_variables', { variables: { 'global.player_money': 30, 'scene.current_choice': 'fish' } })).toEqual({
      changes: [
        { variable: 'global.player_money', old: 0, new: 30 },
        { variable: 'scene.current_choice', old: 'talk', new: 'fish' },
      ],
    });
    expect(client.notifications('state.changed')[0]).toMatchObject({ source: 'preview' });
    const cases: [JsonObject, string][] = [
      [{ 'global.is_rich': true }, 'READ_ONLY'],
      [{ 'sys.selection_count': 3 }, 'READ_ONLY'],
      [{ 'global.player_money': 'muito' }, 'TYPE_MISMATCH'],
      [{ 'global.player_money': 100000 }, 'CONSTRAINT_VIOLATION'],
      [{ 'scene.current_choice': 'nadar' }, 'CONSTRAINT_VIOLATION'],
      [{ 'global.nao_existe': 1 }, 'VARIABLE_NOT_FOUND'],
    ];
    for (const [variables, vnCode] of cases) {
      const response = await client.call('preview.set_variables', { variables });
      expect(response.error, vnCode).toMatchObject({ code: RpcCode.STATE_REJECTED, data: { code: 'STATE_REJECTED', vn_code: vnCode } });
    }
    // Clamp do fishing_skill (sem on_overflow: reject).
    expect(await client.ok('preview.set_variables', { variables: { 'global.fishing_skill': 500 } })).toEqual({
      changes: [{ variable: 'global.fishing_skill', old: 0, new: 100 }],
    });
  });

  it('dá NOT_FOUND para cena, nó, opção e hotspot inexistentes', async () => {
    const { client } = await loaded();
    const ghost = '019a7a00-ffff-7fff-bfff-ffffffffffff';
    expect((await client.call('preview.start', { scene: ghost })).error?.data).toMatchObject({ code: 'NOT_FOUND', kind: 'scene', id: ghost });
    expect((await client.call('preview.start', { scene: DEMO.scenes.beach, node: ghost })).error?.data).toMatchObject({ kind: 'node' });
    await client.ok('preview.start', { scene: DEMO.scenes.beach, node: DEMO.nodes.beachChoice });
    expect((await client.call('preview.input', { action: 'choose', option: ghost })).error?.data).toMatchObject({ kind: 'option' });
    expect(await client.ok('preview.input', { action: 'click', hotspot: ghost })).toEqual({ accepted: false });
  });

  it('respeita o modo stream (censor e censored_text)', async () => {
    const { client } = await loaded();
    await client.ok('preview.start', { scene: DEMO.scenes.beach, node: '019a7a00-61a8-79a8-a339-bfeac680291c', content_filter: true });
    const state = await client.ok<JsonObject>('preview.get_state', { include: ['backlog', 'variables'] });
    expect(state.backlog).toEqual([{ speaker: 'Alice', text: 'Não foi dessa vez... (versão censurada)' }]);
    expect((state.variables as JsonObject)['sys.content_filter']).toBe(true);
  });

  it('semeia o RNG com reproducible_rng', async () => {
    const { client } = await loaded();
    const state = await client.ok('preview.start', { seed: '0123456789abcdef', paused: true });
    expect(state.rng).toEqual({ seed: '0123456789abcdef', state: '0123456789abcdef' });
  });
});

describe('"por que não apareceu" (§4.3)', () => {
  it('explica a seleção sem mudar o estado', async () => {
    const { client } = await loaded();
    await client.ok('preview.start', { paused: true });
    const before = client.received.length;
    const evaluation = await client.ok<JsonObject>('preview.explain_selection', { scene: DEMO.scenes.fishingMaster });
    expect(evaluation).toMatchObject({ selection_count: 0, chapter: DEMO.chapter1, action: 'start_scene', chosen: DEMO.scenes.beach, reason: 'priority' });
    expect(evaluation.candidates).toEqual([
      expect.objectContaining({ scene: DEMO.scenes.fishingMaster, eligible: false, blocked_by: 'conditions' }),
    ]);
    expect(client.trace(before)).toEqual([]);
    const again = await client.ok<JsonObject>('preview.explain_selection', {});
    expect((again.candidates as unknown[]).length).toBe(3);
  });
});

describe('preview.reload (§3)', () => {
  const sceneEntity = (nodes: JsonObject[]) => ({ id: DEMO.scenes.beach, chapter: DEMO.chapter1, nodes });

  it('continua no mesmo nó quando ele ainda existe', async () => {
    const { client } = await loaded();
    await client.ok('preview.start', { scene: DEMO.scenes.beach });
    const nodes = [{ id: DEMO.nodes.beachGreeting, type: 'line', text: 'Oi de novo!' }];
    const result = await client.ok('preview.reload', { patch: [{ file: 'bundle.json', pointer: `/scenes/${DEMO.scenes.beach}`, value: sceneEntity(nodes) }] });
    expect(result).toEqual({ resumed: 'node' });
  });

  it('reinicia a cena quando o nó sumiu e volta à seleção quando a cena sumiu', async () => {
    const { client } = await loaded();
    await client.ok('preview.start', { scene: DEMO.scenes.beach });
    const nodes = [{ id: '019a7a00-0001-7000-8000-000000000001', type: 'line', text: 'Cena nova.' }];
    const restarted = await client.ok('preview.reload', { patch: [{ file: 'bundle.json', pointer: `/scenes/${DEMO.scenes.beach}`, value: sceneEntity(nodes) }] });
    expect(restarted).toEqual({ resumed: 'scene_restarted' });
    expect((await client.ok('preview.get_state', { include: [] })).node).toBe('019a7a00-0001-7000-8000-000000000001');

    const removed = await client.ok('preview.reload', { patch: [{ file: 'bundle.json', pointer: `/scenes/${DEMO.scenes.beach}` }] });
    expect(removed).toEqual({ resumed: 'selection_point' });
    expect(client.notifications('scheduler.evaluated')).toHaveLength(1);
  });

  it('redesenha só a tela em trocas de ui e idioma, e devolve not_running sem jogo', async () => {
    const { client } = await loaded();
    const patch = [{ file: 'locales/en.json', pointer: '/strings/ui~1title~1start', value: 'Begin' }];
    expect(await client.ok('preview.reload', { patch })).toEqual({ resumed: 'not_running' });
    await client.ok('preview.start', { paused: true });
    expect(await client.ok('preview.reload', { patch: [{ file: 'bundle.json', pointer: '/ui/title', value: { id: 'title' } }] })).toEqual({ resumed: 'ui_only' });
  });

  it('exige recarga completa para projeto e variáveis, e não aplica nada com erro', async () => {
    const { client } = await loaded();
    await client.ok('preview.start', { scene: DEMO.scenes.beach });
    const response = await client.call('preview.reload', {
      patch: [
        { file: 'bundle.json', pointer: `/scenes/${DEMO.scenes.beach}` },
        { file: 'bundle.json', pointer: '/variables', value: {} },
      ],
    });
    expect(response.error).toMatchObject({ code: RpcCode.BUNDLE_INVALID, data: { detail: 'full_reload_required', path: '/patch/1' } });
    expect((await client.ok('preview.get_state', { include: [] })).scene).toBe(DEMO.scenes.beach);
    const full = await client.ok('preview.reload', { bundle_url: BUNDLE_URL, changed: ['variables.json'] });
    expect(full).toMatchObject({ resumed: 'node' });
    expect(typeof full.content_hash).toBe('string');
  });

  it('recarrega plugins', async () => {
    const { client } = await loaded();
    await client.ok('preview.start', { scene: DEMO.scenes.beach, node: DEMO.nodes.beachFishing });
    expect(await client.ok('preview.reload_plugins', { ids: [DEMO.plugin] })).toEqual({ reloaded: [DEMO.plugin], activity_restarted: true });
    expect((await client.call('preview.reload_plugins', { ids: ['nao.existe'] })).error?.data).toMatchObject({ kind: 'plugin' });
  });
});

describe('Menu Editor e configurações (§3)', () => {
  it('abre telas de ui/ com valores fingidos', async () => {
    const { rt, client } = await loaded();
    expect(await client.ok('preview.show_screen', { screen: 'title', simulate: { has_save: true, endings: ['festival_ending'] } })).toEqual({});
    expect(rt.screen).toEqual({ screen: 'title', simulate: { has_save: true, endings: ['festival_ending'] } });
    expect((await client.call('preview.show_screen', { screen: 'loja' })).error?.data).toMatchObject({ code: 'NOT_FOUND', kind: 'screen' });
  });

  it('muda o modo stream com o evento do RT §5.5 e troca o idioma', async () => {
    const { client } = await loaded();
    await client.ok('preview.set_setting', { setting: 'content_filter', value: true });
    expect(client.notifications('event.emitted')[0]).toMatchObject({ name: 'sys.content_filter_changed', payload: { enabled: true } });
    expect((await client.call('preview.set_setting', { setting: 'voar', value: 1 })).error?.code).toBe(RpcCode.INVALID_PARAMS);
    expect(await client.ok('preview.set_locale', { locale: 'en' })).toEqual({});
    expect((await client.call('preview.set_locale', { locale: 'ja' })).error?.data).toMatchObject({ kind: 'locale' });
  });
});

describe('dados do jogador (§1.4)', () => {
  it('no painel com user_data project, avisa cada gravação com storage.write', async () => {
    const settings = btoa(JSON.stringify({ content_filter: true }));
    const { rt, client } = await loaded({}, { user_data: 'project', user_files: { 'settings.json': settings } });
    await client.ok('preview.start', {});
    await client.ok('preview.input', { action: 'advance' });
    const writes = client.notifications('storage.write');
    expect(writes.map((w) => w.path)).toEqual(['saves/auto_1.json']);
    expect(rt.storage.get('settings.json')).toBe(settings);
    // O settings.json gravado ligou o modo stream.
    const state = await client.ok<JsonObject>('preview.get_state', { include: ['variables'] });
    expect((state.variables as JsonObject)['sys.content_filter']).toBe(true);
  });

  it('em memória, não manda storage.write', async () => {
    const { rt, client } = await loaded();
    await client.ok('preview.set_setting', { setting: 'text_speed', value: 80 });
    expect(client.notifications('storage.write')).toHaveLength(0);
    expect(rt.storage.has('settings.json')).toBe(true);
  });
});

describe('notificações gravadas', () => {
  it('repete a gravação com seq da sessão', async () => {
    const { client, rt } = await loaded();
    rt.replay(recording as { method: string; params: JsonObject }[]);
    await client.flush();
    expect(client.trace()).toEqual(recording.map((r) => r.method));
    expect(client.notifications().map((n) => n.seq)).toEqual([1, 2, 3, 4, 5, 6, 7]);
  });

  it('recusa uma notificação que não valida', async () => {
    const { rt } = await loaded();
    expect(() => rt.notify('scene.started', { scene: 'não-é-uuid' })).toThrow(/mensagem inválida/);
    // A mensagem não saiu e não gastou seq.
    rt.notify('log', { level: 'info', message: 'ok' });
    expect(rt.sent.at(-1)).toMatchObject({ method: 'log', params: { seq: 1 } });
  });
});

describe('ponte do painel (§1.1)', () => {
  it('liga vnPreview.send ao dublê e entrega por vnPreview.onmessage', async () => {
    const target: { vnPreview?: VnPreviewBridge } = {};
    const received: string[] = [];
    const { bridge, runtime } = installFakeBridge(target, { validator: schema, helloTimeoutMs: null });
    runtimes.push(runtime);
    bridge.onmessage = (text) => received.push(text);
    target.vnPreview?.send(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'session.hello', params: { protocol: '1.0' } }));
    await Promise.resolve();
    expect(JSON.parse(received[0] as string)).toMatchObject({ id: 1, result: { platform: 'web' } });
  });
});
