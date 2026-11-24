/**
 * O pouco de lógica narrativa que o dublê precisa para andar pelas cenas: variáveis com as validações de
 * escrita do RT §6.2, condições, expressões de valor e efeitos. É um subconjunto pequeno e não substitui o
 * runtime: sem RNG (`random_int` devolve o mínimo), sem `event_since_last_selection` (sempre falso) e sem
 * aliases de variáveis.
 */
import type { DoubleVariable, JsonObject, Literal } from './types';

export const MAX_SAFE = 2 ** 53 - 1;

export interface Change {
  variable: string;
  old: Literal | null;
  new: Literal | null;
}

/** Erro de escrita com o código do RT §6.2 (`READ_ONLY`, `TYPE_MISMATCH`…). */
export class WriteError extends Error {
  constructor(
    readonly vnCode: string,
    readonly variable: string,
    message: string,
  ) {
    super(message);
  }
}

const typeDefault: Record<DoubleVariable['type'], Literal> = {
  integer: 0,
  number: 0,
  boolean: false,
  string: '',
  enum: '',
};

export function defaultOf(def: DoubleVariable): Literal {
  if (def.default !== undefined) return def.default;
  if (def.type === 'enum') return def.constraints?.values?.[0] ?? '';
  return typeDefault[def.type];
}

export class VariableStore {
  private defs = new Map<string, DoubleVariable>();
  private values = new Map<string, Literal>();
  private sys = new Map<string, Literal>();

  define(ref: string, def: DoubleVariable, initial?: Literal): void {
    this.defs.set(ref, def);
    if (!def.derived) this.values.set(ref, initial ?? defaultOf(def));
  }

  /** Remove as variáveis de um escopo que terminou (`scene.`, `chapter.`). */
  dropScope(prefix: string): void {
    for (const ref of [...this.defs.keys()]) {
      if (ref.startsWith(prefix)) {
        this.defs.delete(ref);
        this.values.delete(ref);
      }
    }
  }

  setSys(ref: string, value: Literal): void {
    this.sys.set(ref, value);
  }

  has(ref: string): boolean {
    return this.defs.has(ref) || this.sys.has(ref);
  }

  definition(ref: string): DoubleVariable | undefined {
    return this.defs.get(ref);
  }

  get(ref: string): Literal | undefined {
    if (this.sys.has(ref)) return this.sys.get(ref);
    const def = this.defs.get(ref);
    if (!def) return undefined;
    if (def.derived !== undefined) {
      const value = evalValue(def.derived, { get: (r) => (r === ref ? undefined : this.get(r)) });
      return value ?? defaultOf(def);
    }
    return this.values.get(ref);
  }

  /** Todas as variáveis legíveis agora, inclusive `sys.*` e derivadas (spec 07 §5). */
  snapshot(): Record<string, Literal> {
    const out: Record<string, Literal> = {};
    for (const ref of [...this.defs.keys()].sort()) {
      const value = this.get(ref);
      if (value !== undefined) out[ref] = value;
    }
    for (const [ref, value] of [...this.sys.entries()].sort(([a], [b]) => a.localeCompare(b))) out[ref] = value;
    return out;
  }

  /**
   * Aplica escritas como uma transação (RT §6.1): valida todas e só então aplica; na primeira falha, nada muda.
   * `values` chega em ordem; operações relativas já vêm calculadas por `effectWrites`.
   */
  commit(writes: { variable: string; value: Literal }[]): Change[] {
    const pending = new Map<string, Literal>();
    for (const { variable, value } of writes) {
      pending.set(variable, this.check(variable, value));
    }
    const changes: Change[] = [];
    for (const [variable, value] of pending) {
      const old = this.values.get(variable) ?? null;
      if (old === value) continue;
      this.values.set(variable, value);
      changes.push({ variable, old, new: value });
    }
    return changes;
  }

  /** Validações do RT §6.2 que fazem sentido no dublê (passos 3, 4, 7, 8 e 9). Devolve o valor final. */
  check(variable: string, value: Literal): Literal {
    if (this.sys.has(variable) || variable.startsWith('sys.')) {
      throw new WriteError('READ_ONLY', variable, `${variable} é do sistema`);
    }
    const def = this.defs.get(variable);
    if (!def) throw new WriteError('VARIABLE_NOT_FOUND', variable, `${variable} não existe no ponto atual`);
    if (def.derived !== undefined) throw new WriteError('READ_ONLY', variable, `${variable} é derivada`);
    const c = def.constraints ?? {};
    switch (def.type) {
      case 'boolean':
        if (typeof value !== 'boolean') throw mismatch(variable, def, value);
        return value;
      case 'string':
        if (typeof value !== 'string') throw mismatch(variable, def, value);
        if (c.max_length !== undefined && [...value].length > c.max_length) {
          throw new WriteError('CONSTRAINT_VIOLATION', variable, `${variable} passa de ${c.max_length} caracteres`);
        }
        return value;
      case 'enum':
        if (typeof value !== 'string') throw mismatch(variable, def, value);
        if (c.values && !c.values.includes(value)) {
          throw new WriteError('CONSTRAINT_VIOLATION', variable, `${value} não está nos valores de ${variable}`);
        }
        return value;
      case 'integer':
      case 'number': {
        if (typeof value !== 'number' || (def.type === 'integer' && !Number.isInteger(value))) {
          throw mismatch(variable, def, value);
        }
        if (!Number.isFinite(value) || (def.type === 'integer' && Math.abs(value) > MAX_SAFE)) {
          throw new WriteError('OUT_OF_RANGE', variable, `${value} fora do intervalo de ${variable}`);
        }
        const below = c.min !== undefined && value < c.min;
        const above = c.max !== undefined && value > c.max;
        if (below || above) {
          if (c.on_overflow === 'reject') {
            throw new WriteError('CONSTRAINT_VIOLATION', variable, `${value} fora de [${c.min}, ${c.max}] em ${variable}`);
          }
          return below ? (c.min as number) : (c.max as number);
        }
        return value;
      }
    }
  }
}

function mismatch(variable: string, def: DoubleVariable, value: unknown): WriteError {
  return new WriteError('TYPE_MISMATCH', variable, `${variable} é ${def.type}, não ${JSON.stringify(value)}`);
}

export interface EvalContext {
  get(ref: string): Literal | undefined;
  /** Payload do resultado de uma atividade (`{ "result": "campo" }` em `on_result.effects`). */
  result?: JsonObject;
}

const isObject = (v: unknown): v is JsonObject => typeof v === 'object' && v !== null && !Array.isArray(v);

/** Expressão de valor (`common.schema.json → ValueExpr`). `undefined` quando não dá para calcular. */
export function evalValue(expr: unknown, ctx: EvalContext): Literal | undefined {
  if (typeof expr === 'boolean' || typeof expr === 'number' || typeof expr === 'string') return expr;
  if (!isObject(expr)) return undefined;
  if (typeof expr.var === 'string') return ctx.get(expr.var);
  if (typeof expr.result === 'string') {
    let cur: unknown = ctx.result;
    for (const part of expr.result.split('.')) cur = isObject(cur) ? cur[part] : undefined;
    if (typeof cur === 'boolean' || typeof cur === 'number' || typeof cur === 'string') return cur;
    return evalValue(expr.default, ctx);
  }
  if ('if' in expr) return evalCondition(expr.if, ctx) ? evalValue(expr.then, ctx) : evalValue(expr.else, ctx);
  if (typeof expr.fn === 'string' && Array.isArray(expr.args)) {
    const args = expr.args.map((a) => evalValue(a, ctx));
    if (args.some((a) => a === undefined)) return undefined;
    const n = args as number[];
    switch (expr.fn) {
      case 'add':
        return n.reduce((a, b) => a + b);
      case 'sub':
        return n.reduce((a, b) => a - b);
      case 'mul':
        return n.reduce((a, b) => a * b);
      case 'div':
        return n.slice(1).some((b) => b === 0) ? undefined : n.reduce((a, b) => a / b);
      case 'mod':
        return n[1] === 0 ? undefined : (n[0] as number) % (n[1] as number);
      case 'min':
        return Math.min(...n);
      case 'max':
        return Math.max(...n);
      case 'clamp':
        return Math.min(Math.max(n[0] as number, n[1] as number), n[2] as number);
      case 'round':
        return Math.round(n[0] as number);
      case 'floor':
        return Math.floor(n[0] as number);
      case 'ceil':
        return Math.ceil(n[0] as number);
      case 'abs':
        return Math.abs(n[0] as number);
      case 'concat':
        return args.map(String).join('');
      case 'random_int':
        return n[0];
    }
  }
  return undefined;
}

/** Árvore de condição (`Condition`/`ConditionList`); uma lista é um `all`, e a lista vazia é verdadeira. */
export function evalCondition(cond: unknown, ctx: EvalContext): boolean {
  if (cond === undefined || cond === null) return true;
  if (Array.isArray(cond)) return cond.every((c) => evalCondition(c, ctx));
  if (!isObject(cond)) return false;
  if (Array.isArray(cond.all)) return cond.all.every((c) => evalCondition(c, ctx));
  if (Array.isArray(cond.any)) return cond.any.some((c) => evalCondition(c, ctx));
  if ('not' in cond) return !evalCondition(cond.not, ctx);
  if ('event_since_last_selection' in cond) return false;
  if (typeof cond.variable !== 'string' || typeof cond.operator !== 'string') return false;
  const actual = ctx.get(cond.variable);
  const expected = Array.isArray(cond.value) ? cond.value : evalValue(cond.value, ctx);
  switch (cond.operator) {
    case 'equals':
      return actual === expected;
    case 'not_equals':
      return actual !== expected;
    case 'greater_than':
      return typeof actual === 'number' && typeof expected === 'number' && actual > expected;
    case 'greater_than_or_equal':
      return typeof actual === 'number' && typeof expected === 'number' && actual >= expected;
    case 'less_than':
      return typeof actual === 'number' && typeof expected === 'number' && actual < expected;
    case 'less_than_or_equal':
      return typeof actual === 'number' && typeof expected === 'number' && actual <= expected;
    case 'in':
      return Array.isArray(expected) && expected.includes(actual);
    case 'not_in':
      return Array.isArray(expected) && !expected.includes(actual);
    case 'contains':
      return typeof actual === 'string' && typeof expected === 'string' && actual.includes(expected);
    default:
      return false;
  }
}

/**
 * Transforma uma lista de efeitos (`EffectList`) nas escritas da transação, calculando as operações relativas
 * sobre o valor que a própria transação já escreveu. Um efeito cujo valor o dublê não sabe calcular é ignorado.
 */
export function effectWrites(
  effects: unknown,
  store: VariableStore,
  ctx: EvalContext,
): { variable: string; value: Literal }[] {
  if (!Array.isArray(effects)) return [];
  const staged = new Map<string, Literal>();
  const current = (ref: string) => (staged.has(ref) ? staged.get(ref) : store.get(ref));
  const local: EvalContext = { get: current, result: ctx.result };
  for (const effect of effects) {
    if (!isObject(effect) || typeof effect.variable !== 'string') continue;
    const ref = effect.variable;
    const old = current(ref);
    let value: Literal | undefined;
    if (effect.op === 'toggle') value = typeof old === 'boolean' ? !old : undefined;
    else if (effect.op === 'reset') {
      const def = store.definition(ref);
      value = def ? defaultOf(def) : undefined;
    } else {
      const operand = evalValue(effect.value, local);
      if (effect.op === 'set') value = operand;
      else if (typeof old === 'number' && typeof operand === 'number') {
        if (effect.op === 'add') value = old + operand;
        else if (effect.op === 'subtract') value = old - operand;
        else if (effect.op === 'multiply') value = old * operand;
      }
    }
    if (value === undefined) continue;
    staged.set(ref, value);
  }
  return [...staged].map(([variable, value]) => ({ variable, value }));
}

/** Interpolação de texto (`{global.player_money}`, `{{` e `}}` literais), sem formatação por idioma. */
export function interpolate(text: string, get: (ref: string) => Literal | undefined): string {
  return text.replace(/\{\{|\}\}|\{([a-z][a-z0-9_.-]*)\}/g, (match, ref: string | undefined) => {
    if (match === '{{') return '{';
    if (match === '}}') return '}';
    const value = ref ? get(ref) : undefined;
    return value === undefined ? match : String(value);
  });
}
