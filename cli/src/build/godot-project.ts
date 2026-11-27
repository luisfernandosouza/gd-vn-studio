/**
 * `project.godot` gerado (Build System §4.3). O Build System escreve o arquivo do zero a partir do
 * template do runtime e do `project.json`; plugins nunca o alteram (Plugin SDK §2.4). Do template
 * vêm só as seções que o spec fixa (`[input]` com as ações `vn_*` e `[rendering]`); o resto sai do projeto.
 * Puro (sem Node).
 */
import type { JsonObject } from '../bundle/jcs.js';

/** Godot que o runtime 1.0 fixa (Build System §2.1). */
export const PINNED_GODOT = '4.7.2';
/** Recurso Godot da cena principal (BS §4.3). */
export const MAIN_SCENE = 'res://vn_runtime/boot.tscn';

/** Texto de uma string do Godot (`"..."`, com `\` e `"` escapados e quebras de linha em `\n`). */
export function gdString(s: string): string {
  return `"${s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\r?\n/g, '\\n').replace(/\t/g, '\\t')}"`;
}

/** `#rrggbb` ou `#rrggbbaa` → `Color(r, g, b, a)` do Godot. */
export function gdColor(hex: string): string {
  const m = /^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$/.exec(hex);
  if (!m) throw new Error(`cor inválida: ${hex}`);
  const n = (i: number): string => String(Number((parseInt(m[1]!.slice(i, i + 2), 16) / 255).toFixed(4)));
  const a = m[2] ? String(Number((parseInt(m[2], 16) / 255).toFixed(4))) : '1';
  return `Color(${n(0)}, ${n(2)}, ${n(4)}, ${a})`;
}

/** Uma seção `[nome]` do `project.godot` do template, sem o cabeçalho, ou `undefined`. */
export function templateSection(template: string, name: string): string | undefined {
  const lines = template.replace(/\r\n?/g, '\n').split('\n');
  const start = lines.findIndex((l) => l.trim() === `[${name}]`);
  if (start < 0) return undefined;
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (/^\[[A-Za-z0-9_./-]+\]\s*$/.test(lines[i]!)) {
      end = i;
      break;
    }
  }
  return lines.slice(start + 1, end).join('\n').replace(/^\n+|\n+$/g, '');
}

export interface GodotProjectInput {
  /** `project.json`. */
  project: JsonObject;
  /** Título no `default_locale` (`project/title` do idioma; senão o `title` do projeto). */
  title: string;
  /** `project.godot` do template do runtime. */
  template: string;
  /** Caminho `res://` do ícone e da splash, já resolvidos pelo bundle (`assets` do bundle). */
  iconPath?: string;
  splashPath?: string;
  /** Cor de fundo do tema, usada quando não há splash. */
  backgroundColor?: string;
}

const obj = (v: unknown): JsonObject => (v !== null && typeof v === 'object' && !Array.isArray(v) ? (v as JsonObject) : {});

export function generateProjectGodot(i: GodotProjectInput): string {
  const settings = obj(i.project.settings);
  const res = Array.isArray(settings.resolution) ? settings.resolution : [1920, 1080];
  const width = Number(res[0]);
  const height = Number(res[1]);
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
    throw new Error(`settings.resolution inválida: ${JSON.stringify(res)}`);
  }
  const input = templateSection(i.template, 'input');
  const rendering = templateSection(i.template, 'rendering');
  if (!input) throw new Error('o project.godot do template não tem a seção [input] (ações vn_*)');
  if (!rendering) throw new Error('o project.godot do template não tem a seção [rendering]');

  const app = [
    `config/name=${gdString(i.title)}`,
    `config/version=${gdString(String(i.project.version ?? ''))}`,
    `run/main_scene=${gdString(MAIN_SCENE)}`,
    `config/features=PackedStringArray("${PINNED_GODOT.split('.').slice(0, 2).join('.')}")`,
  ];
  if (i.iconPath) app.push(`config/icon=${gdString(i.iconPath)}`);
  if (i.splashPath) {
    app.push(`boot_splash/image=${gdString(i.splashPath)}`);
  } else {
    // Sem splash: só a cor de fundo do tema, sem a logo do Godot (BS §4.3).
    app.push('boot_splash/show_image=false');
    app.push(`boot_splash/bg_color=${gdColor(i.backgroundColor ?? '#000000')}`);
  }

  const parts = [
    '; Gerado pelo Build System (Build System §4.3). Não edite: o build escreve este arquivo de novo.',
    '',
    'config_version=5',
    '',
    '[application]',
    '',
    ...app,
    '',
    '[display]',
    '',
    `window/size/viewport_width=${width}`,
    `window/size/viewport_height=${height}`,
    'window/stretch/mode="canvas_items"',
    'window/stretch/aspect="expand"',
    '',
    '[input]',
    '',
    input,
    '',
    '[internationalization]',
    '',
    // O runtime traduz pelo bundle, não pelo sistema de traduções do Godot.
    'locale/translations=PackedStringArray()',
    '',
    '[rendering]',
    '',
    rendering,
    'textures/canvas_textures/default_texture_filter=1',
    '',
  ];
  return parts.join('\n');
}
