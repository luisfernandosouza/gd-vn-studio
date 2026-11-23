#!/usr/bin/env node
import { formatSummary, summarizeProject } from '../project/summary.js';
import { CLI_VERSION } from '../version.js';

const USAGE = `uso: vnstudio <comando>

  info <pasta>   resume as cenas e as variáveis de um projeto de VN
  --version      versão da CLI

Os comandos do Build System (validate, build, export…) chegam com as tarefas M5.`;

const [cmd, ...args] = process.argv.slice(2);

if (cmd === '--version' || cmd === '-v') {
  console.log(CLI_VERSION);
} else if (cmd === 'info' && args[0]) {
  console.log(formatSummary(await summarizeProject(args[0])));
} else {
  console.error(USAGE);
  process.exitCode = cmd === undefined || cmd === '--help' || cmd === '-h' ? 0 : 2;
}
