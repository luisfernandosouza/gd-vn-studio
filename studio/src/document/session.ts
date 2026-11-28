import { create } from 'zustand';
import type { ProjectFs } from '../project-manager/fs';
import type { OpenedProject } from '../project-manager/open';
import { loadLogicalDocument } from './logical-document';
import { createDocumentStore, type DocumentStore } from './store';

/** O documento do projeto aberto (modelo em memória, undo/redo e autosave). `null` sem projeto aberto. */
export const useDocumentSession = create<{ store: DocumentStore | null }>(() => ({ store: null }));

/** Carrega o documento lógico do projeto recém-aberto e o publica para os editores. */
export async function openDocumentSession(fs: ProjectFs, project: OpenedProject): Promise<DocumentStore> {
  await closeDocumentSession();
  const { doc, disk } = await loadLogicalDocument(fs, project);
  const store = createDocumentStore({ fs, root: project.root, doc, disk });
  useDocumentSession.setState({ store });
  return store;
}

/** Grava o que estiver pendente e solta o documento. */
export async function closeDocumentSession(): Promise<void> {
  const { store } = useDocumentSession.getState();
  useDocumentSession.setState({ store: null });
  await store?.dispose();
}
