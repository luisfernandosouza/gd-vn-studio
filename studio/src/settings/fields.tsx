import { useId, useState, type ReactNode } from 'react';

/** Campos de formulário do painel de configurações: rótulo ligado ao controle e dica opcional. */
interface BaseProps {
  label: string;
  hint?: ReactNode;
}

function Wrap({ label, hint, id, children }: BaseProps & { id: string; children: ReactNode }) {
  return (
    <div className="ps-field">
      <label htmlFor={id}>{label}</label>
      {children}
      {hint && <small id={`${id}-hint`}>{hint}</small>}
    </div>
  );
}

export function TextField({ label, hint, value, onChange, placeholder, list }: BaseProps & { value: string | undefined; onChange: (v: string) => void; placeholder?: string; list?: string }) {
  const id = useId();
  return (
    <Wrap label={label} hint={hint} id={id}>
      <input id={id} type="text" value={value ?? ''} placeholder={placeholder} list={list} aria-describedby={hint ? `${id}-hint` : undefined} onChange={(e) => onChange(e.target.value)} />
    </Wrap>
  );
}

/** Número opcional: campo em branco vira `undefined` (a opção volta ao padrão). */
export function NumberField({ label, hint, value, onChange, min, max, step }: BaseProps & { value: number | undefined; onChange: (v: number | undefined) => void; min?: number; max?: number; step?: number }) {
  const id = useId();
  return (
    <Wrap label={label} hint={hint} id={id}>
      <input
        id={id}
        type="number"
        value={value ?? ''}
        min={min}
        max={max}
        step={step}
        aria-describedby={hint ? `${id}-hint` : undefined}
        onChange={(e) => onChange(e.target.value === '' ? undefined : Number(e.target.value))}
      />
    </Wrap>
  );
}

export function CheckField({ label, hint, checked, onChange }: BaseProps & { checked: boolean; onChange: (v: boolean) => void }) {
  const id = useId();
  return (
    <div className="ps-field ps-check">
      <label htmlFor={id}>
        <input id={id} type="checkbox" checked={checked} aria-describedby={hint ? `${id}-hint` : undefined} onChange={(e) => onChange(e.target.checked)} /> {label}
      </label>
      {hint && <small id={`${id}-hint`}>{hint}</small>}
    </div>
  );
}

export interface Option {
  value: string;
  label: string;
}

export function SelectField({ label, hint, value, options, onChange }: BaseProps & { value: string; options: readonly Option[]; onChange: (v: string) => void }) {
  const id = useId();
  return (
    <Wrap label={label} hint={hint} id={id}>
      <select id={id} value={value} aria-describedby={hint ? `${id}-hint` : undefined} onChange={(e) => onChange(e.target.value)}>
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </Wrap>
  );
}

/** Um item por linha (autores). O texto fica local para a linha em branco recém-digitada não sumir. */
export function LinesField({ label, hint, value, onChange }: BaseProps & { value: readonly string[]; onChange: (v: string[]) => void }) {
  const id = useId();
  const [text, setText] = useState(value.join('\n'));
  return (
    <Wrap label={label} hint={hint} id={id}>
      <textarea
        id={id}
        rows={3}
        value={text}
        aria-describedby={hint ? `${id}-hint` : undefined}
        onChange={(e) => {
          setText(e.target.value);
          onChange(e.target.value.split('\n').map((l) => l.trim()).filter(Boolean));
        }}
      />
    </Wrap>
  );
}

export function Section({ title, children, description }: { title: string; description?: ReactNode; children: ReactNode }) {
  return (
    <fieldset className="ps-section">
      <legend>{title}</legend>
      {description && <p className="ps-desc">{description}</p>}
      {children}
    </fieldset>
  );
}
