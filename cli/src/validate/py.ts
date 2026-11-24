/**
 * Utilitários que reproduzem a semântica do Python usada por `docs/specs/tools/validate.py`.
 *
 * O validador em TypeScript DEVE dar o mesmo resultado que o de referência (Req §14). Para isso ele
 * precisa enxergar os dados como o Python enxerga: `2.0` é float e `2` é int (T007, U005, W017),
 * `[]`, `{}`, `""` e `0` são falsos, `True == 1`, e as mensagens usam `repr()` do Python.
 */

/** Número JSON escrito com ponto ou expoente e de valor inteiro (`2.0`, `1e3`): no Python é float. */
export class PyFloat {
  constructor(readonly value: number) {}
  valueOf(): number {
    return this.value;
  }
  toJSON(): number {
    return this.value;
  }
}

// O validador é um porte de código dinâmico: os dados vêm de JSON e são conferidos por schema e por regra.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type J = any;
export type Dict = Record<string, J>;

export function isDict(x: unknown): x is Dict {
  return typeof x === 'object' && x !== null && !Array.isArray(x) && !(x instanceof PyFloat);
}
export const isList = Array.isArray;
export function isStr(x: unknown): x is string {
  return typeof x === 'string';
}
export function isBool(x: unknown): x is boolean {
  return typeof x === 'boolean';
}
/** `isinstance(x, int) and not isinstance(x, bool)` */
export function isInt(x: unknown): x is number {
  return typeof x === 'number' && Number.isInteger(x);
}
/** `isinstance(x, float)` */
export function isFloat(x: unknown): boolean {
  return x instanceof PyFloat || (typeof x === 'number' && !Number.isInteger(x));
}
/** `isinstance(x, (int, float)) and not isinstance(x, bool)` */
export function isNum(x: unknown): boolean {
  return typeof x === 'number' || x instanceof PyFloat;
}
export function num(x: unknown): number {
  return x instanceof PyFloat ? x.value : Number(x);
}

/** `key in d` para um dict. */
export function has(d: unknown, k: string): boolean {
  return isDict(d) && Object.prototype.hasOwnProperty.call(d, k);
}
/** `d.get(k, dflt)`; para não-dict devolve `dflt`. */
export function get(d: unknown, k: string, dflt: J = null): J {
  return has(d, k) ? (d as Dict)[k] : dflt;
}
export function keys(d: unknown): string[] {
  return isDict(d) ? Object.keys(d) : [];
}
export function values(d: unknown): J[] {
  return isDict(d) ? Object.values(d) : [];
}
export function items(d: unknown): [string, J][] {
  return isDict(d) ? Object.entries(d) : [];
}
/** `x or []` para listas que podem faltar. */
export function list(x: unknown): J[] {
  return Array.isArray(x) ? x : [];
}

/** Verdade no Python. */
export function truthy(x: unknown): boolean {
  if (x === null || x === undefined || x === false) return false;
  if (typeof x === 'number') return x !== 0;
  if (x instanceof PyFloat) return x.value !== 0;
  if (typeof x === 'string') return x.length > 0;
  if (Array.isArray(x)) return x.length > 0;
  if (x instanceof Set || x instanceof Map) return x.size > 0;
  if (typeof x === 'object') return Object.keys(x).length > 0;
  return true;
}

/** `a == b` do Python para valores vindos de JSON. */
export function pyEq(a: unknown, b: unknown): boolean {
  const an = typeof a === 'boolean' ? Number(a) : isNum(a) ? num(a) : a;
  const bn = typeof b === 'boolean' ? Number(b) : isNum(b) ? num(b) : b;
  if (typeof an === 'number' && typeof bn === 'number') return an === bn;
  if (Array.isArray(an) && Array.isArray(bn)) return an.length === bn.length && an.every((v, i) => pyEq(v, bn[i]));
  if (isDict(an) && isDict(bn)) {
    const ka = Object.keys(an);
    return ka.length === Object.keys(bn).length && ka.every((k) => has(bn, k) && pyEq(an[k], bn[k]));
  }
  return an === bn;
}

/** `x in coleção` (lista, Set, ou chaves de um dict). */
export function pyIn(x: unknown, coll: unknown): boolean {
  if (coll instanceof Set) {
    if (coll.has(x)) return true;
    return typeof x !== 'string' && [...coll].some((v) => pyEq(v, x));
  }
  if (Array.isArray(coll)) return coll.some((v) => pyEq(v, x));
  if (isDict(coll)) return typeof x === 'string' && has(coll, x);
  if (typeof coll === 'string') return typeof x === 'string' && coll.includes(x);
  return false;
}

/** Ordem de `sorted()` em str do Python: por ponto de código, não por unidade UTF-16. */
export function cmpStr(a: string, b: string): number {
  if (a === b) return 0;
  const ca = [...a];
  const cb = [...b];
  for (let i = 0; i < Math.min(ca.length, cb.length); i++) {
    const x = ca[i]!.codePointAt(0)!;
    const y = cb[i]!.codePointAt(0)!;
    if (x !== y) return x - y;
  }
  return ca.length - cb.length;
}
export function sorted(xs: Iterable<string>): string[] {
  return [...xs].sort(cmpStr);
}

// ---------- repr() e str() ----------

function strRepr(s: string): string {
  const quote = s.includes("'") && !s.includes('"') ? '"' : "'";
  let out = quote;
  for (const ch of s) {
    const cp = ch.codePointAt(0)!;
    if (ch === '\\') out += '\\\\';
    else if (ch === quote) out += '\\' + quote;
    else if (ch === '\n') out += '\\n';
    else if (ch === '\r') out += '\\r';
    else if (ch === '\t') out += '\\t';
    else if (ch !== ' ' && /[\p{C}\p{Z}]/u.test(ch)) {
      if (cp <= 0xff) out += '\\x' + cp.toString(16).padStart(2, '0');
      else if (cp <= 0xffff) out += '\\u' + cp.toString(16).padStart(4, '0');
      else out += '\\U' + cp.toString(16).padStart(8, '0');
    } else out += ch;
  }
  return out + quote;
}

/** `repr(float)` do Python: dígitos mínimos, notação científica fora de 1e-4 <= |x| < 1e16. */
export function floatRepr(v: number): string {
  if (Number.isNaN(v)) return 'nan';
  if (!Number.isFinite(v)) return v > 0 ? 'inf' : '-inf';
  if (v === 0) return Object.is(v, -0) ? '-0.0' : '0.0';
  const sign = v < 0 ? '-' : '';
  const [mant, expS] = Math.abs(v).toExponential().split('e') as [string, string];
  const digits = mant.replace('.', '');
  const e = Number(expS);
  if (e < -4 || e >= 16) {
    const m = digits.length > 1 ? `${digits[0]}.${digits.slice(1)}` : digits;
    return `${sign}${m}e${e < 0 ? '-' : '+'}${String(Math.abs(e)).padStart(2, '0')}`;
  }
  if (e >= 0) {
    const intPart = digits.length > e + 1 ? digits.slice(0, e + 1) : digits.padEnd(e + 1, '0');
    const frac = digits.length > e + 1 ? digits.slice(e + 1) : '0';
    return `${sign}${intPart}.${frac}`;
  }
  return `${sign}0.${'0'.repeat(-e - 1)}${digits}`;
}

export function pyRepr(x: unknown): string {
  if (x === null || x === undefined) return 'None';
  if (x === true) return 'True';
  if (x === false) return 'False';
  if (x instanceof PyFloat) return floatRepr(x.value);
  if (typeof x === 'number') return Number.isInteger(x) ? String(BigInt(x)) : floatRepr(x);
  if (typeof x === 'string') return strRepr(x);
  if (Array.isArray(x)) return '[' + x.map(pyRepr).join(', ') + ']';
  if (x instanceof Set) return x.size ? '{' + [...x].map(pyRepr).join(', ') + '}' : 'set()';
  if (isDict(x)) return '{' + Object.entries(x).map(([k, v]) => `${strRepr(k)}: ${pyRepr(v)}`).join(', ') + '}';
  return String(x);
}

/** `str(x)`, como num f-string sem `!r`. */
export function pyStr(x: unknown): string {
  return typeof x === 'string' ? x : pyRepr(x);
}

// ---------- JSON com a distinção int/float ----------

export class JsonError extends Error {}

/** `json.loads`: como `JSON.parse`, mas números inteiros escritos como float viram {@link PyFloat}. */
export function parseJson(text: string): J {
  let i = 0;
  const ws = () => {
    while (i < text.length && ' \t\n\r'.includes(text[i]!)) i++;
  };
  const fail = (what: string): never => {
    const before = text.slice(0, i);
    const line = before.split('\n').length;
    const col = i - before.lastIndexOf('\n');
    throw new JsonError(`${what} (linha ${line}, coluna ${col})`);
  };
  const NUM = /-?(?:0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/y;
  const STR = /"(?:[^"\\\u0000-\u001f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"/y;
  const value = (): J => {
    ws();
    const c = text[i];
    if (c === '{') {
      i++;
      const obj: Dict = {};
      ws();
      if (text[i] === '}') {
        i++;
        return obj;
      }
      for (;;) {
        ws();
        if (text[i] !== '"') fail('esperava o nome de um campo');
        const k = str();
        ws();
        if (text[i] !== ':') fail('esperava ":"');
        i++;
        Object.defineProperty(obj, k, { value: value(), enumerable: true, writable: true, configurable: true });
        ws();
        if (text[i] === ',') {
          i++;
          continue;
        }
        if (text[i] === '}') {
          i++;
          return obj;
        }
        fail('esperava "," ou "}"');
      }
    }
    if (c === '[') {
      i++;
      const arr: J[] = [];
      ws();
      if (text[i] === ']') {
        i++;
        return arr;
      }
      for (;;) {
        arr.push(value());
        ws();
        if (text[i] === ',') {
          i++;
          continue;
        }
        if (text[i] === ']') {
          i++;
          return arr;
        }
        fail('esperava "," ou "]"');
      }
    }
    if (c === '"') return str();
    if (text.startsWith('true', i)) return (i += 4), true;
    if (text.startsWith('false', i)) return (i += 5), false;
    if (text.startsWith('null', i)) return (i += 4), null;
    NUM.lastIndex = i;
    const m = NUM.exec(text);
    if (!m) return fail('valor JSON inválido');
    i += m[0].length;
    const v = Number(m[0]);
    return (m[1] || m[2]) && Number.isInteger(v) ? new PyFloat(v) : v;
  };
  const str = (): string => {
    STR.lastIndex = i;
    const m = STR.exec(text);
    if (!m) return fail('texto JSON inválido');
    i += m[0].length;
    return JSON.parse(m[0]) as string;
  };
  if (text.charCodeAt(0) === 0xfeff) fail('o arquivo começa com BOM');
  const v = value();
  ws();
  if (i < text.length) fail('sobra conteúdo depois do JSON');
  return v;
}

/** Volta para valores JSON comuns (para o JSON Schema). */
export function toPlain(x: J): J {
  if (x instanceof PyFloat) return x.value;
  if (Array.isArray(x)) return x.map(toPlain);
  if (isDict(x)) return Object.fromEntries(Object.entries(x).map(([k, v]) => [k, toPlain(v)]));
  return x;
}

// ---------- outras funções da biblioteca padrão ----------

/** `float(s)` do Python; `null` se o texto não for número. */
export function pyFloat(s: unknown): number | null {
  if (isNum(s)) return num(s);
  if (typeof s !== 'string') return null;
  const t = s.trim();
  const d = '\\d(?:_?\\d)*';
  if (new RegExp(`^[+-]?(?:${d}(?:\\.(?:${d})?)?|\\.${d})(?:[eE][+-]?${d})?$`).test(t)) return Number(t.replace(/_/g, ''));
  const m = /^([+-]?)(inf|infinity|nan)$/i.exec(t);
  if (m) return m[2]!.toLowerCase() === 'nan' ? NaN : m[1] === '-' ? -Infinity : Infinity;
  return null;
}

/** `fnmatch.fnmatchcase(name, pat)` */
export function fnmatchcase(name: string, pat: string): boolean {
  let re = '';
  for (let i = 0; i < pat.length; i++) {
    const c = pat[i]!;
    if (c === '*') re += '.*';
    else if (c === '?') re += '.';
    else if (c === '[') {
      let j = i + 1;
      if (pat[j] === '!') j++;
      if (pat[j] === ']') j++;
      while (j < pat.length && pat[j] !== ']') j++;
      if (j >= pat.length) re += '\\[';
      else {
        let stuff = pat.slice(i + 1, j).replace(/\\/g, '\\\\');
        if (stuff.startsWith('!')) stuff = '^' + stuff.slice(1);
        else if (stuff.startsWith('^')) stuff = '\\' + stuff;
        re += `[${stuff}]`;
        i = j;
      }
    } else re += c.replace(/[.*+?^${}()|[\]\\/-]/g, '\\$&');
  }
  return new RegExp(`^(?:${re})$`, 's').test(name);
}

/** `str.splitlines()` */
export function splitlines(s: string): string[] {
  const parts = s.split(/\r\n|[\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]/);
  if (parts.length && parts[parts.length - 1] === '') parts.pop();
  return parts;
}

/** `Path(name).suffix` */
export function suffix(name: string): string {
  const base = name.split(/[\\/]/).pop() ?? '';
  const i = base.lastIndexOf('.');
  return i > 0 && i < base.length - 1 ? base.slice(i) : '';
}
/** `Path(name).stem` */
export function stem(name: string): string {
  const base = name.split(/[\\/]/).pop() ?? '';
  const sfx = suffix(base);
  return sfx ? base.slice(0, -sfx.length) : base;
}
