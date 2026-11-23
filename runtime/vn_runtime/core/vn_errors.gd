class_name VNErrors
extends RefCounted
## Códigos de erro do runtime (RT §6.2, §9; Plugin SDK §5.2, §6.1).
##
## A ordem das verificações de escrita é a do RT §6.2: a primeira que falha
## interrompe. Os mesmos códigos vão em [code]data.vn_code[/code] do erro
## [code]STATE_REJECTED[/code] do Preview (Preview Protocol §6).

const WRONG_THREAD := &"WRONG_THREAD"                  ## 1. chamada fora da thread principal
const INVALID_STATE := &"INVALID_STATE"                ## 2. estado do jogo não permite escrita
const VARIABLE_NOT_FOUND := &"VARIABLE_NOT_FOUND"      ## 3. variável não existe
const READ_ONLY := &"READ_ONLY"                        ## 4. sys.* ou derivada
const SCOPE_INACTIVE := &"SCOPE_INACTIVE"              ## 5. chapter.*/scene.* sem capítulo/cena ativos
const PERMISSION_DENIED := &"PERMISSION_DENIED"        ## 6. chamador sem permissão (DM §4.6, SDK §4)
const TYPE_MISMATCH := &"TYPE_MISMATCH"                ## 7. tipo incompatível com a operação ou o valor
const OUT_OF_RANGE := &"OUT_OF_RANGE"                  ## 8. fora de ±(2^53 − 1), não finito, divisão por zero (RT §12.1); erro de conteúdo
const CONSTRAINT_VIOLATION := &"CONSTRAINT_VIOLATION"  ## 9. restrição; lógica de jogo, não erro de conteúdo (DM §6.2)
const CONFLICT := &"CONFLICT"                          ## 10. expect não confere (só transações)

## Verificações de escrita na ordem do RT §6.2.
const WRITE_CHECK_ORDER: Array[StringName] = [
	WRONG_THREAD, INVALID_STATE, VARIABLE_NOT_FOUND, READ_ONLY, SCOPE_INACTIVE,
	PERMISSION_DENIED, TYPE_MISMATCH, OUT_OF_RANGE, CONSTRAINT_VIOLATION, CONFLICT,
]


## Erro de conteúdo (RT §9): pausa com overlay em debug/Preview; em release
## registra e segue. [constant CONSTRAINT_VIOLATION] não é erro de conteúdo.
static func is_content_error(code: StringName) -> bool:
	return code in [VARIABLE_NOT_FOUND, READ_ONLY, SCOPE_INACTIVE, TYPE_MISMATCH, OUT_OF_RANGE]
