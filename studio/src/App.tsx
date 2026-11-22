import { useEffect } from 'react';
import { notifyAppReady } from './native';
import { useStudioStore } from './state/studio';

/** Janela vazia do esqueleto (M0-05). Os editores chegam nas tarefas M6. */
export function App() {
  const ready = useStudioStore((s) => s.ready);
  const markReady = useStudioStore((s) => s.markReady);

  useEffect(() => {
    markReady();
    void notifyAppReady();
  }, [markReady]);

  return (
    <main className="app" data-ready={ready}>
      <h1>Visual Novel Studio</h1>
    </main>
  );
}
