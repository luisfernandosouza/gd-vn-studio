/** Erro que a tela mostra ao autor como está: `message` já é a frase em linguagem simples (Req §6). */
export class ProjectManagerError extends Error {
  constructor(
    readonly code: 'folder_not_empty' | 'invalid_title' | 'invalid_locale' | 'not_a_project' | 'unreadable' | 'too_new' | 'not_confirmed',
    message: string,
  ) {
    super(message);
    this.name = 'ProjectManagerError';
  }
}
