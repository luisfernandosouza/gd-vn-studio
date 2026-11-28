/** Códigos de erro das edições (Plugin SDK §10.3, §10.4.1). `CONFLICT` e `FORBIDDEN_PATH` vêm da spec; os demais são do Studio. */
export type VNErrorCode =
  | 'CONFLICT'
  | 'FORBIDDEN_PATH'
  /** Patch malformado: operação desconhecida, ponteiro inválido, `test` ausente, entidade com `id` diferente da chave. */
  | 'INVALID_PATCH'
  /** Ponteiro que não existe no documento (inclusive `@<id>` sem elemento com esse id). */
  | 'NOT_FOUND'
  /** O validador recusou o documento resultante. */
  | 'VALIDATION_FAILED';

export class VNError extends Error {
  readonly code: VNErrorCode;
  constructor(code: VNErrorCode, message: string) {
    super(message);
    this.name = 'VNError';
    this.code = code;
  }
}
