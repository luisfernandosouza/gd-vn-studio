#!/usr/bin/env node
import { CLI_VERSION } from '../version.js';

const USAGE = `uso: vnplugin <comando>

  --version      versão da CLI

Os comandos do Plugin SDK §13 (create, validate, test, build, publish…) chegam com as tarefas M3 e M5.`;

const cmd = process.argv[2];

if (cmd === '--version' || cmd === '-v') {
  console.log(CLI_VERSION);
} else {
  console.error(USAGE);
  process.exitCode = cmd === undefined || cmd === '--help' || cmd === '-h' ? 0 : 2;
}
