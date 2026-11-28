import { useState } from 'react';
import { PreviewPanel } from '../../preview/PreviewPanel';
import { closeDocumentSession } from '../document/session';
import { useT } from '../i18n';
import { ProjectSettings } from '../settings/ProjectSettings';
import type { ProjectFs } from './fs';
import { useProjectSession } from './session';

/** Resumo do projeto aberto. Os editores (M6-02 em diante) ocupam este lugar. */
export function OpenProjectSummary({ fs }: { fs?: ProjectFs } = {}) {
  const t = useT();
  const [view, setView] = useState<'summary' | 'settings'>('summary');
  const current = useProjectSession((s) => s.current);
  const setCurrent = useProjectSession((s) => s.setCurrent);
  if (!current) return null;
  const { project, entities, newerMinor } = current;
  if (view === 'settings' && fs) {
    return (
      <>
        <button type="button" onClick={() => setView('summary')}>
          Voltar ao resumo
        </button>
        <ProjectSettings fs={fs} />
      </>
    );
  }
  return (
    <section className="project-manager" aria-labelledby="pm-open-title">
      <h2 id="pm-open-title">{project.title}</h2>
      <p>
        <code>{current.root}</code>
      </p>
      {newerMinor && (
        <p role="status">
          {t('studio/project/newer_minor', { version: project.format_version })}
        </p>
      )}
      <ul>
        <li>{t('studio/project/chapters', { count: entities.chapters.length })}</li>
        <li>{t('studio/project/scenes', { count: entities.scenes.length })}</li>
        <li>{t('studio/project/characters', { count: entities.characters.length })}</li>
      </ul>
      {fs && (
        <button type="button" onClick={() => setView('settings')}>
          Configurações do projeto
        </button>
      )}
      {fs && <PreviewPanel fs={fs} root={current.root} />}
      <button
        type="button"
        onClick={() => {
          void closeDocumentSession().then(() => setCurrent(null));
        }}
      >
        {t('studio/project/close')}
      </button>
    </section>
  );
}
