/**
 * Problemas da resolução de dependências (Plugin SDK §11.3) e da etapa de dependências do build
 * (Build System §3.2). Os códigos B0xx e P0xx são os das specs (BS §13, Data Model §11). As falhas do
 * resolvedor que as specs não numeram (conflito, ciclo, dependência desabilitada…) usam um `kind` sem código.
 */
export type IssueCode = 'B002' | 'B003' | 'B015' | 'P001' | 'P013' | 'P021';

export type IssueKind =
  | 'integrity' // B002
  | 'revoked' // B003
  | 'catalog-offline' // B015 (aviso)
  | 'duplicate-namespace' // P001
  | 'link-on-export' // P013
  | 'bad-path' // P021
  | 'conflict'
  | 'cycle'
  | 'disabled-dependency'
  | 'not-found'
  | 'manifest-mismatch'
  | 'offline-missing'
  | 'token-required'
  | 'network'
  | 'bad-package'
  | 'bad-catalog';

export interface DependencyIssue {
  kind: IssueKind;
  code?: IssueCode;
  level: 'error' | 'warning';
  /** id do plugin, quando o problema é de um plugin. */
  plugin?: string;
  version?: string;
  /** Mensagem simples para o autor (Req §6). */
  message: string;
  /** Texto técnico ("Detalhes"). */
  details?: string;
}

export class DependencyError extends Error {
  readonly issues: DependencyIssue[];
  constructor(issues: DependencyIssue[]) {
    super(issues.map((i) => (i.code ? `${i.code}: ${i.message}` : i.message)).join('\n'));
    this.name = 'DependencyError';
    this.issues = issues;
  }
}

export function issue(
  kind: IssueKind,
  message: string,
  extra: Partial<Omit<DependencyIssue, 'kind' | 'message'>> = {},
): DependencyIssue {
  const codes: Partial<Record<IssueKind, IssueCode>> = {
    integrity: 'B002',
    revoked: 'B003',
    'catalog-offline': 'B015',
    'duplicate-namespace': 'P001',
    'link-on-export': 'P013',
    'bad-path': 'P021',
  };
  const code = codes[kind];
  return {
    kind,
    ...(code ? { code } : {}),
    level: kind === 'catalog-offline' ? 'warning' : 'error',
    message,
    ...extra,
  };
}

/** Falha de rede (sem internet, DNS, conexão recusada). Quem chama decide se vira B015 ou erro. */
export class NetworkError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = 'NetworkError';
  }
}
