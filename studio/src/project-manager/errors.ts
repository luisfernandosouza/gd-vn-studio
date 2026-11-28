import { translate, type Params } from '../i18n/translate';

/**
 * Erro que a tela mostra ao autor (Req §6). `key` é a chave do texto no catálogo de idiomas do produto e
 * `params` preenche os `{campos}`; a tela traduz para o idioma atual. `message` é a mesma frase em inglês, a fonte.
 */
export class ProjectManagerError extends Error {
  constructor(
    readonly code: 'folder_not_empty' | 'invalid_title' | 'invalid_locale' | 'not_a_project' | 'unreadable' | 'too_new' | 'not_confirmed',
    readonly key: string,
    readonly params?: Params,
  ) {
    super(translate('en', key, params));
    this.name = 'ProjectManagerError';
  }
}
