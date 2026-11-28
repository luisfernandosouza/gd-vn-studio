/** Textos do produto (Req §9.1): arquivos no formato de `locales/` (Data Model §9), inglês como fonte. */
import de from './locales/de.json';
import en from './locales/en.json';
import es from './locales/es.json';
import fr from './locales/fr.json';
import it from './locales/it.json';
import ja from './locales/ja.json';
import ptBR from './locales/pt-BR.json';
import zhHans from './locales/zh-Hans.json';
import zhHant from './locales/zh-Hant.json';

type StringValue = string | { text: string };
export interface LocaleFile {
  locale: string;
  strings: Record<string, StringValue>;
}

/** Idiomas da interface no v1, com o nome de cada um na própria língua. O inglês vem primeiro: é a fonte. */
export const UI_LOCALES = [
  { code: 'en', name: 'English' },
  { code: 'pt-BR', name: 'Português (Brasil)' },
  { code: 'es', name: 'Español' },
  { code: 'fr', name: 'Français' },
  { code: 'it', name: 'Italiano' },
  { code: 'de', name: 'Deutsch' },
  { code: 'ja', name: '日本語' },
  { code: 'zh-Hans', name: '简体中文' },
  { code: 'zh-Hant', name: '繁體中文' },
] as const;

export type UiLocale = (typeof UI_LOCALES)[number]['code'];
export const SOURCE_LOCALE: UiLocale = 'en';

export const CATALOGS: Record<UiLocale, LocaleFile> = {
  en,
  'pt-BR': ptBR,
  es,
  fr,
  it,
  de,
  ja,
  'zh-Hans': zhHans,
  'zh-Hant': zhHant,
};

export type Params = Record<string, string | number>;

export function isUiLocale(value: unknown): value is UiLocale {
  return typeof value === 'string' && UI_LOCALES.some((l) => l.code === value);
}

/** Idioma do sistema, se estiver na lista; senão inglês (Req §9.1). Aceita a lista de `navigator.languages`. */
export function detectLocale(languages: readonly string[]): UiLocale {
  for (const lang of languages) {
    if (isUiLocale(lang)) return lang;
    if (/^zh/i.test(lang)) return /TW|HK|MO|Hant/i.test(lang) ? 'zh-Hant' : 'zh-Hans';
    if (/^pt/i.test(lang)) return 'pt-BR';
    const base = lang.split('-')[0]?.toLowerCase();
    if (isUiLocale(base)) return base;
  }
  return SOURCE_LOCALE;
}

function lookup(file: LocaleFile | undefined, key: string): string | undefined {
  const value = file?.strings[key];
  return typeof value === 'string' ? value : value?.text;
}

/** `{nome}` vira o parâmetro; `{{` e `}}` são chaves literais (Data Model §9). Parâmetro ausente fica como está. */
export function interpolate(text: string, params?: Params): string {
  return text.replace(/\{\{|\}\}|\{([A-Za-z_][A-Za-z0-9_]*)\}/g, (m, name?: string) => {
    if (m === '{{') return '{';
    if (m === '}}') return '}';
    return name !== undefined && params && name in params ? String(params[name]) : m;
  });
}

/** Traduz `key` para `locale`; chave sem tradução cai no inglês, e sem inglês devolve a própria chave. */
export function translate(locale: UiLocale, key: string, params?: Params): string {
  const text = lookup(CATALOGS[locale], key) ?? lookup(CATALOGS[SOURCE_LOCALE], key) ?? key;
  return interpolate(text, params);
}
