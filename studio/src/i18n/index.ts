import { useCallback } from 'react';
import { create } from 'zustand';
import { detectLocale, isUiLocale, translate, type Params, type UiLocale } from './translate';

export { UI_LOCALES, detectLocale, translate, type Params, type UiLocale } from './translate';

const LOCALE_KEY = 'vnstudio.uiLocale';

function systemLocale(): UiLocale {
  if (typeof navigator === 'undefined') return 'en';
  return detectLocale(navigator.languages?.length ? navigator.languages : [navigator.language]);
}

/** Escolha do autor (guardada nesta máquina), senão o idioma do sistema, senão inglês. */
function initialLocale(): UiLocale {
  try {
    const stored = localStorage.getItem(LOCALE_KEY);
    if (isUiLocale(stored)) return stored;
  } catch {
    // sem armazenamento: vale o idioma do sistema
  }
  return systemLocale();
}

export interface I18nState {
  locale: UiLocale;
  setLocale: (locale: UiLocale) => void;
}

export const useI18n = create<I18nState>((set) => ({
  locale: initialLocale(),
  setLocale: (locale) => {
    try {
      localStorage.setItem(LOCALE_KEY, locale);
    } catch {
      // a escolha vale só nesta sessão
    }
    set({ locale });
  },
}));

/** Função de tradução do idioma atual; troca de idioma re-renderiza quem a usa. */
export function useT(): (key: string, params?: Params) => string {
  const locale = useI18n((s) => s.locale);
  return useCallback((key, params) => translate(locale, key, params), [locale]);
}

/** Tradução fora de componentes React (ex.: mensagens de erro já criadas). */
export function t(key: string, params?: Params): string {
  return translate(useI18n.getState().locale, key, params);
}
