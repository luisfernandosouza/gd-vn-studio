import './project-manager.css';
import { useState } from 'react';
import { UI_LOCALES, useT, type Params } from '../i18n';
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

const LOCALE_NAMES: Record<string, string> = Object.fromEntries(UI_LOCALES.map((l) => [l.code, l.name]));

function guessLocale(): string {
  const lang = typeof navigator === 'undefined' ? 'en' : navigator.language;
  if ((PRODUCT_LOCALES as readonly string[]).includes(lang)) return lang;
  if (lang.startsWith('pt')) return 'pt-BR';
  if (lang.startsWith('zh')) return /TW|HK|Hant/i.test(lang) ? 'zh-Hant' : 'zh-Hans';
  const base = lang.split('-')[0] ?? 'en';
  return (PRODUCT_LOCALES as readonly string[]).includes(base) ? base : 'en';
}

function describeError(e: unknown, t: (key: string, params?: Params) => string): string {
  if (e instanceof ProjectManagerError) return t(e.key, e.params);
  return t('studio/pm/error/generic', { detail: e instanceof Error ? e.message : String(e) });
}

/** Tela inicial do Studio: novo projeto, abrir projeto, recentes e atualização de formato (M6-01). */
export function ProjectManager({ fs, pickFolder }: ProjectManagerProps) {
  const t = useT();
  const setCurrent = useProjectSession((s) => s.setCurrent);
  const [title, setTitle] = useState('');
  const [locale, setLocale] = useState(guessLocale);
  const [parent, setParent] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [plan, setPlan] = useState<MigrationPlan | null>(null);
  const [confirmed, setConfirmed] = useState(false);
  const [recents, setRecents] = useState<RecentProject[]>(loadRecents);

  const folderName = slugify(title || t('studio/pm/default_name'));
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
      setError(describeError(e, t));
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
        setError(t('studio/error/too_new', { version: result.formatVersion }));
      }
    });

  const create = () =>
    run(async () => {
      if (!target) throw new ProjectManagerError('invalid_title', 'studio/error/choose_folder');
      await createProject(fs, { root: target, title, defaultLocale: locale });
      const result = await openProject(fs, target);
      if (result.status === 'opened') finish(result.project);
    });

  const chooseParent = async () => {
    const folder = await pickFolder(t('studio/pm/pick_parent'));
    if (folder) setParent(folder);
  };

  const chooseProject = async () => {
    const folder = await pickFolder(t('studio/pm/pick_open'));
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
        <h2 id="pm-migrate">{t('studio/pm/migrate/title')}</h2>
        <p>{t('studio/pm/migrate/intro', { from: plan.fromVersion, to: plan.toVersion })}</p>
        <ol>
          {plan.steps.map((s) => (
            <li key={s.from}>
              {s.description}
              {s.destructive && <strong> {t('studio/pm/migrate/destructive_step')}</strong>}
            </li>
          ))}
        </ol>
        <h3>{t('studio/pm/migrate/files_change')}</h3>
        <ul className="pm-changes">
          {plan.changes.map((c) => (
            <li key={c.path}>
              <details>
                <summary>
                  {t(`studio/pm/migrate/${c.kind}`)}: <code>{c.path}</code>
                </summary>
                <div className="pm-diff">
                  <pre aria-label={t('studio/pm/migrate/before')}>{c.before ?? ''}</pre>
                  <pre aria-label={t('studio/pm/migrate/after')}>{c.after ?? ''}</pre>
                </div>
              </details>
            </li>
          ))}
        </ul>
        {plan.destructive && (
          <label>
            <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />{' '}
            {t('studio/pm/migrate/confirm')}
          </label>
        )}
        {error && <p role="alert">{error}</p>}
        <div className="pm-actions">
          <button type="button" onClick={() => setPlan(null)} disabled={busy}>
            {t('studio/pm/migrate/cancel')}
          </button>
          <button type="button" onClick={migrate} disabled={busy || (plan.destructive && !confirmed)}>
            {t('studio/pm/migrate/apply')}
          </button>
        </div>
      </section>
    );
  }

  return (
    <section className="project-manager" aria-labelledby="pm-title">
      <h2 id="pm-title">{t('studio/pm/projects')}</h2>
      <form
        className="pm-new"
        aria-label={t('studio/pm/new_project')}
        onSubmit={(e) => {
          e.preventDefault();
          void create();
        }}
      >
        <h3>{t('studio/pm/new_project')}</h3>
        <label>
          {t('studio/pm/game_name')}
          <input value={title} onChange={(e) => setTitle(e.target.value)} required />
        </label>
        <label>
          {t('studio/pm/writing_language')}
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
            {t('studio/pm/choose_folder')}
          </button>
          <span>{target ? <code>{target}</code> : t('studio/pm/no_folder')}</span>
        </div>
        <button type="submit" disabled={busy || !title.trim() || !target}>
          {t('studio/pm/create')}
        </button>
      </form>
      <div className="pm-open">
        <button type="button" onClick={() => void chooseProject()} disabled={busy}>
          {t('studio/pm/open')}
        </button>
        {recents.length > 0 && (
          <>
            <h3>{t('studio/pm/recents')}</h3>
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
