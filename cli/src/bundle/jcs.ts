/**
 * JSON canônico (RFC 8785, JCS), Build System §5.1: UTF-8, chaves ordenadas por unidades UTF-16,
 * sem espaços, números no formato mais curto que preserva o valor (Number.prototype.toString do
 * ECMAScript) e strings com escape mínimo. É o serializador do `content_hash`, da assinatura de saves
 * e perfil (§8.3) e do `build.json`. Conferido pelos vetores de `conformance/canonical.json`.
 *
 * Não depende de Node: o Studio (WebView) usa o mesmo módulo.
 */

export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type JsonObject = { [key: string]: Json };

/** Ordem do JCS (RFC 8785 §3.2.3): unidades UTF-16, que é a comparação nativa de strings do JS. */
function utf16Compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

function number(n: number): string {
  if (!Number.isFinite(n)) throw new RangeError('número não finito não tem forma canônica');
  // String() já é o Number::toString do ECMAScript, que o JCS adota; -0 sai "0".
  return String(n);
}

/**
 * Escape mínimo (RFC 8785 §3.2.2.2): `JSON.stringify` de uma string já escapa só aspas, barra
 * invertida e controles (com \b \f \n \r \t curtos e \u00xx minúsculo), e deixa `/`, U+007F,
 * U+2028 e o resto crus, como o JCS pede.
 */
function string(s: string): string {
  return JSON.stringify(s);
}

export function canonicalize(value: unknown): string {
  if (value === null) return 'null';
  switch (typeof value) {
    case 'boolean':
      return value ? 'true' : 'false';
    case 'number':
      return number(value);
    case 'string':
      return string(value);
    case 'object': {
      if (Array.isArray(value)) return '[' + value.map(canonicalize).join(',') + ']';
      const obj = value as Record<string, unknown>;
      const keys = Object.keys(obj)
        .filter((k) => obj[k] !== undefined)
        .sort(utf16Compare);
      return '{' + keys.map((k) => string(k) + ':' + canonicalize(obj[k])).join(',') + '}';
    }
    default:
      throw new TypeError(`valor sem forma JSON: ${typeof value}`);
  }
}

/** Bytes UTF-8 da forma canônica. */
export function canonicalBytes(value: unknown): Uint8Array {
  return new TextEncoder().encode(canonicalize(value));
}
