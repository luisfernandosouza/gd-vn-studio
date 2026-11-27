import { describe, expect, it } from 'vitest';
import { contrastRatio, dialogContrast, parseColor } from './contrast';

describe('contraste', () => {
  it('lê #rrggbb e #rrggbbaa', () => {
    expect(parseColor('#ffffff')).toEqual({ r: 255, g: 255, b: 255, a: 1 });
    expect(parseColor('#00000080')?.a).toBeCloseTo(0.5, 2);
    expect(parseColor('branco')).toBeNull();
    expect(parseColor('#fff')).toBeNull();
  });

  it('preto sobre branco dá 21:1', () => {
    expect(contrastRatio({ r: 0, g: 0, b: 0, a: 1 }, { r: 255, g: 255, b: 255, a: 1 })).toBeCloseTo(21, 5);
  });

  it('o tema do preset passa (texto branco sobre painel azul-escuro translúcido)', () => {
    const c = dialogContrast(null);
    expect(c?.ok).toBe(true);
    expect(c!.ratio).toBeGreaterThan(4.5);
  });

  it('avisa texto cinza claro sobre painel claro', () => {
    const c = dialogContrast({ colors: { text: '#cccccc', panel: '#ffffff' } });
    expect(c?.ok).toBe(false);
    expect(c!.ratio).toBeLessThan(4.5);
  });

  it('painel translúcido usa o pior fundo: texto branco sobre painel quase transparente falha', () => {
    expect(dialogContrast({ colors: { text: '#ffffff', panel: '#10182620' } })?.ok).toBe(false);
  });

  it('cor ilegível não calcula', () => {
    expect(dialogContrast({ colors: { text: 'red' } } as never)).toBeNull();
  });
});
