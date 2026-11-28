import './settings.css';
import type { Project } from '@vnstudio/plugin-schema';
import { produce, type Draft } from 'immer';
import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from 'react';
import { useDocumentSession } from '../document/session';
import type { DocumentStore } from '../document/store';
import type { ProjectFs } from '../project-manager/fs';
import { uniqueName } from '../project-manager/ids';
import { UI_LOCALES } from '../i18n';
import { LOCALE_PATTERN, PRODUCT_LOCALES } from '../project-manager/layout';
import { useProjectSession } from '../project-manager/session';
import { dialogContrast, MIN_CONTRAST } from './contrast';
import { CheckField, LinesField, NumberField, Section, SelectField, TextField } from './fields';
import {
  fieldsToPayload,
  loadSettingsContext,
  PAYLOAD_TYPES,
  payloadToFields,
  prune,
  applyProjectSettings,
  validateSettings,
  type SettingsContext,
  type PayloadType,
} from './model';

const PLATFORMS = [
  ['windows', 'Windows'],
  ['linux', 'Linux'],
  ['macos', 'macOS'],
  ['web', 'Web'],
] as const;

const LOCALE_NAMES: Record<string, string> = Object.fromEntries(UI_LOCALES.map((l) => [l.code, l.name]));
const localeLabel = (l: string) => (LOCALE_NAMES[l] ? `${LOCALE_NAMES[l]} (${l})` : l);
const ratioText = (r: number) => r.toFixed(1).replace('.', ',');

/**
 * Configurações do projeto (M7-10): todas as opções de `project.json` sem editar JSON. Edita uma cópia;
 * "Salvar" confere os valores e grava de forma atômica.
 */
function useDocumentProject(store: DocumentStore | null): Project | undefined {
  return useSyncExternalStore(
    (notify) => (store ? store.subscribe(notify) : () => undefined),
    () => store?.getState().doc.project as Project | undefined,
  );
}

export function ProjectSettings({ fs }: { fs: ProjectFs }) {
  const current = useProjectSession((s) => s.current);
  const setCurrent = useProjectSession((s) => s.setCurrent);
  const store = useDocumentSession((s) => s.store);
  // A fonte da verdade é o documento do projeto (M6-02); sem ele, vale o que o Project Manager abriu.
  const base = useDocumentProject(store) ?? current?.project;
  const [draft, setDraft] = useState<Project | null>(base ?? null);
  const lastBase = useRef(base);
  const [ctx, setCtx] = useState<SettingsContext | null>(null);
  const [status, setStatus] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);
  const [saving, setSaving] = useState(false);
  const [newLocale, setNewLocale] = useState('');

  useEffect(() => {
    if (!current) return;
    let alive = true;
    void loadSettingsContext(fs, current).then((c) => alive && setCtx(c));
    return () => {
      alive = false;
    };
    // só ao abrir: salvar não muda capítulos, assets nem cenas
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fs, current?.root]);

  // Mudança vinda de fora (desfazer, refazer, plugin): sem edição pendente, a tela acompanha o documento.
  useEffect(() => {
    const previous = lastBase.current;
    lastBase.current = base;
    if (!base || base === previous) return;
    setDraft((d) => (d && previous && JSON.stringify(prune(d)) === JSON.stringify(prune(previous)) ? base : d));
  }, [base]);

  const issues = useMemo(() => (draft && ctx ? validateSettings(draft, ctx) : []), [draft, ctx]);
  const dirty = useMemo(() => !!draft && !!base && JSON.stringify(prune(draft)) !== JSON.stringify(prune(base)), [draft, base]);

  if (!current || !draft) return null;
  const edit = (fn: (d: Draft<Project>) => void) => {
    setStatus(null);
    setDraft((p) => (p ? produce(p, fn) : p));
  };

  const locales = draft.locales?.length ? draft.locales : [draft.default_locale];
  const localeChoices = [...new Set([...PRODUCT_LOCALES, ...locales])];
  const setLocales = (next: string[]) =>
    edit((d) => {
      d.locales = next;
    });
  const toggleLocale = (l: string, on: boolean) => setLocales(on ? [...locales, l] : locales.filter((x) => x !== l));
  const display = draft.settings?.display ?? {};
  const settings = draft.settings ?? {};
  const build = draft.build ?? {};
  const orderedChapters = ctx
    ? [...(draft.chapters ?? []).flatMap((id) => ctx.chapters.filter((c) => c.id === id)), ...ctx.chapters.filter((c) => !draft.chapters?.includes(c.id))]
    : [];
  const contrast = dialogContrast(ctx?.theme);
  const assetList = (ctx?.assets ?? []).filter((a) => ['image', 'background', 'sprite'].includes(a.type));

  const save = async () => {
    if (!store) {
      setStatus({ kind: 'error', text: 'O documento do projeto ainda está carregando; tente de novo em instantes.' });
      return;
    }
    setSaving(true);
    try {
      const saved = await applyProjectSettings(store, draft);
      setCurrent({ ...current, project: saved });
      setDraft(saved);
      setStatus({ kind: 'ok', text: 'Configurações salvas em project.json.' });
    } catch (e) {
      setStatus({ kind: 'error', text: `Não foi possível salvar: ${e instanceof Error ? e.message : String(e)}` });
    } finally {
      setSaving(false);
    }
  };

  const setSetting = <K extends keyof NonNullable<Project['settings']>>(key: K, value: NonNullable<Project['settings']>[K] | undefined) =>
    edit((d) => {
      d.settings ??= {};
      if (value === undefined) delete d.settings[key];
      else d.settings[key] = value;
    });
  const setDisplay = <K extends keyof NonNullable<NonNullable<Project['settings']>['display']>>(key: K, value: NonNullable<NonNullable<Project['settings']>['display']>[K] | undefined) =>
    edit((d) => {
      d.settings ??= {};
      d.settings.display ??= {};
      if (value === undefined) delete d.settings.display[key];
      else d.settings.display[key] = value;
    });
  const setBuild = <K extends keyof NonNullable<Project['build']>>(key: K, value: NonNullable<Project['build']>[K] | undefined) =>
    edit((d) => {
      d.build ??= {};
      if (value === undefined) delete d.build[key];
      else d.build[key] = value;
    });
  const resolution = settings.resolution ?? [];
  const setResolutionPart = (i: 0 | 1, v: number | undefined) => {
    const next = [...resolution] as number[];
    next[i] = v ?? 0;
    setSetting('resolution', next.length === 2 && !next.every((n) => !n) ? ([next[0] ?? 0, next[1] ?? 0] as [number, number]) : undefined);
  };

  const assetField = (label: string, value: string | undefined, onChange: (v: string | undefined) => void) => (
    <TextField label={label} value={value} list="ps-assets" hint="ID de um asset do projeto (por exemplo ui/icon)." onChange={(v) => onChange(v.trim() || undefined)} />
  );

  return (
    <section className="project-settings" aria-labelledby="ps-title">
      <h2 id="ps-title">Configurações do projeto</h2>
      <datalist id="ps-assets">
        {assetList.map((a) => (
          <option key={a.id} value={a.id} />
        ))}
      </datalist>

      <Section title="Jogo">
        <TextField label="Título" value={draft.title} onChange={(v) => edit((d) => void (d.title = v))} />
        <TextField label="Identificador do projeto" value={draft.id} hint="Fixado na criação: outros arquivos e saves dependem dele." onChange={() => {}} />
        <TextField label="Versão do jogo" value={draft.version} placeholder="0.1.0" hint="Obrigatória para exportar." onChange={(v) => edit((d) => void (d.version = v.trim() || undefined))} />
        <LinesField label="Autores (um por linha)" value={draft.authors ?? []} onChange={(v) => edit((d) => void (d.authors = v))} />
      </Section>

      <Section title="Idiomas" description="O texto-fonte fica no idioma-fonte; as traduções ficam em locales/<idioma>/ e continuam no disco se você desmarcar um idioma.">
        <SelectField
          label="Idioma-fonte"
          value={draft.default_locale}
          options={localeChoices.map((l) => ({ value: l, label: localeLabel(l) }))}
          onChange={(v) =>
            edit((d) => {
              d.default_locale = v;
              if (d.locales?.length && !d.locales.includes(v)) d.locales.unshift(v);
            })
          }
        />
        <div role="group" aria-label="Idiomas do jogo" className="ps-checks">
          {localeChoices.map((l) => (
            <CheckField key={l} label={localeLabel(l)} checked={locales.includes(l)} onChange={(on) => (l === draft.default_locale ? undefined : toggleLocale(l, on))} hint={l === draft.default_locale ? 'idioma-fonte' : undefined} />
          ))}
        </div>
        <div className="ps-inline">
          <TextField label="Outro idioma (etiqueta BCP 47)" value={newLocale} placeholder="ko, pt-PT…" onChange={setNewLocale} />
          <button
            type="button"
            disabled={!LOCALE_PATTERN.test(newLocale.trim()) || locales.includes(newLocale.trim())}
            onClick={() => {
              setLocales([...locales, newLocale.trim()]);
              setNewLocale('');
            }}
          >
            Adicionar idioma
          </button>
        </div>
      </Section>

      <Section title="Tela e desempenho" description="Padrões do jogo; o jogador pode mudar o que a tela de configurações dele oferecer (UI Spec §8).">
        <div className="ps-inline">
          <NumberField label="Largura base (px)" min={1} value={resolution[0] || undefined} onChange={(v) => setResolutionPart(0, v)} />
          <NumberField label="Altura base (px)" min={1} value={resolution[1] || undefined} onChange={(v) => setResolutionPart(1, v)} />
        </div>
        <div role="group" aria-label="Tamanhos de janela oferecidos" className="ps-list">
          <p>Tamanhos de janela oferecidos ao jogador {display.resolutions ? '' : '(em branco: 1280×720, 1600×900, 1920×1080 e 2560×1440 na proporção da resolução base)'}</p>
          {(display.resolutions ?? []).map((r, i) => (
            <div className="ps-inline" key={i}>
              <NumberField label={`Largura ${i + 1}`} min={1} value={r[0]} onChange={(v) => setDisplay('resolutions', display.resolutions?.map((x, j) => (j === i ? [v ?? 0, x[1] ?? 0] : x)))} />
              <NumberField label={`Altura ${i + 1}`} min={1} value={r[1]} onChange={(v) => setDisplay('resolutions', display.resolutions?.map((x, j) => (j === i ? [x[0] ?? 0, v ?? 0] : x)))} />
              <button type="button" onClick={() => setDisplay('resolutions', display.resolutions?.filter((_, j) => j !== i))}>
                Remover tamanho {i + 1}
              </button>
            </div>
          ))}
          <button type="button" onClick={() => setDisplay('resolutions', [...(display.resolutions ?? []), [1280, 720]])}>
            Adicionar tamanho de janela
          </button>
        </div>
        <SelectField
          label="Modo de tela"
          value={display.display_mode ?? 'windowed'}
          options={[
            { value: 'windowed', label: 'Janela' },
            { value: 'fullscreen', label: 'Tela cheia' },
            { value: 'borderless', label: 'Janela sem borda' },
          ]}
          onChange={(v) => setDisplay('display_mode', v as 'windowed')}
        />
        <CheckField label="Sincronização vertical (vsync)" checked={display.vsync ?? true} onChange={(v) => setDisplay('vsync', v)} />
        <NumberField label="Limite de FPS da novel" min={0} max={360} value={display.fps_limit_vn} hint="0 = sem limite. Em branco: 60." onChange={(v) => setDisplay('fps_limit_vn', v)} />
        <NumberField label="Limite de FPS dos minijogos" min={0} max={360} value={display.fps_limit_activity} hint="0 = sem limite. Em branco: sem limite." onChange={(v) => setDisplay('fps_limit_activity', v)} />
      </Section>

      <Section title="Texto, salvamento e sorteios">
        <NumberField label="Velocidade do texto (caracteres por segundo)" min={0} value={settings.text_speed} hint="0 = instantâneo. Em branco: 40." onChange={(v) => setSetting('text_speed', v)} />
        <NumberField label="Pausa do modo automático (segundos)" min={0} step={0.1} value={settings.auto_delay} hint="Em branco: 1,5." onChange={(v) => setSetting('auto_delay', v)} />
        <SelectField
          label="Salvamento automático"
          value={settings.autosave ?? ''}
          options={[
            { value: '', label: 'Padrão do runtime' },
            { value: 'off', label: 'Desligado' },
            { value: 'scene_start', label: 'No início de cada cena' },
            { value: 'selection_point', label: 'A cada ponto de seleção' },
          ]}
          onChange={(v) => setSetting('autosave', (v || undefined) as 'off' | undefined)}
        />
        <NumberField label="Tempo máximo de uma atividade de plugin (segundos)" min={1} value={settings.activity_timeout_seconds} hint="Em branco: sem limite. Ao estourar, a atividade falha e segue o caminho de erro." onChange={(v) => setSetting('activity_timeout_seconds', v)} />
        <CheckField
          label="Sorteios reproduzíveis"
          checked={settings.reproducible_rng ?? false}
          hint="Ligado, todo sorteio usa o gerador reproduzível: o estado entra no save e o Preview repete o mesmo traço do jogo exportado. Desligado, o sorteio é comum e não entra no save."
          onChange={(v) => setSetting('reproducible_rng', v || undefined)}
        />
        <div role="group" aria-label="Formato de números por idioma" className="ps-list">
          <p>Formato de números por idioma (só para idiomas fora da tabela do runtime)</p>
          {Object.entries(settings.number_formats ?? {}).map(([loc, f]) => {
            const update = (patch: Partial<typeof f>) => setSetting('number_formats', { ...settings.number_formats, [loc]: { ...f, ...patch } });
            return (
              <div className="ps-inline" key={loc}>
                <strong>{loc}</strong>
                <TextField label={`Separador decimal (${loc})`} value={f.decimal} onChange={(v) => update({ decimal: v })} />
                <TextField label={`Separador de milhar (${loc})`} value={f.group} hint="Vazio = sem separador." onChange={(v) => update({ group: v })} />
                <NumberField label={`Mínimo de dígitos para agrupar (${loc})`} min={4} max={9} value={f.min_grouping} onChange={(v) => update({ min_grouping: v })} />
                <button
                  type="button"
                  onClick={() => {
                    const rest = { ...settings.number_formats };
                    delete rest[loc];
                    setSetting('number_formats', rest);
                  }}
                >
                  Remover formato de {loc}
                </button>
              </div>
            );
          })}
          {locales.filter((l) => !settings.number_formats?.[l]).map((l) => (
            <button key={l} type="button" onClick={() => setSetting('number_formats', { ...settings.number_formats, [l]: { decimal: ',', group: '.' } })}>
              Definir formato de números para {l}
            </button>
          ))}
        </div>
      </Section>

      <Section title="Capítulos e seleção de cenas">
        <SelectField
          label="Capítulo inicial"
          value={draft.start_chapter}
          options={ctx?.chapters.length ? ctx.chapters.map((c) => ({ value: c.id, label: c.title })) : [{ value: draft.start_chapter, label: draft.start_chapter }]}
          onChange={(v) => edit((d) => void (d.start_chapter = v))}
        />
        <div role="group" aria-label="Ordem dos capítulos" className="ps-list">
          <p>Ordem de autoria dos capítulos (desempate final da seleção)</p>
          <ol>
            {orderedChapters.map((c, i) => {
              const move = (by: -1 | 1) => {
                const ids = orderedChapters.map((x) => x.id);
                const [item] = ids.splice(i, 1);
                ids.splice(i + by, 0, item as string);
                edit((d) => void (d.chapters = ids));
              };
              return (
                <li key={c.id}>
                  {c.title}{' '}
                  <button type="button" disabled={i === 0} onClick={() => move(-1)} aria-label={`Subir ${c.title}`}>
                    ↑
                  </button>
                  <button type="button" disabled={i === orderedChapters.length - 1} onClick={() => move(1)} aria-label={`Descer ${c.title}`}>
                    ↓
                  </button>
                </li>
              );
            })}
          </ol>
        </div>
        <SelectField
          label="Desempate entre cenas candidatas"
          value={draft.scheduler?.tie_breaker ?? 'deterministic'}
          hint="Com sorteio ponderado, só é reproduzível com “Sorteios reproduzíveis” ligado."
          options={[
            { value: 'deterministic', label: 'Determinístico (padrão)' },
            { value: 'weighted_random', label: 'Sorteio ponderado' },
          ]}
          onChange={(v) =>
            edit((d) => {
              d.scheduler ??= {};
              d.scheduler.tie_breaker = v as 'deterministic';
            })
          }
        />
        <CheckField
          label="Cenas sem capítulo entram na seleção"
          checked={draft.scheduler?.include_global_scenes ?? true}
          onChange={(v) =>
            edit((d) => {
              d.scheduler ??= {};
              d.scheduler.include_global_scenes = v;
            })
          }
        />
        <div role="group" aria-label="Grupos de exclusividade" className="ps-list">
          <p>Grupos de exclusividade (vivem o jogo inteiro)</p>
          {(draft.exclusive_groups ?? []).map((g, i) => (
            <div className="ps-inline" key={i}>
              <TextField label={`Identificador do grupo ${i + 1}`} value={g.id} onChange={(v) => edit((d) => void (d.exclusive_groups![i]!.id = v))} />
              <TextField label={`Descrição do grupo ${i + 1}`} value={g.description} onChange={(v) => edit((d) => void (d.exclusive_groups![i]!.description = v))} />
              <NumberField label={`Máximo de execuções do grupo ${i + 1}`} min={1} value={g.max_plays} hint="Em branco: 1." onChange={(v) => edit((d) => void (d.exclusive_groups![i]!.max_plays = v))} />
              <button type="button" onClick={() => edit((d) => void d.exclusive_groups!.splice(i, 1))}>
                Remover grupo {i + 1}
              </button>
            </div>
          ))}
          <button type="button" onClick={() => edit((d) => void (d.exclusive_groups = [...(d.exclusive_groups ?? []), { id: uniqueName('grupo', (d.exclusive_groups ?? []).map((g) => g.id)) }]))}>
            Adicionar grupo
          </button>
        </div>
      </Section>

      <Section title="Finais" description="Todo nó de fim de jogo escolhe um destes finais. Eles alimentam a galeria de finais.">
        {(draft.endings ?? []).map((e, i) => {
          const used = ctx?.endingUsage[e.id]?.length ?? 0;
          return (
            <div className="ps-ending" key={i} role="group" aria-label={`Final ${i + 1}`}>
              <TextField label={`Título do final ${i + 1}`} value={e.title} onChange={(v) => edit((d) => void (d.endings![i]!.title = v))} />
              <TextField label={`Identificador do final ${i + 1}`} value={e.id} hint={used ? `Usado em ${used} cena(s).` : undefined} onChange={(v) => edit((d) => void (d.endings![i]!.id = v))} />
              <TextField label={`Descrição do final ${i + 1}`} value={e.description} onChange={(v) => edit((d) => void (d.endings![i]!.description = v))} />
              {assetField(`Imagem do final ${i + 1}`, e.image, (v) => edit((d) => void (d.endings![i]!.image = v)))}
              <NumberField label={`Ordem na galeria do final ${i + 1}`} value={e.order} onChange={(v) => edit((d) => void (d.endings![i]!.order = v))} />
              <button type="button" onClick={() => edit((d) => void d.endings!.splice(i, 1))}>
                Remover final {i + 1}
              </button>
            </div>
          );
        })}
        <button
          type="button"
          onClick={() =>
            edit((d) => {
              const id = uniqueName('final', (d.endings ?? []).map((x) => x.id));
              d.endings = [...(d.endings ?? []), { id, title: 'Novo final' }];
            })
          }
        >
          Adicionar final
        </button>
      </Section>

      <Section title="Modo stream (versão censurada)" description="O jogador liga o filtro na tela de configurações; o conteúdo é marcado nos assets e nas cenas.">
        <CheckField label="Começar com o modo stream ligado" checked={draft.content_filter?.default ?? false} onChange={(v) => edit((d) => void ((d.content_filter ??= {}).default = v || undefined))} />
        <CheckField
          label="Perguntar na primeira vez que o jogo abre"
          checked={draft.content_filter?.ask_on_first_launch ?? false}
          hint="Sem este aviso, sem controle nas telas e sem “começar ligado”, o validador avisa que o modo stream não tem como ser ligado."
          onChange={(v) => edit((d) => void ((d.content_filter ??= {}).ask_on_first_launch = v || undefined))}
        />
        {assetField('Imagem neutra no lugar de conteúdo escondido', draft.content_filter?.placeholder, (v) => edit((d) => void ((d.content_filter ??= {}).placeholder = v)))}
      </Section>

      <Section title="Galeria">
        <CheckField
          label="O jogo tem galeria"
          checked={!!draft.gallery}
          hint="Sem galeria, a tela do preset não entra e o botão do título some."
          onChange={(on) => edit((d) => void (d.gallery = on ? { sections: ['endings', 'images', 'music'] } : undefined))}
        />
        {draft.gallery && (
          <div role="group" aria-label="Seções da galeria" className="ps-checks">
            {(
              [
                ['endings', 'Finais'],
                ['images', 'Imagens'],
                ['music', 'Músicas'],
              ] as const
            ).map(([key, label]) => (
              <CheckField
                key={key}
                label={label}
                checked={draft.gallery!.sections.includes(key)}
                onChange={(on) => edit((d) => void (d.gallery!.sections = (['endings', 'images', 'music'] as const).filter((k) => (k === key ? on : d.gallery!.sections.includes(k))) as NonNullable<typeof d.gallery>['sections']))}
              />
            ))}
          </div>
        )}
      </Section>

      <Section title="Eventos da história" description="Eventos story.* que as cenas emitem e testam; os não declarados geram aviso.">
        {(draft.events ?? []).map((ev, i) => {
          const fields = payloadToFields(ev.payload);
          const setFields = (next: NonNullable<typeof fields>) => edit((d) => void (d.events![i]!.payload = fieldsToPayload(next)));
          return (
            <div className="ps-ending" key={i} role="group" aria-label={`Evento ${i + 1}`}>
              <TextField label={`Nome do evento ${i + 1}`} value={ev.name} placeholder="story.met_master" onChange={(v) => edit((d) => void (d.events![i]!.name = v))} />
              <TextField label={`Descrição do evento ${i + 1}`} value={ev.description} onChange={(v) => edit((d) => void (d.events![i]!.description = v))} />
              {fields === null ? (
                <p className="ps-desc">Este evento tem um payload avançado (JSON Schema além de campos simples). Ele é preservado ao salvar.</p>
              ) : (
                <>
                  {fields.map((f, j) => (
                    <div className="ps-inline" key={j}>
                      <TextField label={`Campo ${j + 1} do evento ${i + 1}`} value={f.name} onChange={(v) => setFields(fields.map((x, k) => (k === j ? { ...x, name: v } : x)))} />
                      <SelectField
                        label={`Tipo do campo ${j + 1} do evento ${i + 1}`}
                        value={f.type}
                        options={PAYLOAD_TYPES.map((t) => ({ value: t, label: { string: 'Texto', integer: 'Inteiro', number: 'Número', boolean: 'Sim/não' }[t] }))}
                        onChange={(v) => setFields(fields.map((x, k) => (k === j ? { ...x, type: v as PayloadType } : x)))}
                      />
                      <CheckField label={`Obrigatório (campo ${j + 1})`} checked={f.required} onChange={(v) => setFields(fields.map((x, k) => (k === j ? { ...x, required: v } : x)))} />
                      <button type="button" onClick={() => setFields(fields.filter((_, k) => k !== j))}>
                        Remover campo {j + 1}
                      </button>
                    </div>
                  ))}
                  <button type="button" onClick={() => setFields([...fields, { name: uniqueName('campo', fields.map((f) => f.name)), type: 'string', required: false }])}>
                    Adicionar campo ao evento {i + 1}
                  </button>
                </>
              )}
              <button type="button" onClick={() => edit((d) => void d.events!.splice(i, 1))}>
                Remover evento {i + 1}
              </button>
            </div>
          );
        })}
        <button type="button" onClick={() => edit((d) => void (d.events = [...(d.events ?? []), { name: uniqueName('story.evento', (d.events ?? []).map((e) => e.name)) }]))}>
          Adicionar evento
        </button>
      </Section>

      <Section title="Exportação">
        <TextField label="Nome do executável" value={build.executable_name} hint="Em branco: derivado do título." onChange={(v) => setBuild('executable_name', v || undefined)} />
        <TextField label="Empresa ou equipe" value={build.company} onChange={(v) => setBuild('company', v || undefined)} />
        {assetField('Ícone do executável', build.icon, (v) => setBuild('icon', v))}
        {assetField('Imagem de abertura', build.splash, (v) => setBuild('splash', v))}
        <div role="group" aria-label="Plataformas" className="ps-checks">
          {PLATFORMS.map(([key, label]) => (
            <CheckField key={key} label={label} checked={build.platforms?.includes(key) ?? false} onChange={(on) => setBuild('platforms', PLATFORMS.map(([k]) => k).filter((k) => (k === key ? on : build.platforms?.includes(k))) as typeof build.platforms)} />
          ))}
        </div>
        <CheckField
          label="Incluir todos os idiomas do jogo no build"
          checked={!build.locales}
          onChange={(all) => setBuild('locales', all ? undefined : (locales as [string, ...string[]]))}
        />
        {build.locales && (
          <div role="group" aria-label="Idiomas do build" className="ps-checks">
            {locales.map((l) => (
              <CheckField
                key={l}
                label={localeLabel(l)}
                checked={build.locales!.includes(l)}
                onChange={(on) => setBuild('locales', locales.filter((x) => (x === l ? on : build.locales!.includes(x))) as [string, ...string[]])}
              />
            ))}
          </div>
        )}
        <SelectField
          label="Compressão das imagens"
          value={build.textures ?? 'lossless'}
          options={[
            { value: 'lossless', label: 'Sem perda (padrão)' },
            { value: 'lossy', label: 'Com perda, WebP (menor; indicado para Web)' },
          ]}
          onChange={(v) => setBuild('textures', v === 'lossless' ? undefined : (v as 'lossy'))}
        />
        <SelectField
          label="Edição"
          value={build.edition ?? 'standard'}
          hint="A censurada deixa o filtro sempre ligado, esconde o controle e não leva os originais no pacote."
          options={[
            { value: 'standard', label: 'Padrão' },
            { value: 'censored', label: 'Censurada' },
          ]}
          onChange={(v) => setBuild('edition', v === 'standard' ? undefined : (v as 'censored'))}
        />
        <CheckField label="Permitir abrir links (ação open_url)" checked={build.allow_urls ?? true} hint="Sempre pede confirmação ao jogador." onChange={(v) => setBuild('allow_urls', v ? undefined : false)} />
        <CheckField
          label="Cifrar o PCK (avançado)"
          checked={build.protection?.encrypt_pck ?? false}
          onChange={(v) => edit((d) => void (((d.build ??= {}).protection ??= {}).encrypt_pck = v || undefined))}
        />
        <SelectField
          label="Save ou perfil com assinatura que não confere"
          value={build.protection?.save_tamper ?? 'flag'}
          options={[
            { value: 'ignore', label: 'Ignorar' },
            { value: 'flag', label: 'Marcar (padrão)' },
            { value: 'reject', label: 'Rejeitar' },
          ]}
          onChange={(v) => edit((d) => void (((d.build ??= {}).protection ??= {}).save_tamper = v === 'flag' ? undefined : (v as 'ignore')))}
        />
        <TextField label="Perfil de assinatura no Windows" value={build.signing?.windows} hint="Nome de um perfil guardado no cofre do sistema; credenciais nunca ficam no projeto." onChange={(v) => edit((d) => void (((d.build ??= {}).signing ??= {}).windows = v || undefined))} />
        <TextField label="Perfil de assinatura no macOS" value={build.signing?.macos} onChange={(v) => edit((d) => void (((d.build ??= {}).signing ??= {}).macos = v || undefined))} />
        {build.protection?.save_key_id && <p className="ps-desc">Impressão digital da chave de saves: {build.protection.save_key_id} (gravada pelo Studio no primeiro build de release).</p>}
      </Section>

      <Section title="Versão do runtime">
        <TextField label="Versão mínima do runtime" value={draft.runtime?.min_version} onChange={(v) => edit((d) => void ((d.runtime ??= {}).min_version = v.trim() || undefined))} />
        <TextField label="Faixa de versões do Godot" value={draft.runtime?.godot} hint="Por exemplo >=4.7.0 <5.0.0. O build falha se o Godot do Studio estiver fora da faixa." onChange={(v) => edit((d) => void ((d.runtime ??= {}).godot = v.trim() || undefined))} />
        <TextField label="Arquivo de tema" value={draft.theme} placeholder="theme.json" hint="Caminho relativo à pasta do projeto. Em branco: theme.json, ou o preset classic se não existir." onChange={(v) => edit((d) => void (d.theme = v.trim() || undefined))} />
      </Section>

      <Section title="Acessibilidade" description="O jogo exportado já traz o mínimo do v1 (Req §12) sem trabalho seu: tamanho do texto de 80% a 200%, texto instantâneo, redução de movimento, legendas, menus por teclado ou gamepad e alto contraste na caixa de diálogo.">
        {contrast ? (
          contrast.ok ? (
            <p role="status" className="ps-ok">
              Contraste do texto ({contrast.text}) sobre o painel ({contrast.panel}): {ratioText(contrast.ratio)}:1, acima do mínimo de {ratioText(MIN_CONTRAST)}:1.
            </p>
          ) : (
            <p role="alert" className="ps-warn">
              Contraste baixo: o texto ({contrast.text}) sobre o painel ({contrast.panel}) dá {ratioText(contrast.ratio)}:1, abaixo do mínimo de {ratioText(MIN_CONTRAST)}:1. Escureça o painel ou clareie o texto no tema; com “alto contraste” ligado, o jogador recebe fundo opaco, mas o ideal é que o padrão já passe.
            </p>
          )
        ) : (
          <p role="status">Não foi possível calcular o contraste: as cores do tema (colors.text e colors.panel) não estão no formato #rrggbb ou #rrggbbaa.</p>
        )}
        <p className="ps-desc">A conta considera o painel translúcido sobre cena toda preta ou toda branca e usa o pior caso.</p>
      </Section>

      <div className="ps-actions" role="group" aria-label="Salvar">
        {issues.length > 0 && (
          <ul role="alert" className="ps-issues">
            {issues.map((i, k) => (
              <li key={k}>
                <strong>{i.field}:</strong> {i.message}
              </li>
            ))}
          </ul>
        )}
        <button type="button" onClick={() => void save()} disabled={!dirty || issues.length > 0 || saving || !ctx}>
          Salvar configurações
        </button>
        <button
          type="button"
          disabled={!dirty || saving}
          onClick={() => {
            setDraft(base ?? current.project);
            setStatus(null);
          }}
        >
          Descartar mudanças
        </button>
        {dirty && <span>Há mudanças não salvas.</span>}
        {status && <p role={status.kind === 'error' ? 'alert' : 'status'}>{status.text}</p>}
      </div>
    </section>
  );
}
