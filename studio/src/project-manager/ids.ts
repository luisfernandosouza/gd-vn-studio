/** IDs do Data Model §3: UUIDv7 para entidades e `Id` legível gerado do nome (Req §2). */

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** UUIDv7 em minúsculas (RFC 9562): 48 bits de milissegundos, versão 7, variante 10. */
export function uuidv7(now: number = Date.now(), random: Uint8Array = crypto.getRandomValues(new Uint8Array(10))): string {
  const b = new Uint8Array(16);
  let ms = Math.floor(now);
  for (let i = 5; i >= 0; i--) {
    b[i] = ms % 256;
    ms = Math.floor(ms / 256);
  }
  b.set(random.subarray(0, 10), 6);
  b[6] = 0x70 | ((b[6] ?? 0) & 0x0f);
  b[8] = 0x80 | ((b[8] ?? 0) & 0x3f);
  const h = hex(b);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

export const ID_PATTERN = /^[a-z][a-z0-9_]{0,63}$/;

/**
 * Nome legível a partir de um título (Req §2): sem acento, minúsculas, `_` no lugar de espaço e
 * pontuação. Começa com letra; se o título não tiver nenhuma, usa `fallback`.
 */
export function slugify(title: string, fallback = 'projeto'): string {
  let s = title
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  if (!s) return fallback;
  if (!/^[a-z]/.test(s)) s = `${fallback}_${s}`;
  return s.slice(0, 64).replace(/_+$/, '');
}

/** Acrescenta `_2`, `_3`… até o nome não estar em `taken` (Req §2: sufixo numérico se já existir). */
export function uniqueName(base: string, taken: Iterable<string>): string {
  const used = new Set(taken);
  if (!used.has(base)) return base;
  for (let n = 2; ; n++) {
    const suffix = `_${n}`;
    const candidate = base.slice(0, 64 - suffix.length) + suffix;
    if (!used.has(candidate)) return candidate;
  }
}
