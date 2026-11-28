import { act, cleanup, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { App } from '../App';
import { MemoryFs } from '../project-manager/memory-fs';
import { useProjectSession } from '../project-manager/session';
import { useI18n } from './index';
import { CATALOGS, SOURCE_LOCALE, UI_LOCALES, detectLocale, interpolate, translate } from './translate';

const KEY_PATTERN = /^[a-z0-9][a-z0-9_-]*(\/[A-Za-z0-9_.-]+)+$/;
const placeholders = (s: string) => [...s.matchAll(/\{([A-Za-z_]\w*)\}/g)].map((m) => m[1]).sort();
const text = (v: string | { text: string }) => (typeof v === 'string' ? v : v.text);

describe('catálogos de idioma do Studio', () => {
  const source = CATALOGS[SOURCE_LOCALE].strings;

  it('são os 9 idiomas do produto (Req §9.1)', () => {
    expect(UI_LOCALES.map((l) => l.code).sort()).toEqual(['de', 'en', 'es', 'fr', 'it', 'ja', 'pt-BR', 'zh-Hans', 'zh-Hant']);
    for (const { code } of UI_LOCALES) expect(CATALOGS[code].locale).toBe(code);
  });

  it('usam chaves válidas e as mesmas chaves e campos do inglês', () => {
    for (const key of Object.keys(source)) expect(key).toMatch(KEY_PATTERN);
    for (const { code } of UI_LOCALES) {
      const strings = CATALOGS[code].strings;
      expect(Object.keys(strings).sort(), code).toEqual(Object.keys(source).sort());
      for (const [key, value] of Object.entries(strings)) {
        expect(text(value).trim(), `${code} ${key}`).not.toBe('');
        expect(placeholders(text(value)), `${code} ${key}`).toEqual(placeholders(text(source[key]!)));
      }
    }
  });
});

describe('tradução', () => {
  it('traduz e interpola', () => {
    expect(translate('pt-BR', 'studio/project/chapters', { count: 3 })).toBe('Capítulos: 3');
    expect(interpolate('{{x}} {n}', { n: 2 })).toBe('{x} 2');
  });

  it('chave sem tradução cai no inglês, e sem inglês devolve a chave', () => {
    const pt = CATALOGS['pt-BR'].strings;
    const saved = pt['studio/pm/create'];
    delete pt['studio/pm/create'];
    try {
      expect(translate('pt-BR', 'studio/pm/create')).toBe('Create project');
    } finally {
      pt['studio/pm/create'] = saved!;
    }
    expect(translate('de', 'studio/nao/existe')).toBe('studio/nao/existe');
  });

  it('abre no idioma do sistema se estiver na lista, senão em inglês', () => {
    expect(detectLocale(['ja-JP'])).toBe('ja');
    expect(detectLocale(['pt-PT'])).toBe('pt-BR');
    expect(detectLocale(['zh-TW'])).toBe('zh-Hant');
    expect(detectLocale(['zh-CN'])).toBe('zh-Hans');
    expect(detectLocale(['fr-CA', 'en'])).toBe('fr');
    expect(detectLocale(['ko-KR', 'es-MX'])).toBe('es');
    expect(detectLocale(['ko-KR'])).toBe('en');
    expect(detectLocale([])).toBe('en');
  });
});

describe('troca de idioma na interface', () => {
  afterEach(cleanup);
  beforeEach(() => {
    useProjectSession.setState({ current: null });
    useI18n.setState({ locale: 'en' });
  });

  it('trocar o idioma muda os textos da tela e o atributo lang', () => {
    render(<App io={{ fs: new MemoryFs(), pickFolder: async () => null }} />);
    expect(screen.getByRole('heading', { name: 'Projects' })).toBeInTheDocument();
    act(() => useI18n.getState().setLocale('ja'));
    expect(screen.getByRole('heading', { name: 'プロジェクト' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'プロジェクトを開く…' })).toBeInTheDocument();
    expect(document.documentElement.lang).toBe('ja');
    expect(localStorage.getItem('vnstudio.uiLocale')).toBe('ja');
  });
});
