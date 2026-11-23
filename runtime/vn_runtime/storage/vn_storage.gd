@abstract
class_name VNStorage
extends VNModule
## VNStorage (RT §8.5): onde o Save Manager e o UI Manager gravam os dados do
## jogador. O runtime nunca abre [code]user://[/code] direto; tudo passa por
## aqui, inclusive os dados de plugin que vão no save e no perfil.
##
## Três implementações, escolhidas no boot (RT §8.5, PP §1.4):
## [constant KIND_USER] ([code]user://[/code]; no Web, IndexedDB), no jogo
## exportado; [constant KIND_MEMORY] (dicionário descartado ao fechar), padrão
## do Preview; [constant KIND_FOLDER] ([code].vnstudio/preview/user/[/code]: na
## janela grava em [code]--vn-user-dir[/code]; no painel guarda na memória e
## emite [signal file_written]/[signal file_deleted], que viram
## [code]storage.write[/code]/[code]storage.delete[/code]).
##
## Caminhos são relativos, com [code]/[/code], sem [code]..[/code] nem raiz
## ([method is_valid_path]): [code]saves/slot_1.json[/code],
## [code]profile.json[/code], [code]settings.json[/code].
##
## Specs: RT §8.5, §11; Preview Protocol §1.4, §4; Plugin SDK §12.2 (W009).
## Tarefas: M2-10 (user:// e memória), M4-08 (pasta do Preview).

## Um arquivo foi gravado (todas as implementações).
signal file_written(path: String, data: PackedByteArray)
## Um arquivo foi apagado (todas as implementações).
signal file_deleted(path: String)

const KIND_USER := &"user"
const KIND_MEMORY := &"memory"
const KIND_FOLDER := &"folder"


func module_id() -> StringName:
	return &"storage"


## Qual implementação é: [constant KIND_USER], [constant KIND_MEMORY] ou [constant KIND_FOLDER].
@abstract func kind() -> StringName

@abstract func exists(path: String) -> bool

## Bytes do arquivo; vazio se ele não existe (confira [method exists]).
@abstract func read_bytes(path: String) -> PackedByteArray

## Grava o arquivo inteiro, criando as pastas. Recusa caminho inválido com
## [constant ERR_INVALID_PARAMETER].
@abstract func write_bytes(path: String, data: PackedByteArray) -> Error

## Apaga o arquivo. Apagar o que não existe devolve [constant ERR_FILE_NOT_FOUND].
@abstract func delete(path: String) -> Error

## Renomeia (usado para [code]settings.json.bad[/code] e
## [code]profile.rejected.json[/code], RT §3.0).
@abstract func rename(from_path: String, to_path: String) -> Error

## Arquivos sob [param dir] (sem recursão), em ordem lexicográfica, com o caminho completo.
@abstract func list(dir: String) -> PackedStringArray


## Caminho aceito: relativo, com [code]/[/code], sem [code]..[/code], [code]\\[/code]
## nem esquema (PP §1.4: o Studio recusa o resto).
static func is_valid_path(path: String) -> bool:
	if path.is_empty() or path.begins_with("/") or path.contains("\\") or path.contains(":"):
		return false
	for part in path.split("/"):
		if part.is_empty() or part == "." or part == "..":
			return false
	return true


## Texto UTF-8; vazio se o arquivo não existe.
func read_text(path: String) -> String:
	return read_bytes(path).get_string_from_utf8()


func write_text(path: String, text: String) -> Error:
	return write_bytes(path, text.to_utf8_buffer())


## JSON lido; [code]null[/code] se não existe ou não é JSON válido.
func read_json(path: String) -> Variant:
	if not exists(path):
		return null
	return JSON.parse_string(read_text(path))


func write_json(path: String, data: Variant) -> Error:
	return write_text(path, JSON.stringify(data, "\t"))
