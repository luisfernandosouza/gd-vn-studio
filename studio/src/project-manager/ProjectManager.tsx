import './project-manager.css';
import { useState } from 'react';
import { createProject } from './create';
import { ProjectManagerError } from './errors';
import { joinPath, type ProjectFs } from './fs';
import { slugify } from './ids';
import { PRODUCT_LOCALES } from './layout';
import { applyMigration, type MigrationPlan } from './migrate';
import { openProject, type OpenedProject } from './open';
import { loadRecents, rememberRecent, useProjectSession, type RecentProject } from './session';

export interface ProjectManagerProps {
  fs: ProjectFs;
  /** Abre o seletor de pasta do sistema; `null` se o autor cancelar. */
  pickFolder: (title: string) => Promise<string | null>;
}

const LOCALE_NAMES: Record<string, string> = {
  'pt-BR': 'Português (Brasil)',
  en: 'English',
  es: 'Español',
  fr: 'Français',
  it: 'Italiano',
  de: 'Deutsch',
  ja: '日本語',
  'zh-Hans': '简体中文',
  'zh-Hant': '繁體中文',
};

function guessLocale(): string {
  const lang = typeof navigator === 'undefined' ? 'en' : navigator.language;
  if ((PRODUCT_LOCALES as readonly string[]).includes(lang)) return lang;
  if (lang.startsWith('pt')) return 'pt-BR';
  if (lang.startsWith('zh')) return /TW|HK|Hant/i.test(lang) ? 'zh-Hant' : 'zh-Hans';
  const base = lang.split('-')[0] ?? 'en';
  return (PRODUCT_LOCALES as readonly string[]).includes(base) ? base : 'en';
}

function describeError(e: unknown): string {
  if (e instanceof ProjectManagerError) return e.message;
  return `Não foi possível concluir: ${e instanceof Error ? e.message : String(e)}`;
}

/** Tela inicial do Studio: novo projeto, abrir projeto, recentes e atualização de formato (M6-01). */
export function ProjectManager({ fs, pickFolder }: ProjectManagerProps) {
  const setCurrent = useProjectSession((s) => s.setCurrent);
  const [title, setTitle] = useState('');
  const [locale, setLocale] = useState(guessLocale);
  const [parent, setParent] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [plan, setPlan] = useState<MigrationPlan | null>(null);
  const [confirmed, setConfirmed] = useState(false);
  const [recents, setRecents] = useState<RecentProject[]>(loadRecents);

  const folderName = slugify(title || 'meu jogo');
  const target = parent ? joinPath(parent, folderName) : null;

  const finish = (project: OpenedProject) => {
    setRecents(rememberRecent({ root: project.root, title: project.project.title }));
    setCurrent(project);
  };

  const run = async (task: () => Promise<void>) => {
    setBusy(true);
    setError(null);
    try {
      await task();
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  const open = (root: string) =>
    run(async () => {
      const result = await openProject(fs, root);
      if (result.status === 'opened') finish(result.project);
      else if (result.status === 'needs_migration') {
        setConfirmed(false);
        setPlan(result.plan);
      } else {
        setError(`Este projeto foi feito numa versão mais nova do Studio (formato ${result.formatVersion}). Atualize o Visual Novel Studio para abri-lo.`);
      }
    });

  const create = () =>
    run(async () => {
      if (!target) throw new ProjectManagerError('invalid_title', 'Escolha onde criar o projeto.');
      await createProject(fs, { root: target, title, defaultLocale: locale });
      const result = await openProject(fs, target);
      if (result.status === 'opened') finish(result.project);
    });

  const chooseParent = async () => {
    const folder = await pickFolder('Onde criar o projeto');
    if (folder) setParent(folder);
  };

  const chooseProject = async () => {
    const folder = await pickFolder('Abrir projeto');
    if (folder) await open(folder);
  };

  const migrate = () =>
    run(async () => {
      if (!plan) return;
      await applyMigration(fs, plan, { confirmed });
      setPlan(null);
      await open(plan.root);
    });

  if (plan) {
    return (
      <section className="project-manager" aria-labelledby="pm-migrate">
        <h2 id="pm-migrate">Atualizar o projeto</h2>
        <p>
          Este projeto usa o formato {plan.fromVersion}, e este Studio usa o {plan.toVersion}. Antes de gravar, o Studio guarda uma
          cópia de todos os arquivos em <code>.vnstudio/backups/</code>.
        </p>
        <ol>
          {plan.steps.map((s) => (
            <li key={s.from}>
              {s.description}
              {s.destructive && <strong> (apaga dados)</strong>}
            </li>
          ))}
        </ol>
        <h3>Arquivos que mudam</h3>
        <ul className="pm-changes">
          {plan.changes.map((c) => (
            <li key={c.path}>
              <details>
                <summary>
                  {c.kind === 'added' ? 'Novo' : c.kind === 'removed' ? 'Apagado' : 'Alterado'}: <code>{c.path}</code>
                </summary>
                <div className="pm-diff">
                  <pre aria-label="Antes">{c.before ?? ''}</pre>
                  <pre aria-label="Depois">{c.after ?? ''}</pre>
                </div>
              </details>
            </li>
          ))}
        </ul>
        {plan.destructive && (
          <label>
            <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} /> Entendo que esta atualização
            apaga dados do projeto e que a cópia fica em .vnstudio/backups/
          </label>
        )}
        {error && <p role="alert">{error}</p>}
        <div className="pm-actions">
          <button type="button" onClick={() => setPlan(null)} disabled={busy}>
            Cancelar
          </button>
          <button type="button" onClick={migrate} disabled={busy || (plan.destructive && !confirmed)}>
            Atualizar projeto
          </button>
        </div>
      </section>
    );
  }

  return (
    <section className="project-manager" aria-labelledby="pm-title">
      <h2 id="pm-title">Projetos</h2>
      <form
        className="pm-new"
        aria-label="Novo projeto"
        onSubmit={(e) => {
          e.preventDefault();
          void create();
        }}
      >
        <h3>Novo projeto</h3>
        <label>
          Nome do jogo
          <input value={title} onChange={(e) => setTitle(e.target.value)} required />
        </label>
        <label>
          Idioma em que você escreve
          <select value={locale} onChange={(e) => setLocale(e.target.value)}>
            {PRODUCT_LOCALES.map((l) => (
              <option key={l} value={l}>
                {LOCALE_NAMES[l] ?? l}
              </option>
            ))}
          </select>
        </label>
        <div className="pm-folder">
          <button type="button" onClick={() => void chooseParent()} disabled={busy}>
            Escolher pasta…
          </button>
          <span>{target ? <code>{target}</code> : 'Nenhuma pasta escolhida'}</span>
        </div>
        <button type="submit" disabled={busy || !title.trim() || !target}>
          Criar projeto
        </button>
      </form>
      <div className="pm-open">
        <button type="button" onClick={() => void chooseProject()} disabled={busy}>
          Abrir projeto…
        </button>
        {recents.length > 0 && (
          <>
            <h3>Recentes</h3>
            <ul>
              {recents.map((r) => (
                <li key={r.root}>
                  <button type="button" className="pm-recent" onClick={() => void open(r.root)} disabled={busy}>
                    {r.title} <small>{r.root}</small>
                  </button>
                </li>
              ))}
            </ul>
          </>
        )}
      </div>
      {error && <p role="alert">{error}</p>}
    </section>
  );
}
