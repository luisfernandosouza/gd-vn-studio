/**
 * História padrão do dublê: o projeto de exemplo das specs (`docs/specs/examples/demo-project`), com as cenas
 * lidas dos próprios arquivos e as avaliações do Scheduler gravadas à mão, coerentes com as condições das cenas
 * num jogo novo.
 *
 * Caminho de um jogo novo: capítulo 1 → Chegada (entry) → Encontro no trem (priority) → Um dia tranquilo
 * (fallback) → sai do capítulo (completion) → capítulo 2 → O festival (entry) → final `festival_ending`.
 */
import chapter1 from '../../../docs/specs/examples/demo-project/chapters/ch01.json';
import chapter2 from '../../../docs/specs/examples/demo-project/chapters/ch02.json';
import alice from '../../../docs/specs/examples/demo-project/characters/alice.json';
import sceneArrival from '../../../docs/specs/examples/demo-project/scenes/ch01/scene_arrival.json';
import sceneBeach from '../../../docs/specs/examples/demo-project/scenes/ch01/scene_beach.json';
import sceneFishingMaster from '../../../docs/specs/examples/demo-project/scenes/ch01/scene_fishing_master.json';
import sceneQuietDay from '../../../docs/specs/examples/demo-project/scenes/ch01/scene_quiet_day.json';
import sceneFestival from '../../../docs/specs/examples/demo-project/scenes/ch02/scene_festival.json';
import type { DoubleStory, DoubleVariable, SceneEntity } from './types';

/** Ids da demo, para os testes e para quem monta cenários no Studio. */
export const DEMO = {
  chapter1: chapter1.id,
  chapter2: chapter2.id,
  alice: alice.id,
  scenes: {
    arrival: sceneArrival.id,
    beach: sceneBeach.id,
    fishingMaster: sceneFishingMaster.id,
    quietDay: sceneQuietDay.id,
    festival: sceneFestival.id,
  },
  nodes: {
    beachFirst: '019a7a00-2ee0-78cd-b7fb-730161b48bdb',
    beachGreeting: '019a7a00-3a98-732b-89dd-170487226b34',
    beachChoice: '019a7a00-4268-71d6-977e-cf1637d45f1b',
    beachFishing: '019a7a00-4a38-76e1-9cd6-55120fa376e8',
    quietInteract: '019a7a00-a0f0-7c1e-9d2a-5e7f3b1c4d61',
  },
  options: {
    fish: '019a7a00-4650-7571-a41a-c83fdebea0ae',
    talk: '019a7a00-4e20-7121-8b7a-3686b62d8686',
    icecream: '019a7a00-55f0-7d02-b43b-d18b41604bdf',
  },
  hotspots: {
    shell: '019a7a00-a0fc-7c1e-9d2a-5e7f3b1c4d64',
    lamp: '019a7a00-a100-7c1e-9d2a-5e7f3b1c4d65',
  },
  activity: 'fishing.fishing_game',
  plugin: 'vnstudio.fishing',
} as const;

const int = (def: number, min?: number, max?: number, onOverflow?: 'clamp' | 'reject'): DoubleVariable => ({
  type: 'integer',
  default: def,
  constraints: { ...(min !== undefined ? { min } : {}), ...(max !== undefined ? { max } : {}), ...(onOverflow ? { on_overflow: onOverflow } : {}) },
});

/** Configurações do jogador (UI Spec §8) com padrões plausíveis; `content_filter` vem de `project.content_filter.default`. */
const settings = {
  locale: 'pt-BR',
  text_speed: 40,
  auto_delay: 1.5,
  skip_unread: false,
  content_filter: false,
  subtitles: false,
  show_hotspots: false,
  high_contrast: false,
  reduce_motion: false,
  text_scale: 1,
  display_mode: 'windowed',
  vsync: true,
  fps_limit_vn: 60,
  fps_limit_activity: 0,
  'volume.master': 1,
  'volume.music': 0.8,
  'volume.sfx': 0.8,
  'volume.ambient': 0.8,
  'volume.voice': 1,
};

export function demoStory(): DoubleStory {
  return {
    project_id: 'seaside_story',
    content_hash: 'sha256-00d0b1e0000000000000000000000000000000000000000000000000000000d0',
    format_version: '1.0.0',
    start_chapter: chapter1.id,
    default_locale: 'pt-BR',
    locales: ['pt-BR', 'en'],
    characters: [{ id: alice.id, key: alice.key, name: alice.name }],
    variables: {
      'global.player_money': int(0, 0, 99999, 'reject'),
      'global.fishing_won': { type: 'boolean', default: false },
      'global.fishing_skill': int(0, 0, 100),
      'global.is_rich': {
        type: 'boolean',
        derived: { if: [{ variable: 'global.player_money', operator: 'greater_than_or_equal', value: 1000 }], then: true, else: false },
      },
      'global.endings_seen': int(0),
      'character.alice.affection': { ...int(alice.initial_values.affection, -100, 100) },
      'character.alice.met': { type: 'boolean', default: false },
    },
    chapters: [
      {
        id: chapter1.id,
        title: chapter1.title,
        entry_scene: chapter1.entry_scene,
        variables: { days_passed: int(0) },
        next: chapter2.id,
        selections: [
          {
            action: 'start_scene',
            chosen: sceneBeach.id,
            reason: 'priority',
            candidates: [
              { scene: sceneBeach.id, eligible: true },
              {
                scene: sceneFishingMaster.id,
                eligible: false,
                blocked_by: 'conditions',
                failed: [
                  { path: 'conditions[0]', variable: 'global.fishing_won', operator: 'equals', expected: true, actual: false },
                  { path: 'conditions[1]', variable: 'global.fishing_skill', operator: 'greater_than_or_equal', expected: 10, actual: 0 },
                ],
              },
              { scene: sceneQuietDay.id, eligible: false, blocked_by: 'mode_manual' },
            ],
          },
          {
            action: 'start_scene',
            chosen: sceneQuietDay.id,
            reason: 'fallback',
            candidates: [
              { scene: sceneBeach.id, eligible: false, blocked_by: 'max_plays', detail: { plays: 1, max_plays: 1 } },
              {
                scene: sceneFishingMaster.id,
                eligible: false,
                blocked_by: 'conditions',
                failed: [{ path: 'conditions[0]', variable: 'global.fishing_won', operator: 'equals', expected: true, actual: false }],
              },
              { scene: sceneQuietDay.id, eligible: false, blocked_by: 'mode_manual' },
            ],
          },
          { action: 'exit_chapter', chosen: null, reason: 'completion', candidates: [] },
        ],
      },
      { id: chapter2.id, title: chapter2.title, entry_scene: chapter2.entry_scene, next: null },
    ],
    scenes: [sceneArrival, sceneBeach, sceneFishingMaster, sceneQuietDay, sceneFestival] as unknown as SceneEntity[],
    plugins: {
      'vnstudio.fishing': {
        namespace: 'fishing',
        activities: {
          fishing_game: {
            outcomes: ['won', 'lost'],
            skippable: true,
            default_outcome: 'lost',
            free_play: { params: { difficulty: 'normal', duration_seconds: 90, target_fish: 5 } },
          },
        },
      },
    },
    screens: ['title', 'settings', 'extras', 'credits', 'save', 'load', 'pause', 'backlog', 'gallery', 'hud', 'minigames'],
    endings: ['festival_ending'],
    settings,
    autosave: 'selection_point',
    reproducible_rng: true,
  };
}
