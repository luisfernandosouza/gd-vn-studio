import { useEffect, useMemo } from 'react';
import { notifyAppReady } from './native';
import { nativeProjectIo } from './project-manager/native-folder';
import { OpenProjectSummary } from './project-manager/OpenProject';
import { ProjectManager, type ProjectManagerProps } from './project-manager/ProjectManager';
import { useProjectSession } from './project-manager/session';
import { useStudioStore } from './state/studio';

/** Janela do Studio: sem projeto aberto, mostra o Project Manager (M6-01). Os editores chegam nas tarefas M6. */
export function App({ io }: { io?: ProjectManagerProps } = {}) {
  const ready = useStudioStore((s) => s.ready);
  const markReady = useStudioStore((s) => s.markReady);
  const current = useProjectSession((s) => s.current);
  const projectIo = useMemo(() => io ?? nativeProjectIo(), [io]);

  useEffect(() => {
    markReady();
    void notifyAppReady();
  }, [markReady]);

  return (
    <main className="app" data-ready={ready}>
      <h1>Visual Novel Studio</h1>
      {current ? <OpenProjectSummary /> : <ProjectManager fs={projectIo.fs} pickFolder={projectIo.pickFolder} />}
    </main>
  );
}
