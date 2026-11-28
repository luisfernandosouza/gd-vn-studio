/** Modelo de dados em memória do Studio (M6-02): documento lógico, JSON Patch, undo/redo e gravação contínua. */
export { VNError, type VNErrorCode } from './errors';
export {
  cloneDiskState,
  commitSave,
  loadLogicalDocument,
  localeFileFor,
  planSave,
  recoverPendingSave,
  type DiskState,
  type LoadedDocument,
  type LogicalDocument,
  type SavePlan,
} from './logical-document';
export { applyPatch, deepEqual, ENTITY_COLLECTIONS, isForbiddenForPlugin, withTests, type ApplyOptions, type EditSource, type Operation, type PatchResult } from './patch';
export { formatPointer, getValue, parsePointer, resolvePointer } from './pointer';
export {
  createDocumentStore,
  type Command,
  type DocumentGuard,
  type DocumentState,
  type DocumentStore,
  type DocumentStoreOptions,
  type EditOptions,
  type HistoryEntry,
  type SaveStatus,
} from './store';
export { closeDocumentSession, openDocumentSession, useDocumentSession } from './session';
