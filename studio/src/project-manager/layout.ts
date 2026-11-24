/** Estrutura de um projeto em disco (Data Model §2; spec 09 §3). */

/** Versão do Narrative Data Model que este Studio grava (`project.json → format_version`, Data Model §12). */
export const FORMAT_VERSION = '1.0.0';

export const SCHEMA_BASE = 'https://schemas.vnstudio.dev/specs-v1.0.0/';

export const schemaUrl = (name: string) => `${SCHEMA_BASE}${name}.schema.json`;

/** Arquivos da raiz, um por assunto. */
export const ROOT_FILES = {
  project: 'project.json',
  variables: 'variables.json',
  assets: 'assets.json',
  plugins: 'plugins.json',
  pluginLock: 'plugin-lock.json',
  theme: 'theme.json',
  gitignore: '.gitignore',
} as const;

/** Pastas de entidades: um arquivo por entidade (Data Model §1, princípio 2). */
export const ENTITY_DIRS = {
  characters: 'characters',
  chapters: 'chapters',
  scenes: 'scenes',
  ui: 'ui',
  sets: 'sets',
  locales: 'locales',
} as const;

export type EntityKind = keyof typeof ENTITY_DIRS;

/** Pastas que um projeto novo já traz. `scenes/_global/` guarda cenas com `chapter: null`. */
export const STARTER_DIRS = ['characters', 'chapters', 'scenes', 'scenes/_global', 'ui', 'sets', 'locales', 'assets', '.vnstudio'] as const;

/** Pasta do editor, fora do Git (spec 09 §3.4). */
export const EDITOR_DIR = '.vnstudio';
export const BACKUPS_DIR = '.vnstudio/backups';

/** Faixa do Godot aceita por um projeto novo (Build System §2.1): o runtime do v1 usa o Godot 4.7. */
export const NEW_PROJECT_GODOT_RANGE = '>=4.7.0 <5.0.0';
export const NEW_PROJECT_RUNTIME_MIN = '1.0.0';

/** Idiomas do produto (Req §9.1), oferecidos como idioma-fonte de um projeto novo. */
export const PRODUCT_LOCALES = ['pt-BR', 'en', 'es', 'fr', 'it', 'de', 'ja', 'zh-Hans', 'zh-Hant'] as const;

export const LOCALE_PATTERN = /^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$/;

interface StarterTexts {
  chapter: string;
  scene: string;
  line: string;
}

const STARTER: Record<string, StarterTexts> = {
  'pt-BR': { chapter: 'Capítulo 1', scene: 'Início', line: 'Sua história começa aqui.' },
  en: { chapter: 'Chapter 1', scene: 'Beginning', line: 'Your story begins here.' },
  es: { chapter: 'Capítulo 1', scene: 'Inicio', line: 'Tu historia empieza aquí.' },
  fr: { chapter: 'Chapitre 1', scene: 'Début', line: 'Votre histoire commence ici.' },
  it: { chapter: 'Capitolo 1', scene: 'Inizio', line: 'La tua storia inizia qui.' },
  de: { chapter: 'Kapitel 1', scene: 'Anfang', line: 'Deine Geschichte beginnt hier.' },
  ja: { chapter: '第1章', scene: 'はじまり', line: '物語はここから始まります。' },
  'zh-Hans': { chapter: '第一章', scene: '开始', line: '你的故事从这里开始。' },
  'zh-Hant': { chapter: '第一章', scene: '開始', line: '你的故事從這裡開始。' },
};

/** Textos do capítulo e da cena iniciais no idioma-fonte (tag exata, depois a base, depois inglês). */
export function starterTexts(locale: string): StarterTexts {
  return STARTER[locale] ?? STARTER[locale.split('-')[0] ?? ''] ?? (STARTER.en as StarterTexts);
}
