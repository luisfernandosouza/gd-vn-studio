/**
 * Contraste de cores (WCAG 2.x), para o aviso do Req §12: "o Menu Editor avisa quando a cor do texto
 * sobre o painel tem contraste abaixo de 4,5:1".
 */
import type { Theme } from '@vnstudio/plugin-schema';
import classicTheme from '../../../docs/specs/presets/classic/theme.json';

export const MIN_CONTRAST = 4.5;

export interface Rgba {
  r: number;
  g: number;
  b: number;
  /** 0 a 1 */
  a: number;
}

/** Lê `#rrggbb` ou `#rrggbbaa` (o `Color` do theme.schema.json); outra coisa dá `null`. */
export function parseColor(value: string | undefined): Rgba | null {
  if (!value || !/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value)) return null;
  const n = (i: number) => parseInt(value.slice(i, i + 2), 16);
  return { r: n(1), g: n(3), b: n(5), a: value.length === 9 ? n(7) / 255 : 1 };
}

/** Cor `top` desenhada sobre `bottom` (opaca). */
export function compose(top: Rgba, bottom: Rgba): Rgba {
  const mix = (t: number, b: number) => t * top.a + b * (1 - top.a);
  return { r: mix(top.r, bottom.r), g: mix(top.g, bottom.g), b: mix(top.b, bottom.b), a: 1 };
}

export function luminance({ r, g, b }: Rgba): number {
  const lin = (c: number) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

export function contrastRatio(a: Rgba, b: Rgba): number {
  const la = luminance(a);
  const lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

const BLACK: Rgba = { r: 0, g: 0, b: 0, a: 1 };
const WHITE: Rgba = { r: 255, g: 255, b: 255, a: 1 };

export interface DialogContrast {
  text: string;
  panel: string;
  /** Menor razão entre as duas imagens de fundo extremas (preto e branco) por trás do painel. */
  ratio: number;
  ok: boolean;
}

/**
 * Contraste de `theme.colors.text` sobre `theme.colors.panel`. O painel costuma ser translúcido
 * (`#101826d9` no preset), então o que há atrás dele é a cena; a conta usa o pior dos dois extremos
 * (cena toda preta ou toda branca), para não depender da imagem de fundo. Cores ausentes vêm do preset.
 * Devolve `null` se alguma das cores não puder ser lida.
 */
export function dialogContrast(theme: Theme | null | undefined): DialogContrast | null {
  const preset = (classicTheme as { colors: { text: string; panel: string } }).colors;
  const text = theme?.colors?.text ?? preset.text;
  const panel = theme?.colors?.panel ?? preset.panel;
  const fg = parseColor(text);
  const bg = parseColor(panel);
  if (!fg || !bg) return null;
  const ratio = Math.min(...[BLACK, WHITE].map((back) => {
    const panelOnBack = compose(bg, back);
    return contrastRatio(compose(fg, panelOnBack), panelOnBack);
  }));
  return { text, panel, ratio, ok: ratio >= MIN_CONTRAST };
}
