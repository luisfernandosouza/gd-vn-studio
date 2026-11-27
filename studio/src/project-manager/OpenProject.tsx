import { useState } from 'react';
import { ProjectSettings } from '../settings/ProjectSettings';
import type { ProjectFs } from './fs';
import { useProjectSession } from './session';

/** Resumo do projeto aberto. Os editores (M6-02 em diante) ocupam este lugar. */
export function OpenProjectSummary({ fs }: { fs: ProjectFs }) {
  const [view, setView] = useState<'summary' | 'settings'>('summary');
  const current = useProjectSession((s) => s.current);
  const setCurrent = useProjectSession((s) => s.setCurrent);
  if (!current) return null;
  const { project, entities, newerMinor } = current;
  if (view === 'settings') {
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
          Este projeto foi gravado por um Studio mais novo (formato {project.format_version}). Campos que esta versão não conhece podem se
          perder ao editar; atualize o Studio quando puder.
        </p>
      )}
      <ul>
        <li>{entities.chapters.length} capítulo(s)</li>
        <li>{entities.scenes.length} cena(s)</li>
        <li>{entities.characters.length} personagem(ns)</li>
      </ul>
      <button type="button" onClick={() => setView('settings')}>
        Configurações do projeto
      </button>
      <button type="button" onClick={() => setCurrent(null)}>
        Fechar projeto
      </button>
    </section>
  );
}
