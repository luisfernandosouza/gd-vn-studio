/** `vnstudio compile [--edition standard|censored] [--stage] <projeto> <saída> [<plugin>...]` */
import { compileProject } from './compile.js';
import { loadProject } from './load.js';
import { stageAssets } from './stage.js';
import { writeBundle } from './write.js';
import { validateProject } from '../validate/validator.js';

export const COMPILE_USAGE = `uso: vnstudio compile [--edition standard|censored] [--stage] <pasta-do-projeto> <saída> [<pasta-de-plugin>...]

  --edition  edição do build (BS §5.4); sem a opção vale project.json → build.edition
  --stage    copia também os assets usados (na edição censurada, sem os originais)

Os idiomas vêm de project.json → build.locales (BS §5.3), ou de todos os \`locales\`.`;

/** Roda o comando e devolve o código de saída (0 ok, 1 erro de validação, 2 uso errado). */
export function runCompile(args: string[], out: (s: string) => void = console.log, errOut: (s: string) => void = console.error): number {
  let edition: 'standard' | 'censored' | undefined;
  let stage = false;
  const paths: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i]!;
    if (a === '--stage') stage = true;
    else if (a === '--edition') {
      const v = args[++i];
      if (v !== 'standard' && v !== 'censored') {
        errOut(COMPILE_USAGE);
        return 2;
      }
      edition = v;
    } else if (a.startsWith('--')) {
      errOut(COMPILE_USAGE);
      return 2;
    } else paths.push(a);
  }
  if (paths.length < 2) {
    errOut(COMPILE_USAGE);
    return 2;
  }
  const [project, dest, ...plugins] = paths as [string, string, ...string[]];
  const v = validateProject(project, plugins, {});
  if (v.errors.length) {
    for (const e of v.errors) errOut(`ERRO [${e.code}] ${e.message}`);
    return 1;
  }
  const compiled = compileProject(loadProject(project, { pluginDirs: plugins }), { edition });
  writeBundle(dest, compiled);
  let extra = '';
  if (stage) {
    const r = stageAssets(project, dest, compiled.bundle);
    extra = `, ${r.copied.length} asset(s)`;
    for (const m of r.missing) errOut(`AVISO asset ausente no projeto: ${m}`);
  }
  out(`bundle gravado em ${dest} (${compiled.bundle.content_hash}; ${Object.keys(compiled.bundle.scenes).length} cenas, ${Object.keys(compiled.locales).length} idioma(s)${extra})`);
  return 0;
}
