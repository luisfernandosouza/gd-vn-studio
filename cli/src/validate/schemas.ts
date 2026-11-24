/**
 * Conferência por JSON Schema (código S000, e P004 para `params` e `config` de plugins).
 *
 * Os schemas vêm de `docs/specs/schemas/` (fonte única, spec 09 §1). No pacote npm eles estão em
 * `cli/schemas/` e os presets em `cli/presets/`, gerados por `sync_generated_copies.py`.
 */
import { Ajv2020, type ErrorObject, type ValidateFunction } from 'ajv/dist/2020.js';
import { readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDir, loadJson } from './files.js';
import { pyRepr, toPlain, type J } from './py.js';

export const SCHEMA_BASE = 'https://schemas.vnstudio.dev/specs-v1.0.0/';

export interface SpecsPaths {
  schemas: string;
  presets: string;
}

/** Acha `schemas/` e `presets/`: `VNSTUDIO_SPECS`, o `docs/specs/` do monorepo, ou as cópias do pacote. */
export function findSpecs(specsDir?: string): SpecsPaths {
  const explicit = specsDir ?? process.env.VNSTUDIO_SPECS;
  if (explicit) return { schemas: path.join(explicit, 'schemas'), presets: path.join(explicit, 'presets') };
  const here = path.dirname(fileURLToPath(import.meta.url));
  // no monorepo: <raiz>/docs/specs; no pacote npm: <pacote>/schemas e <pacote>/presets (src|dist/validate → pacote)
  for (let dir = here, i = 0; i < 6; i++, dir = path.dirname(dir)) {
    const specs = path.join(dir, 'docs', 'specs');
    if (isDir(path.join(specs, 'schemas'))) return { schemas: path.join(specs, 'schemas'), presets: path.join(specs, 'presets') };
  }
  const pkg = path.resolve(here, '..', '..');
  if (isDir(path.join(pkg, 'schemas'))) return { schemas: path.join(pkg, 'schemas'), presets: path.join(pkg, 'presets') };
  throw new Error('não achei os schemas das specs (docs/specs/schemas/); use VNSTUDIO_SPECS=<pasta das specs>');
}

/** Um erro de schema no formato do validador de referência: caminho no documento e mensagem. */
export interface SchemaIssue {
  path: string;
  message: string;
}

const TYPE_NAMES: Record<string, string> = {
  string: 'um texto',
  integer: 'um número inteiro',
  number: 'um número',
  boolean: 'verdadeiro ou falso',
  object: 'um objeto',
  array: 'uma lista',
  null: 'nulo',
};

function short(x: J): string {
  const r = pyRepr(x);
  return r.length > 60 ? r.slice(0, 57) + '...' : r;
}

/** Mensagem em português simples para um erro do Ajv (Req §6). */
function message(e: ErrorObject): string {
  const p = e.params as Record<string, J>;
  switch (e.keyword) {
    case 'required':
      return `falta o campo obrigatório "${p.missingProperty}"`;
    case 'additionalProperties':
      return `campo desconhecido "${p.additionalProperty}"`;
    case 'unevaluatedProperties':
      return `campo desconhecido "${p.unevaluatedProperty}"`;
    case 'type': {
      const ts = String(p.type).split(',');
      return `deveria ser ${ts.map((t) => TYPE_NAMES[t] ?? t).join(' ou ')}, mas é ${short(e.data)}`;
    }
    case 'enum':
      return `${short(e.data)} não é um dos valores aceitos (${(p.allowedValues as J[]).map(short).join(', ')})`;
    case 'const':
      return `deveria ser ${short(p.allowedValue)}, mas é ${short(e.data)}`;
    case 'pattern':
      return `${short(e.data)} não segue o formato esperado (${p.pattern})`;
    case 'minLength':
      return `${short(e.data)} é curto demais (mínimo de ${p.limit} caractere(s))`;
    case 'maxLength':
      return `${short(e.data)} é longo demais (máximo de ${p.limit} caracteres)`;
    case 'minimum':
    case 'exclusiveMinimum':
      return `${short(e.data)} é pequeno demais (precisa ser ${p.comparison} ${p.limit})`;
    case 'maximum':
    case 'exclusiveMaximum':
      return `${short(e.data)} é grande demais (precisa ser ${p.comparison} ${p.limit})`;
    case 'multipleOf':
      return `${short(e.data)} precisa ser múltiplo de ${p.multipleOf}`;
    case 'minItems':
      return `a lista precisa de pelo menos ${p.limit} item(ns)`;
    case 'maxItems':
      return `a lista aceita no máximo ${p.limit} itens`;
    case 'uniqueItems':
      return `a lista tem itens repetidos (posições ${p.j} e ${p.i})`;
    case 'minProperties':
      return `precisa de pelo menos ${p.limit} campo(s)`;
    case 'maxProperties':
      return `aceita no máximo ${p.limit} campos`;
    case 'propertyNames':
      return `nome de campo inválido "${p.propertyName}"`;
    case 'dependentRequired':
    case 'dependencies':
      return `o campo "${p.property}" exige também "${p.missingProperty}"`;
    case 'anyOf':
      return 'não corresponde a nenhuma das formas aceitas';
    case 'oneOf':
      return p.passingSchemas ? 'corresponde a mais de uma das formas aceitas' : 'não corresponde a nenhuma das formas aceitas';
    case 'not':
      return `${short(e.data)} não é aceito aqui (valor reservado ou proibido)`;
    case 'false schema':
      return 'este campo não é aceito aqui';
    case 'contains':
      return 'a lista não tem nenhum item da forma esperada';
    default:
      return e.message ?? e.keyword;
  }
}

function underPath(p: string, base: string): boolean {
  return p === base || p.startsWith(base + '/');
}

/**
 * Aproxima a lista de `iter_errors` do `jsonschema` do Python: um `anyOf`/`oneOf` que falha conta como um
 * erro só (os erros de cada alternativa ficam de fora), e o `if` de um `if/then` não vira erro próprio.
 */
function collapse(errors: ErrorObject[]): ErrorObject[] {
  const keep = errors.map(() => true);
  errors.forEach((e, k) => {
    if (e.keyword === 'if') keep[k] = false;
    if (e.keyword !== 'anyOf' && e.keyword !== 'oneOf') return;
    for (let j = k - 1; j >= 0 && underPath(errors[j]!.instancePath, e.instancePath); j--) keep[j] = false;
  });
  return errors.filter((_, k) => keep[k]);
}

function decodePointer(p: string): string {
  return p
    .split('/')
    .slice(1)
    .map((s) => s.replace(/~1/g, '/').replace(/~0/g, '~'))
    .join('/');
}

function toIssues(v: ValidateFunction, data: J): SchemaIssue[] {
  if (v(toPlain(data))) return [];
  return collapse(v.errors ?? [])
    .map((e) => ({ path: decodePointer(e.instancePath), message: message(e).slice(0, 200) }))
    .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
}

/** Os schemas das specs carregados num Ajv (2020-12, sem conferir `format`, como o `jsonschema` do Python). */
export class Schemas {
  private readonly ajv: Ajv2020;
  private readonly adhoc = new Map<string, ValidateFunction | null>();

  constructor(readonly paths: SpecsPaths) {
    this.ajv = new Ajv2020({ strict: false, allErrors: true, validateFormats: false, verbose: true });
    for (const f of readdirSync(paths.schemas).filter((n) => n.endsWith('.schema.json')).sort()) {
      const s = loadJson(path.join(paths.schemas, f));
      this.ajv.addSchema(toPlain(s), SCHEMA_BASE + f);
    }
  }

  /** Erros de `data` contra um schema das specs (`scene.schema.json`…). */
  check(schemaFile: string, data: J): SchemaIssue[] {
    const v = this.ajv.getSchema(SCHEMA_BASE + schemaFile);
    if (!v) throw new Error(`schema ${schemaFile} não encontrado`);
    return toIssues(v, data);
  }

  /** Erros de `data` contra um schema avulso (`params_schema`, `config_schema` de um plugin). */
  checkAdhoc(schema: J, data: J): SchemaIssue[] {
    const plain = toPlain(schema ?? {});
    const key = JSON.stringify(plain);
    let v = this.adhoc.get(key);
    if (v === undefined) {
      try {
        const copy = typeof plain === 'object' && plain !== null ? { ...plain } : plain;
        if (typeof copy === 'object' && copy !== null) delete copy.$id;
        v = this.ajv.compile(copy);
      } catch {
        v = null;
      }
      this.adhoc.set(key, v);
    }
    if (v === null) return [{ path: '', message: 'o schema do plugin é inválido' }];
    return toIssues(v, data);
  }
}
