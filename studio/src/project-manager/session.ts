import { create } from 'zustand';
import { immer } from 'zustand/middleware/immer';
import type { OpenedProject } from './open';

/** Projeto aberto no Studio. O documento lógico em memória fica em `document/session.ts` (M6-02). */
export interface ProjectSessionState {
  current: OpenedProject | null;
  setCurrent: (project: OpenedProject | null) => void;
}

export const useProjectSession = create<ProjectSessionState>()(
  immer((set) => ({
    current: null,
    setCurrent: (project) =>
      set((draft) => {
        draft.current = project;
      }),
  })),
);

const RECENTS_KEY = 'vnstudio.recentProjects';
const MAX_RECENTS = 8;

export interface RecentProject {
  root: string;
  title: string;
}

/** Projetos recentes (só conveniência desta máquina; sem armazenamento, a lista fica vazia). */
export function loadRecents(): RecentProject[] {
  try {
    const raw = localStorage.getItem(RECENTS_KEY);
    const list: unknown = raw ? JSON.parse(raw) : [];
    return Array.isArray(list) ? list.filter((r): r is RecentProject => typeof r?.root === 'string' && typeof r?.title === 'string') : [];
  } catch {
    return [];
  }
}

export function rememberRecent(entry: RecentProject): RecentProject[] {
  const list = [entry, ...loadRecents().filter((r) => r.root !== entry.root)].slice(0, MAX_RECENTS);
  try {
    localStorage.setItem(RECENTS_KEY, JSON.stringify(list));
  } catch {
    // sem armazenamento: a lista vale só nesta sessão
  }
  return list;
}
