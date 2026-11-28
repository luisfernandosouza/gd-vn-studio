import { closeDocumentSession } from '../document/session';
import { useT } from '../i18n';
import { useProjectSession } from './session';

/** Resumo do projeto aberto. Os editores (M6-02 em diante) ocupam este lugar. */
export function OpenProjectSummary() {
  const t = useT();
  const current = useProjectSession((s) => s.current);
  const setCurrent = useProjectSession((s) => s.setCurrent);
  if (!current) return null;
  const { project, entities, newerMinor } = current;
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
