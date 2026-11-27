/** `vnstudio stage <projeto> --out <pasta> [--plugin <pasta>...]`: monta o Build Staging (BS §4) e para aí. */
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { compileProject, loadProject } from '../bundle/index.js';
import { PluginCache } from '../plugins/cache.js';
import { githubTokenProvider } from '../plugins/credentials.js';
import { prepareDependencies, readLocks, type PreparedPlugin } from '../plugins/dependencies.js';
import { fetchGet } from '../plugins/http.js';
import { packPluginFolder } from '../plugins/pack.js';
import { validateProject } from '../validate/index.js';
import { defaultTemplateDirs, stageBuild, StagingError } from './staging.js';
import type { Edition } from '../bundle/input.js';

export const STAGE_USAGE = `uso: vnstudio stage <pasta-do-projeto> --out <pasta-de-staging> [--offline] [--edition standard|censored] [--plugin <pasta>...]

  --plugin <pasta>   usa a pasta vn_plugins/<namespace>/ do plugin no lugar do lock (desenvolvimento e testes)
  --offline          não consulta o catálogo nem baixa nada; falta no cache é erro

Sai com 0 ao montar o staging, 1 com erro de validação, 2 com dependência ausente ou template incompleto.`;

export async function runStage(args: string[]): Promise<number> {
  const flags = { out: undefined as string | undefined, offline: false, edition: undefined as Edition | undefined, plugins: [] as string[] };
  const rest: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i]!;
    if (a === '--offline') flags.offline = true;
    else if (a === '--out' && args[i + 1]) flags.out = resolve(args[++i]!);
    else if (a === '--edition' && (args[i + 1] === 'standard' || args[i + 1] === 'censored')) flags.edition = args[++i] as Edition;
    else if (a === '--plugin' && args[i + 1]) flags.plugins.push(resolve(args[++i]!));
    else rest.push(a);
  }
  if (rest.length !== 1 || !flags.out) {
    console.error(STAGE_USAGE);
    return 2;
  }
  const projectDir = resolve(rest[0]!);
  try {
    const { errors } = validateProject(projectDir, flags.plugins, { export: true });
    if (errors.length) {
      for (const d of errors) console.error(`${d.code} ${d.where}: ${d.message}`);
      return 1;
    }

    let prepared: PreparedPlugin[] = [];
    if (flags.plugins.length) {
      for (const dir of flags.plugins) {
        const manifest = JSON.parse(readFileSync(join(dir, 'plugin.json'), 'utf8')) as { id: string; version: string; namespace: string };
        prepared.push({ id: manifest.id, version: manifest.version, namespace: manifest.namespace, trust: 'local', from: 'embedded', folder: dir, package: await packPluginFolder(dir) });
      }
    } else {
      const { lock, localLock } = await readLocks(projectDir);
      const report = await prepareDependencies({
        projectDir,
        lock,
        ...(localLock ? { localLock } : {}),
        export: true,
        offline: flags.offline,
        cache: new PluginCache(),
        http: fetchGet,
        githubToken: githubTokenProvider(),
      });
      for (const i of report.issues) console.error(`${i.code ?? ''} ${i.message}`.trim());
      if (report.issues.some((i) => i.code !== 'B015')) return 2;
      prepared = report.plugins;
    }

    const compiled = compileProject(loadProject(projectDir, { pluginDirs: prepared.flatMap((p) => (p.folder ? [p.folder] : [])) }), flags.edition ? { edition: flags.edition } : {});
    const result = await stageBuild({ projectDir, compiled, plugins: prepared, stagingDir: flags.out, ...defaultTemplateDirs() });
    console.log(`staging ${result.buildId} em ${result.stagingDir}`);
    return 0;
  } catch (err) {
    if (err instanceof StagingError) {
      console.error(err.message);
      return 2;
    }
    throw err;
  }
}
