/** SemVer mínimo, com faixas no estilo node-semver (`^`, `~`, comparadores, `||`), igual ao de `validate.py`. */

type Ver = [number, number, number, string | null];
type Key = [number, number, number, number, string];

export function parseVer(v: string): Ver | null {
  const t = v.trim().replace(/^[v=]+/, '');
  const m = /^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?/.exec(t);
  if (!m) return null;
  return [Number(m[1]), Number(m[2] ?? 0), Number(m[3] ?? 0), m[4] ?? null];
}

function key(v: Ver): Key {
  return [v[0], v[1], v[2], v[3] ? 0 : 1, v[3] ?? ''];
}

function cmp(a: Key, b: Key): number {
  for (let i = 0; i < 5; i++) {
    const x = a[i]!;
    const y = b[i]!;
    if (x < y) return -1;
    if (x > y) return 1;
  }
  return 0;
}

export function satisfies(version: string, range: string): boolean {
  const v = parseVer(version);
  if (v === null) return false;
  for (const alt of range.split('||')) {
    let ok = true;
    for (const comp of alt.split(/\s+/).filter(Boolean)) {
      const m = /^(\^|~|>=|<=|>|<|=)?(.+)$/.exec(comp)!;
      const op = m[1] ?? '=';
      const b = parseVer(m[2]!);
      if (b === null) {
        ok = false;
        break;
      }
      const kv = key(v);
      const kb = key(b);
      if (op === '^') {
        const hi: Key = b[0] ? [b[0] + 1, 0, 0, 0, ''] : b[1] ? [0, b[1] + 1, 0, 0, ''] : [0, 0, b[2] + 1, 0, ''];
        ok = cmp(kb, kv) <= 0 && cmp(kv, hi) < 0;
      } else if (op === '~') {
        ok = cmp(kb, kv) <= 0 && cmp(kv, [b[0], b[1] + 1, 0, 0, '']) < 0;
      } else {
        const c = cmp(kv, kb);
        ok = { '=': c === 0, '>=': c >= 0, '<=': c <= 0, '>': c > 0, '<': c < 0 }[op]!;
      }
      if (!ok) break;
    }
    if (ok) return true;
  }
  return false;
}
