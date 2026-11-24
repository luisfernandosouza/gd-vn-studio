/** Project Manager do Studio (M6-01): criar, abrir, migrar e manter o `.gitignore` de um projeto. */
export { createProject, type CreatedProject, type NewProjectOptions } from './create';
export { ProjectManagerError } from './errors';
export { joinPath, listFilesRecursive, type DirEntry, type ProjectFs } from './fs';
export { applyGitignoreBlock, GITIGNORE_BLOCK } from './gitignore';
export { slugify, uniqueName, uuidv7 } from './ids';
export { formatJson } from './json';
export { FORMAT_VERSION, PRODUCT_LOCALES } from './layout';
export { applyMigration, MIGRATORS, planMigration, type FileChange, type MigrationPlan, type Migrator } from './migrate';
export { openProject, type OpenedProject, type OpenOptions, type OpenResult } from './open';
