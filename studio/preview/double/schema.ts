/**
 * Validação das mensagens do Preview contra `docs/specs/schemas/preview-protocol.schema.json` (spec 07).
 *
 * Usa o Ajv, que compila os schemas com `new Function`: a CSP do Studio não permite `unsafe-eval`, então este
 * módulo é só para os testes (Vitest) e ferramentas em Node, nunca para o bundle do app. O dublê recebe a
 * validação por injeção (`FakePreviewRuntimeOptions.validator`) e funciona sem ela.
 */
import Ajv2020 from 'ajv/dist/2020';
import type { ErrorObject as AjvError, ValidateFunction } from 'ajv';
import addFormats from 'ajv-formats';
import type { MessageValidator } from './types';

const PROTOCOL_ID = 'https://schemas.vnstudio.dev/specs-v1.0.0/preview-protocol.schema.json';

const schemaModules = import.meta.glob<Record<string, unknown>>('../../../docs/specs/schemas/*.schema.json', {
  eager: true,
  import: 'default',
});

/** `preview.set_variables` → `Preview_set_variables`; `session.hello` → `Session_hello`. */
export function defName(method: string): string {
  const flat = method.replace('.', '_');
  return flat.charAt(0).toUpperCase() + flat.slice(1);
}

function format(errors: AjvError[] | null | undefined): string {
  return (errors ?? [])
    .slice(0, 8)
    .map((e) => `${e.instancePath || '/'} ${e.message ?? ''}${e.params ? ' ' + JSON.stringify(e.params) : ''}`)
    .join('; ');
}

export interface ProtocolSchema extends MessageValidator {
  /** Valida qualquer mensagem do protocolo (requisição, notificação ou resposta) só pela forma geral. */
  validateMessage(message: unknown): string | null;
  /** Valida `value` contra `$defs/<nome>` do schema do protocolo. */
  validateDef(name: string, value: unknown): string | null;
}

let cached: ProtocolSchema | null = null;

/** Carrega todos os schemas das specs (o do protocolo referencia `common` e `save`) e compila uma vez. */
export function loadProtocolSchema(): ProtocolSchema {
  if (cached) return cached;
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  addFormats(ajv);
  for (const schema of Object.values(schemaModules)) ajv.addSchema(schema);

  const message = ajv.getSchema(PROTOCOL_ID);
  if (!message) throw new Error(`schema ${PROTOCOL_ID} não encontrado`);
  const defs = new Map<string, ValidateFunction>();
  const def = (name: string): ValidateFunction => {
    let fn = defs.get(name);
    if (!fn) {
      fn = ajv.getSchema(`${PROTOCOL_ID}#/$defs/${name}`);
      if (!fn) throw new Error(`$defs/${name} não existe em preview-protocol.schema.json`);
      defs.set(name, fn);
    }
    return fn;
  };

  const validateMessage = (value: unknown): string | null => (message(value) ? null : format(message.errors));
  const validateDef = (name: string, value: unknown): string | null => {
    const fn = def(name);
    return fn(value) ? null : format(fn.errors);
  };

  cached = {
    validateMessage,
    validateDef,
    checkRequest(request) {
      return validateMessage(request);
    },
    checkOutgoing(outgoing, requestMethod) {
      const envelope = validateMessage(outgoing);
      if (envelope) return envelope;
      // A forma geral aceita qualquer `result`; o resultado de cada método está em $defs/<Método>_result.
      if (requestMethod && 'result' in outgoing) {
        const problem = validateDef(`${defName(requestMethod)}_result`, outgoing.result);
        if (problem) return `result de ${requestMethod}: ${problem}`;
      }
      return null;
    },
  };
  return cached;
}
