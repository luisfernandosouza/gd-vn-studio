/**
 * Mensagens em linguagem simples (Req §6): uma frase por código, com os parâmetros preenchidos.
 *
 * O texto técnico, igual ao do validador de referência, fica em `Diagnostic.detail` ("Detalhes" no Studio).
 * O Studio troca `onde` (arquivo#id) por títulos e nomes curtos ao mostrar a mensagem (M6-03).
 */

export type Params = Record<string, string | number>;

type Template = string | ((p: Params) => string);

/** Modelos da tabela do Req §6, usados quando o validador passa os parâmetros. */
const TEMPLATES: Record<string, Template> = {
  R004: 'A imagem ou som "{asset}" usado em {onde} não está mais no projeto.',
  R005: '{onde} usa a variável "{variavel}", que não existe ou não vale aqui.',
  R006: '{onde} aponta para uma cena que foi apagada.',
  R009: 'Um passo em {onde} leva a outro passo que foi apagado.',
  R012: 'O final "{final}" não está na lista de finais do jogo.',
  T001: '"{variavel}" guarda {tipo}, mas recebeu {valor}.',
  P008: 'O plugin "{plugin}" pode alterar "{variavel}", mas a variável não aceita alterações de plugins.',
  W001: 'Este passo nunca é alcançado.',
  W007: 'O plugin "{plugin}" não deu nome legível a "{campo}".',
  W008: 'O plugin "{plugin}" não foi testado para {plataforma}. O jogo pode funcionar mal nessa plataforma.',
  P013: 'O plugin "{plugin}" está ligado a uma pasta de desenvolvimento. Peça ao desenvolvedor o arquivo .vnplugin antes de exportar.',
  R014: '{onde} leva a uma cena de outro capítulo. Para mudar de capítulo, termine este capítulo e escolha o próximo.',
  R015: 'O grupo "{grupo}" existe no jogo inteiro e também no capítulo {capitulo}. Use nomes diferentes.',
  W010: 'A cena de reserva do capítulo {capitulo} não muda nada que faça o capítulo terminar. O jogo pode ficar repetindo essa cena.',
  W013: 'Este passo está incompleto: {motivo}.',
  R019: 'O texto de {onde} mostra "{variavel}", que não existe ou não vale aqui. O jogador veria o texto quebrado.',
  R020: '{onde} anuncia um acontecimento que não é da história ({evento}). Só acontecimentos da história podem ser anunciados pelas cenas.',
  T006: '"{variavel}" guarda {tipo}, mas recebe aqui um valor de outro tipo.',
  U001: '{onde} usa "{alvo}", que não existe mais nesta tela ou cenário.',
  U003: 'O elemento {onde} do menu inicial depende de "{variavel}", que só existe durante uma partida. Use uma variável de perfil ou de finais.',
  U004: '{onde} faz "{acao}", mas essa ação não vale nesse lugar.',
  U006: '{onde}: a tela não tem como seguir adiante (o menu inicial precisa de "Novo jogo", a pausa de um botão para voltar).',
  W017: '"{variavel}" guarda números inteiros; o resultado da conta será cortado (ex.: 3,7 vira 3). Use "arredondar" para deixar claro.',
};

/** Frase geral de cada código (Data Model §11, UI Spec §11, spec 09 §5), para quando não há modelo com parâmetros. */
const GENERIC: Record<string, string> = {
  S000: 'O arquivo {onde} não está no formato esperado: {detalhe}.',
  R001: 'Dois itens do projeto usam o mesmo identificador ({onde}).',
  R002: 'A mesma variável foi criada duas vezes ({onde}).',
  R003: 'O personagem em {onde} dá valor inicial a uma variável de personagem que não existe.',
  R004: 'Uma imagem, som ou fonte usado em {onde} não está no projeto.',
  R005: '{onde} usa uma variável que não existe ou não vale aqui.',
  R006: '{onde} aponta para uma cena que não existe.',
  R007: '{onde} aponta para um capítulo que não existe.',
  R008: '{onde} usa um grupo de exclusividade que não foi criado.',
  R009: 'Um passo em {onde} leva a outro passo que foi apagado.',
  R010: '{onde} cita um personagem que não existe.',
  R011: '{onde} usa uma expressão que o personagem não tem.',
  R012: '{onde} termina num final que não está na lista de finais do jogo.',
  R013: 'Os idiomas do build não batem com os idiomas do projeto.',
  R014: '{onde} leva a uma cena de outro capítulo. Para mudar de capítulo, termine este capítulo e escolha o próximo.',
  R015: 'Um grupo de exclusividade tem o mesmo nome no jogo inteiro e num capítulo. Use nomes diferentes.',
  R016: 'A escolha ou clique em {onde} guarda um valor que a variável não aceita.',
  R017: 'Só variáveis globais e de plugins podem valer para o perfil inteiro ({onde}).',
  R018: 'O texto de {onde} tem uma formatação quebrada ou desconhecida.',
  R019: 'O texto de {onde} mostra uma variável que não existe ou não vale aqui. O jogador veria o texto quebrado.',
  R020: '{onde} anuncia um acontecimento que não é da história. Só acontecimentos da história podem ser anunciados.',
  R021: 'Para exportar, o projeto precisa de um número de versão.',
  R022: '{onde} muda a história conforme o modo stream. O modo stream só pode trocar o que aparece, nunca o que acontece.',
  R023: '{onde} só pode ser pulado ou trocado no modo stream se for um passo de apresentação (fala, cenário, personagem, som ou espera).',
  R024: 'A versão para o modo stream de {onde} não pode ser o próprio item nem outro item também marcado para o modo stream.',
  T001: '{onde} compara ou grava um valor de tipo diferente do da variável.',
  T002: '{onde} tenta alterar uma variável que só pode ser lida.',
  T003: '{onde} faz uma conta que não combina com o tipo da variável.',
  T004: 'Duas ou mais variáveis calculadas dependem uma da outra em círculo ({onde}).',
  T005: '{onde} usa o resultado de um minijogo fora do lugar onde ele existe.',
  T006: '{onde} grava numa variável um valor de outro tipo.',
  T007: '{onde} usa uma função com argumentos de número ou tipo errado.',
  T008: 'Uma variável calculada não pode sortear números ({onde}).',
  P001: 'Dois plugins usam o mesmo nome interno.',
  P002: '{onde} usa um minijogo que nenhum plugin oferece.',
  P003: '{onde} usa um plugin que não está instalado no projeto.',
  P004: 'As opções em {onde} não são aceitas pelo plugin.',
  P005: '{onde} usa um resultado que o minijogo não tem.',
  P006: 'O projeto deu ao plugin uma permissão que ele não pediu ({onde}).',
  P007: 'O projeto deu ao plugin acesso a uma variável que ele não pediu ({onde}).',
  P008: 'O projeto deixou o plugin alterar uma variável que não aceita alterações de plugins ({onde}).',
  P009: 'O plugin anuncia um acontecimento fora do próprio nome ({onde}).',
  P010: 'O plugin dá nome a um resultado que não existe ({onde}).',
  P011: 'O código do plugin usa um nome sem o prefixo do plugin ({onde}).',
  P012: 'O código do plugin acessa arquivos fora da própria pasta ({onde}).',
  P013: 'Um plugin está ligado a uma pasta de desenvolvimento. Peça ao desenvolvedor o arquivo .vnplugin antes de exportar.',
  P014: 'O projeto deixou o plugin ler uma variável que não aceita leitura de plugins ({onde}).',
  P015: 'A versão travada de um plugin não bate com a pedida pelo projeto ({onde}).',
  P016: 'Só plugins oficiais podem usar a internet ({onde}).',
  P017: 'O plugin pede acesso a variáveis que não pode usar ({onde}).',
  P018: 'As opções em {onde} citam uma imagem, cena ou personagem que não existe.',
  P019: 'O plugin guarda recordes ou dados de perfil sem pedir a permissão para isso ({onde}).',
  P020: '{onde} abre um minijogo que não existe ou que não pode ser jogado fora da história.',
  P021: 'A pasta ou o arquivo do plugin indicado em {onde} não foi encontrado.',
  W001: 'Este passo nunca é alcançado.',
  W002: 'Um resultado do minijogo em {onde} não tem destino; a cena segue para o próximo passo.',
  W003: 'Há uma tradução para um texto que não existe mais ({onde}).',
  W004: 'O plugin não foi encontrado, então as permissões dele não foram conferidas.',
  W005: 'O capítulo pode ficar sem nenhuma cena disponível.',
  W006: '{onde} pode ficar sem nenhuma opção visível.',
  W007: 'O plugin não deu nome legível a um campo ({onde}).',
  W008: 'O plugin não foi testado para uma das plataformas do jogo. O jogo pode funcionar mal nela.',
  W009: 'O código do plugin usa um recurso do Godot que plugins não podem usar ({onde}).',
  W010: 'A cena de reserva do capítulo não muda nada que faça o capítulo terminar. O jogo pode ficar repetindo essa cena.',
  W011: 'O final em {onde} só vale quando o passo encerra o jogo.',
  W012: 'O plugin quer ouvir acontecimentos, mas não pediu a permissão para isso.',
  W013: 'Este passo está incompleto.',
  W014: '{onde} usa um arquivo de tipo diferente do esperado (por exemplo, uma fonte como cenário).',
  W015: '{onde} usa um acontecimento da história que não está na lista de acontecimentos do jogo.',
  W016: 'O plugin usa um texto que não tem versão no idioma principal dele ({onde}).',
  W017: '{onde} grava um número com casas decimais numa variável de números inteiros; o valor será cortado.',
  W018: 'Este capítulo não está na lista de capítulos do jogo.',
  W019: '{onde} espera um acontecimento do sistema, que nunca é registrado; a condição é sempre falsa.',
  W021: 'Os textos prontos do jogo (menus, avisos) não estão traduzidos para um dos idiomas; vão aparecer em inglês.',
  W022: 'O plugin guarda recordes, mas não tem permissão para gravar dados de perfil.',
  W023: 'Uma tradução está no arquivo errado ({onde}).',
  W024: 'Há conteúdo marcado para o modo stream, mas o jogador não tem como ligar esse modo.',
  W025: 'A fala em {onde} tem texto para o modo stream, mas a voz original continua tocando.',
  U001: '{onde} usa um elemento, camada, estado, tela ou cenário que não existe.',
  U002: '{onde} usa um estilo que não existe no tema.',
  U003: '{onde} no menu inicial depende de uma variável que só existe durante uma partida. Use uma variável de perfil ou de finais.',
  U004: '{onde} faz uma ação que não vale nesse lugar.',
  U005: '{onde} usa um controle ou valor que não combina com a configuração.',
  U006: '{onde}: a tela não tem como seguir adiante (o menu inicial precisa de "Novo jogo", a pausa de um botão para voltar).',
  U007: '{onde} sai da tela.',
  U008: '{onde} pode ser clicado, mas não tem texto nem dica (fica sem nome para teclado e leitores de tela).',
  U009: 'A tela de créditos não mostra as licenças, que o jogo é obrigado a exibir.',
  U010: 'Um minijogo é aberto a partir da pausa; o botão ficará escondido durante a partida.',
  U011: 'Uma seção da galeria vai aparecer vazia.',
  U012: '{onde} mostra uma seção da galeria que o projeto não ativou.',
  U013: 'Um arquivo marcado para a galeria não vai aparecer nela ({onde}).',
  U014: 'O projeto não tem galeria, então a tela ou o botão de galeria não faz nada ({onde}).',
};

function fill(t: Template, p: Params): string | null {
  if (typeof t === 'function') return t(p);
  let missing = false;
  const s = t.replace(/\{(\w+)\}/g, (_, k: string) => {
    if (p[k] === undefined) missing = true;
    return String(p[k] ?? '');
  });
  return missing ? null : s;
}

/** Frase simples para um diagnóstico. */
export function plainMessage(code: string, where: string, detail: string, params: Params = {}): string {
  const p: Params = { onde: where, detalhe: detail, ...params };
  const specific = TEMPLATES[code];
  if (specific && Object.keys(params).length) {
    const s = fill(specific, p);
    if (s) return s;
  }
  return fill(GENERIC[code] ?? '{onde}: {detalhe}', p) ?? detail;
}

export const KNOWN_CODES = Object.keys(GENERIC);
