import { closeDocumentSession } from '../document/session';
import { useProjectSession } from './session';

/** Resumo do projeto aberto. Os editores (M6-02 em diante) ocupam este lugar. */
export function OpenProjectSummary() {
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
          Este projeto foi gravado por um Studio mais novo (formato {project.format_version}). Campos que esta versão não conhece podem se
          perder ao editar; atualize o Studio quando puder.
        </p>
      )}
      <ul>
        <li>{entities.chapters.length} capítulo(s)</li>
        <li>{entities.scenes.length} cena(s)</li>
        <li>{entities.characters.length} personagem(ns)</li>
      </ul>
      <button type="button" onClick={() => {
          void closeDocumentSession().then(() => setCurrent(null));
        }}>
        Fechar projeto
      </button>
    </section>
  );
}
