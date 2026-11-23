#!/usr/bin/env node
/**
 * Gera generated/schemas.d.ts a partir de docs/specs/schemas/ (tarefa M0-06, spec 09 §1, Plugin SDK §10).
 *
 * docs/specs/schemas/ é a fonte única dos schemas. Este script não copia schemas: ele junta todos os
 * arquivos num documento só, com um nome TypeScript por raiz e por $defs, e passa esse documento ao
 * json-schema-to-typescript. Assim cada definição comum (EntityId, VariableDefinition…) vira um tipo
 * só, compartilhado por todos os arquivos, em vez de uma cópia por schema.
 *
 * Nomes:
 *   - a raiz de cada arquivo recebe o nome de ROOTS (scene.schema.json → Scene);
 *   - cada $defs mantém a chave (common.schema.json#/$defs/VariableDefinition → VariableDefinition);
 *     se a chave colidir com outro nome, ganha o nome da raiz do arquivo como prefixo;
 *   - ALIASES acrescenta nomes de conveniência (Variable = VariableDefinition).
 *
 * Uso:
 *   node scripts/generate.mjs           gera
 *   node scripts/generate.mjs --check   falha (código 1) se o arquivo gerado estiver desatualizado
 */
import { readFileSync, readdirSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { compile } from 'json-schema-to-typescript';

const HERE = dirname(fileURLToPath(import.meta.url));
const PKG = join(HERE, '..');
const REPO = join(PKG, '..', '..');
const SCHEMAS = join(REPO, 'docs', 'specs', 'schemas');
const OUT = join(PKG, 'generated', 'schemas.d.ts');

/** Nome TypeScript da raiz de cada schema. Um schema novo sem nome aqui faz o script parar. */
const ROOTS = {
  'assets.schema.json': 'Assets',
  'build-manifest.schema.json': 'BuildManifest',
  'bundle-licenses.schema.json': 'BundleLicenses',
  'bundle-locale.schema.json': 'BundleLocale',
  'bundle-plugins.schema.json': 'BundlePlugins',
  'bundle.schema.json': 'Bundle',
  'chapter.schema.json': 'Chapter',
  'character.schema.json': 'Character',
  'common.schema.json': null, // só $defs
  'conformance.schema.json': 'ConformanceFile',
  'locale.schema.json': 'LocaleFile', // "Locale" já é o código de idioma (common)
  'plugin-lock.schema.json': 'PluginLock',
  'plugin.schema.json': 'PluginManifest',
  'plugins.schema.json': 'ProjectPlugins',
  'preview-protocol.schema.json': 'PreviewMessage',
  'project.schema.json': 'Project',
  'save.schema.json': 'Save',
  'scene.schema.json': 'Scene',
  'set.schema.json': 'SetFile', // "Set" é o Set do JavaScript
  'theme.schema.json': 'Theme',
  'ui-screen.schema.json': 'UiScreen',
  'variables.schema.json': 'Variables',
};

/** Nomes de conveniência citados pelas specs e pelo backlog. */
const ALIASES = {
  Variable: 'VariableDefinition',
};

// Palavras-chave cujo valor é um schema, uma lista de schemas ou um mapa de schemas (JSON Schema 2020-12).
const SUBSCHEMA = ['items', 'additionalProperties', 'not', 'if', 'then', 'else', 'contains', 'propertyNames',
  'unevaluatedItems', 'unevaluatedProperties', 'contentSchema'];
const SUBSCHEMA_LIST = ['allOf', 'anyOf', 'oneOf', 'prefixItems'];
const ANNOTATIONS = ['description', 'title', '$comment', 'default', 'examples', 'deprecated', 'readOnly', 'writeOnly'];
const SUBSCHEMA_MAP = ['properties', 'patternProperties', 'dependentSchemas', '$defs', 'definitions'];

function fail(msg) {
  console.error(`plugin-schema: ${msg}`);
  process.exit(1);
}

function loadSchemas() {
  const files = readdirSync(SCHEMAS).filter((f) => f.endsWith('.schema.json')).sort();
  for (const f of files) if (!(f in ROOTS)) fail(`${f} não tem nome de raiz em ROOTS (scripts/generate.mjs)`);
  for (const f of Object.keys(ROOTS)) if (!files.includes(f)) fail(`ROOTS cita ${f}, que não existe em docs/specs/schemas/`);
  return files.map((file) => ({ file, schema: JSON.parse(readFileSync(join(SCHEMAS, file), 'utf8')) }));
}

/** Decide o nome de cada raiz e de cada $defs, sem colisões. */
function assignNames(schemas) {
  const names = new Map(); // `${file}#${def ?? ''}` → nome
  const taken = new Map(); // nome → origem
  const claim = (key, name) => {
    if (taken.has(name)) fail(`nome ${name} usado por ${taken.get(name)} e ${key}`);
    taken.set(name, key);
    names.set(key, name);
  };
  for (const { file } of schemas) if (ROOTS[file]) claim(`${file}#`, ROOTS[file]);
  // common primeiro: os nomes dele são os mais usados e ficam sem prefixo.
  const ordered = [...schemas].sort((a, b) => (a.file === 'common.schema.json' ? -1 : b.file === 'common.schema.json' ? 1 : 0));
  for (const { file, schema } of ordered) {
    for (const def of Object.keys(schema.$defs ?? {}).sort()) {
      const name = taken.has(def) ? `${ROOTS[file]}${def}` : def;
      claim(`${file}#${def}`, name);
    }
  }
  for (const [alias, target] of Object.entries(ALIASES)) {
    if (taken.has(alias)) fail(`apelido ${alias} colide com ${taken.get(alias)}`);
    if (![...names.values()].includes(target)) fail(`apelido ${alias} aponta para ${target}, que não existe`);
  }
  return names;
}

/** Reescreve um $ref ("common.schema.json#/$defs/X", "#/$defs/Y/properties/z", "save.schema.json") para o documento único. */
function rewriteRef(ref, file, names) {
  const hash = ref.indexOf('#');
  const target = hash === -1 ? ref : ref.slice(0, hash) || file;
  const pointer = hash === -1 ? '' : ref.slice(hash + 1);
  if (!(target in ROOTS)) fail(`${file}: $ref ${ref} aponta para fora de docs/specs/schemas/`);
  const m = /^\/\$defs\/([^/]+)(.*)$/.exec(pointer);
  if (m) {
    const name = names.get(`${target}#${m[1]}`);
    if (!name) fail(`${file}: $ref ${ref} cita uma definição que não existe`);
    return `#/$defs/${name}${m[2]}`;
  }
  const root = names.get(`${target}#`);
  if (!root) fail(`${file}: $ref ${ref} cita a raiz de um schema sem raiz`);
  if (pointer && !pointer.startsWith('/')) fail(`${file}: $ref ${ref} não é um ponteiro JSON`);
  return `#/$defs/${root}${pointer}`;
}

/**
 * Copia um schema reescrevendo os $ref e tirando $id, $schema e os title internos: o
 * json-schema-to-typescript usa title como nome de tipo, e os nomes são só os de assignNames.
 */
function transform(node, file, names) {
  if (Array.isArray(node)) return node.map((n) => transform(n, file, names));
  if (node === null || typeof node !== 'object') return node;
  // {$ref, description}: o json-schema-to-typescript criaria um tipo novo (EntityId1, EntityId2…) para
  // cada uso. Fica só o $ref, e o tipo é o da definição citada.
  if ('$ref' in node && Object.keys(node).every((k) => k === '$ref' || ANNOTATIONS.includes(k))) {
    return { $ref: rewriteRef(node.$ref, file, names) };
  }
  const out = {};
  for (const [k, v] of Object.entries(node)) {
    if (k === '$id' || k === '$schema' || k === 'title' || k === '$comment') continue;
    if (k === '$ref') out[k] = rewriteRef(v, file, names);
    else if (SUBSCHEMA.includes(k)) out[k] = transform(v, file, names);
    else if (SUBSCHEMA_LIST.includes(k)) out[k] = v.map((s) => transform(s, file, names));
    else if (SUBSCHEMA_MAP.includes(k)) out[k] = Object.fromEntries(Object.entries(v).map(([p, s]) => [p, transform(s, file, names)]));
    else out[k] = v; // enum, const, default, examples, description…: dados, não schemas
  }
  return out;
}

function buildDocument(schemas, names) {
  const defs = {};
  for (const { file, schema } of schemas) {
    const { $defs = {}, ...root } = schema;
    if (ROOTS[file]) {
      const id = schema.$id;
      const body = transform(root, file, names);
      body.title = ROOTS[file];
      body.description = [`Raiz de ${file} (${id}).`, root.description].filter(Boolean).join('\n\n');
      defs[ROOTS[file]] = body;
    }
    for (const [def, s] of Object.entries($defs)) {
      const name = names.get(`${file}#${def}`);
      const body = transform(s, file, names);
      body.title = name;
      defs[name] = body;
    }
  }
  const sorted = Object.fromEntries(Object.keys(defs).sort().map((k) => [k, defs[k]]));
  return { title: 'VnStudioSchemas', $defs: sorted };
}

const BANNER = `/* eslint-disable */
/**
 * GERADO por sdk/plugin-schema/scripts/generate.mjs a partir de docs/specs/schemas/. NÃO EDITE À MÃO.
 * Para atualizar: npm run generate (na raiz do repositório). A CI falha se este arquivo estiver desatualizado.
 */`;

async function generate() {
  const schemas = loadSchemas();
  const names = assignNames(schemas);
  const doc = buildDocument(schemas, names);
  let ts = await compile(doc, 'VnStudioSchemas', {
    bannerComment: BANNER,
    unreachableDefinitions: true,
    additionalProperties: true,
    strictIndexSignatures: false,
    enableConstEnums: false,
    inferStringEnumKeysFromValues: false,
    declareExternallyReferenced: true,
    format: true,
    style: { singleQuote: true, printWidth: 120 },
    $refOptions: { resolve: { external: false } },
  });
  // A raiz sintética só existe para carregar os $defs: tira a interface vazia dela.
  ts = ts.replace(/\nexport interface VnStudioSchemas \{[\s\S]*?\n\}\n/, '\n');
  for (const [alias, target] of Object.entries(ALIASES)) {
    ts += `\n/** Apelido de ${target}. */\nexport type ${alias} = ${target};\n`;
  }
  return ts.replace(/\r\n/g, '\n');
}

const check = process.argv.includes('--check');
const ts = await generate();
const rel = relative(REPO, OUT).split('\\').join('/');
if (check) {
  // Compara sem CR: com core.autocrlf no Windows o checkout tem CRLF, e isso não é desatualização.
  const current = existsSync(OUT) ? readFileSync(OUT, 'utf8').replace(/\r\n/g, '\n') : '';
  if (current !== ts) {
    console.error(`::error file=${rel}::Tipos desatualizados em relação a docs/specs/schemas/. Rode "npm run generate" na raiz e faça commit de ${rel}.`);
    process.exit(1);
  }
  console.log(`${rel} está em dia com docs/specs/schemas/.`);
} else {
  writeFileSync(OUT, ts);
  console.log(`gerado ${rel}`);
}
