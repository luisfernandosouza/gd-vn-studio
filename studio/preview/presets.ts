/**
 * Presets de interface que vêm no Studio (UI Spec §2.1): `docs/specs/presets/<nome>/`, lidos no build do
 * Studio (spec 09 §1.2), sem cópia à mão. O compilador do bundle os usa para aplicar o preset ao projeto.
 */
import type { JsonObject } from '../../cli/src/bundle/jcs';
import { codePointCompare } from '../../cli/src/bundle/compile';
import type { PresetInput } from '../../cli/src/bundle/input';

const files = import.meta.glob<JsonObject>('../../docs/specs/presets/*/{theme.json,ui/*.json,locales/*.json}', {
  eager: true,
  import: 'default',
});

const stem = (path: string): string => path.split('/').pop()!.replace(/\.json$/, '');

export function bundledPreset(name: string): PresetInput {
  const prefix = `../../docs/specs/presets/${name}/`;
  const mine = Object.entries(files).filter(([path]) => path.startsWith(prefix));
  const theme = mine.find(([path]) => path === `${prefix}theme.json`)?.[1];
  if (!theme) throw new Error(`preset ${name} não vem no Studio`);
  const group = (dir: string): [string, JsonObject][] =>
    mine
      .filter(([path]) => path.startsWith(`${prefix}${dir}/`))
      .map(([path, doc]): [string, JsonObject] => [stem(path), doc])
      // ordem de nome de arquivo, como o compilador de referência lê a pasta
      .sort(([a], [b]) => codePointCompare(`${a}.json`, `${b}.json`));
  return { name, theme, ui: group('ui'), locales: Object.fromEntries(group('locales')) };
}
