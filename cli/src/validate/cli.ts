/** `vnstudio validate [--export] [--json] <projeto> [<plugin>...]` */
import { formatDiagnostic, validateProject, type Diagnostic } from './validator.js';

export const VALIDATE_USAGE = `uso: vnstudio validate [--export] [--json] <pasta-do-projeto> [<pasta-de-plugin>...]

  --export   aplica também as regras de exportação (R021, P013; W013 e U009 viram erro)
  --json     saída em JSON: { errors, warnings }, cada um com code, where, detail e message`;

/** Roda o comando e devolve o código de saída (0 sem erros, 1 com erros, 2 uso errado). */
export function runValidate(args: string[], out: (s: string) => void = console.log, errOut: (s: string) => void = console.error): number {
  const flags = new Set(args.filter((a) => a.startsWith('--')));
  const paths = args.filter((a) => !a.startsWith('--'));
  const unknown = [...flags].filter((f) => f !== '--export' && f !== '--json');
  if (!paths.length || unknown.length) {
    errOut(VALIDATE_USAGE);
    return 2;
  }
  const [project, ...plugins] = paths as [string, ...string[]];
  const r = validateProject(project, plugins, { export: flags.has('--export') });
  if (flags.has('--json')) {
    out(JSON.stringify(r, null, 2));
  } else {
    const show = (label: string, d: Diagnostic) => out(`${label} [${d.code}] ${d.message}\n       ${formatDiagnostic(d)}`);
    for (const w of r.warnings) show('AVISO', w);
    for (const e of r.errors) show('ERRO ', e);
    out(`\n${r.errors.length} erro(s), ${r.warnings.length} aviso(s).`);
  }
  return r.errors.length ? 1 : 0;
}
