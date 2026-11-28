import { useEffect, useMemo } from 'react';
import { UI_LOCALES, useI18n, useT } from './i18n';
import { notifyAppReady } from './native';
import { nativeProjectIo } from './project-manager/native-folder';
import { OpenProjectSummary } from './project-manager/OpenProject';
import { ProjectManager, type ProjectManagerProps } from './project-manager/ProjectManager';
import { useProjectSession } from './project-manager/session';
import { useStudioStore } from './state/studio';

/** Janela do Studio: sem projeto aberto, mostra o Project Manager (M6-01). Os editores chegam nas tarefas M6. */
export function App({ io }: { io?: ProjectManagerProps } = {}) {
  const t = useT();
  const locale = useI18n((s) => s.locale);
  const setLocale = useI18n((s) => s.setLocale);
  const ready = useStudioStore((s) => s.ready);
  const markReady = useStudioStore((s) => s.markReady);
  const current = useProjectSession((s) => s.current);
  const projectIo = useMemo(() => io ?? nativeProjectIo(), [io]);

  useEffect(() => {
    markReady();
    void notifyAppReady();
  }, [markReady]);

  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  return (
    <main className="app" data-ready={ready}>
      <h1>Visual Novel Studio</h1>
      <label className="app-language">
        {t('studio/language/label')}
        <select value={locale} onChange={(e) => setLocale(e.target.value as typeof locale)}>
          {UI_LOCALES.map((l) => (
            <option key={l.code} value={l.code} lang={l.code}>
              {l.name}
            </option>
          ))}
        </select>
      </label>
      {current ? <OpenProjectSummary fs={projectIo.fs} /> : <ProjectManager fs={projectIo.fs} pickFolder={projectIo.pickFolder} />}
    </main>
  );
}
