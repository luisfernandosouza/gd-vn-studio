#!/usr/bin/env node
import { formatSummary, summarizeProject } from '../project/summary.js';
import { runCompile } from '../bundle/cli.js';
import { runValidate } from '../validate/cli.js';
import { CLI_VERSION } from '../version.js';

const USAGE = `uso: vnstudio <comando>

  info <pasta>                         resume as cenas e as variáveis de um projeto de VN
  validate [--export] [--json] <pasta> [<plugin>...]
                                       confere o projeto (Data Model §11, UI Spec §11)
  compile [--edition standard|censored] [--stage] <pasta> <saída> [<plugin>...]
                                       gera o bundle (BS §5.1, §5.3, §5.4)
  --version                            versão da CLI

Os comandos de build e exportação chegam com as outras tarefas M5.`;

const [cmd, ...args] = process.argv.slice(2);

if (cmd === '--version' || cmd === '-v') {
  console.log(CLI_VERSION);
} else if (cmd === 'info' && args[0]) {
  console.log(formatSummary(await summarizeProject(args[0])));
} else if (cmd === 'validate') {
  process.exitCode = runValidate(args);
} else if (cmd === 'compile') {
  process.exitCode = runCompile(args);
} else {
  console.error(USAGE);
  process.exitCode = cmd === undefined || cmd === '--help' || cmd === '-h' ? 0 : 2;
}
