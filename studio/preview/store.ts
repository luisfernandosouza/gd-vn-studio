import { create } from 'zustand';
import type { PreviewSession } from './session';

/**
 * A sessão do Preview aberta no painel. Os editores (M6-02 em diante) chamam
 * `usePreviewStore.getState().session?.update(input)` a cada edição.
 */
export interface PreviewStoreState {
  session: PreviewSession | null;
  setSession: (session: PreviewSession | null) => void;
}

export const usePreviewStore = create<PreviewStoreState>()((set) => ({
  session: null,
  setSession: (session) => set({ session }),
}));
