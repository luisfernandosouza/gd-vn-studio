import { create } from 'zustand';
import { immer } from 'zustand/middleware/immer';

/** Estado global do Studio: Zustand + Immer (bibliotecas aceitas em 2026-11-14, README das specs). */
export interface StudioState {
  ready: boolean;
  markReady: () => void;
}

export const useStudioStore = create<StudioState>()(
  immer((set) => ({
    ready: false,
    markReady: () =>
      set((draft) => {
        draft.ready = true;
      }),
  })),
);
