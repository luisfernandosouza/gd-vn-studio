/** Código GDScript e cenas dos plugins: P011, P012, W009 e W016 (Plugin SDK §12.2). */
import { readText, rel, rglobFiles } from './files.js';
import { get, has, keys, pyStr, splitlines, suffix, type Dict } from './py.js';

// Plugin SDK §12.2 (tabela de W009)
const BANNED_API = new RegExp(
  '\\b(OS\\.(execute|create_process|create_instance|shell_open|kill|get_environment|set_environment|get_user_data_dir)|HTTPRequest|HTTPClient|StreamPeerTCP|TCPServer|PacketPeerUDP|UDPServer|WebSocketPeer' +
    '|Engine\\.get_singleton|ProjectSettings\\.set_setting|JavaScriptBridge|JavaScriptObject|ResourceSaver\\.save|PROCESS_MODE_ALWAYS)\\b' +
    '|process_mode\\s*=\\s*3\\b',
);
// arquivos: só res:// (user:// também é vetado: os dados do plugin vão pelo VNStorage, Runtime Spec §8.5)
const ABS_FS = /\b(FileAccess|DirAccess)\.\w+\(\s*"(?!res:\/\/)|\.(save|save_png|save_jpg|save_webp|save_exr)\(\s*"(?!res:\/\/)/;
const I18N_KEY = /\.text\(\s*"(runtime\/[^"]+)"/g;
const RES_PATH = /res:\/\/[^"' )]+/g;
const GROUP = /(?:add_to_group|InputMap\.add_action)\(\s*&?"([^"]+)"/g;

type Report = (code: string, where: string, msg: string) => void;

function capitalize(w: string): string {
  return w ? w[0]!.toUpperCase() + w.slice(1).toLowerCase() : w;
}

export function checkPluginCode(pid: string, m: Dict, root: string, err: Report, warn: Report): void {
  const ns = pyStr(get(m, 'namespace', ''));
  const pascal = ns.split('_').map(capitalize).join('');
  const allowed = [`res://vn_plugins/${ns}/`, 'res://addons/vn_runtime_sdk/'];
  // aproximação: nome do plugin ≈ namespace
  for (const d of keys(get(m, 'dependencies', {}))) allowed.push(`res://vn_plugins/${d.includes('.') ? d.slice(d.indexOf('.') + 1) : d}/`);
  const locales = get(m, 'plugin_locales', {});
  const baseTexts = get(locales, String(get(m, 'default_locale', '')), {});
  const files = rglobFiles(root, (n) => ['.gd', '.tscn', '.tres'].includes(suffix(n)));
  for (const f of files) {
    const sfx = suffix(f);
    const relPath = `${pid}/${rel(root, f)}`;
    const lines = splitlines(readText(f));
    lines.forEach((line, k) => {
      const where = `${relPath}:${k + 1}`;
      for (const p of line.match(RES_PATH) ?? []) {
        if (!allowed.some((a) => p.startsWith(a))) err('P012', where, `caminho ${p} fora de res://vn_plugins/${ns}/`);
      }
      if (sfx !== '.gd' && /^\s*process_mode\s*=\s*3\b/.test(line)) {
        warn('W009', where, 'nó com process_mode ALWAYS continua rodando com o jogo pausado');
      }
      if (sfx !== '.gd' || line.trimStart().startsWith('#')) return;
      const cm = /^\s*class_name\s+([\p{L}\p{N}_]+)/u.exec(line);
      if (cm && !cm[1]!.startsWith(pascal)) err('P011', where, `class_name ${cm[1]} sem o prefixo ${pascal}`);
      for (const g of line.matchAll(GROUP)) {
        if (!g[1]!.startsWith(ns + '_')) err('P011', where, `grupo/ação ${g[1]} sem o prefixo ${ns}_`);
      }
      if (BANNED_API.test(line) || ABS_FS.test(line)) warn('W009', where, 'API do Godot vetada em plugins');
      for (const km of line.matchAll(I18N_KEY)) {
        if (!has(baseTexts, km[1]!)) warn('W016', where, `${km[1]} sem texto em plugin_locales[${pyStr(get(m, 'default_locale'))}]`);
      }
    });
  }
}
