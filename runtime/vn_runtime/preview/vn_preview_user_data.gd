class_name VNPreviewUserData
extends RefCounted
## Dados do jogador no Preview (Preview Protocol §1.2, §1.4, §4; RT §8.5; decisões D21 e D25).
## Tarefa: M4-08.
##
## Escolhe o [VNStorage] do Preview e o põe no registro dos módulos. Nada do Preview grava em
## [code]user://[/code]:
## [br]- [code]user_data: "memory"[/code] (padrão): [VNMemoryStorage]; nada sobrevive ao fechar.
## [br]- [code]user_data: "project"[/code] na janela: [VNFolderStorage] na pasta de
##   [code]--vn-user-dir[/code] ([code]<projeto>/.vnstudio/preview/user[/code]), gravando direto.
## [br]- [code]user_data: "project"[/code] no painel: [VNFolderStorage] em memória, semeado com
##   [code]user_files[/code] do [code]preview.load[/code]; cada gravação ou remoção vira a notificação
##   [code]storage.write[/code]/[code]storage.delete[/code], que o Studio aplica na pasta.
##
## A [VNPreviewSession] chama [method configure] com os [code]params[/code] de cada
## [code]preview.load[/code], antes do handler do método (M4-05), para que o handler já leia o
## perfil e as configurações do lugar certo. Depois de trocar o armazenamento, quem carrega o
## bundle relê [code]profile.json[/code] e [code]settings.json[/code] (o Save Manager e o UI Manager
## leem pelo [code]modules.storage[/code]).

## Opção da janela com a pasta dos saves mantidos (PP §1.2).
const USER_DIR_FLAG := "--vn-user-dir"

const MEMORY := "memory"
const PROJECT := "project"

const _BASE64 := "^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$"

var transport: VNPreviewSession.Transport
## Pasta de [code]--vn-user-dir[/code] (absoluta, com [code]/[/code], terminada em [code]/[/code]),
## ou vazio. Só na janela.
var user_dir: String

var _mode := MEMORY
var _storage: VNStorage = null
# A sessão guarda este objeto; aqui fica só uma referência fraca, para não formar ciclo.
var _session_ref: WeakRef = null


func _init(p_transport: VNPreviewSession.Transport, p_user_dir: String = "") -> void:
	transport = p_transport
	user_dir = p_user_dir


## [code]memory[/code] ou [code]project[/code], conforme o último [method configure].
func mode() -> String:
	return _mode


## O armazenamento em uso desde o último [method configure], ou null antes dele.
func storage() -> VNStorage:
	return _storage


# --- Linha de comando e boot -------------------------------------------------

## [code]--vn-user-dir <pasta>[/code] (ou [code]--vn-user-dir=<pasta>[/code]): [code]{dir}[/code]
## com a pasta normalizada, vazio se a opção não veio, ou [code]{error}[/code]. A pasta precisa ser
## absoluta e não pode ficar dentro de [code]user://[/code] (PP §1.4, RT §8.5).
static func user_dir_option(args: PackedStringArray = VNPreview._all_args()) -> Dictionary:
	var present := false
	for a in args:
		if a == USER_DIR_FLAG or a.begins_with(USER_DIR_FLAG + "="):
			present = true
	if not present:
		return {}
	var raw := VNPreview._value_of(args, USER_DIR_FLAG)
	var dir := normalize_dir(raw)
	if dir.is_empty():
		return {"error": "%s precisa de uma pasta absoluta (recebeu \"%s\")" % [USER_DIR_FLAG, raw]}
	if _is_inside(dir, normalize_dir(OS.get_user_data_dir())):
		return {"error": "%s não pode apontar para a pasta de dados do jogo (user://)" % USER_DIR_FLAG}
	return {"dir": dir}


## Pasta absoluta do sistema com [code]/[/code] e terminada em [code]/[/code]; vazio se o caminho
## for relativo, tiver esquema ([code]user://[/code], [code]res://[/code]) ou [code]..[/code].
static func normalize_dir(path: String) -> String:
	var p := path.strip_edges().replace("\\", "/")
	if p.is_empty() or p.contains("://"):
		return ""
	var windows_drive := RegEx.create_from_string("^[A-Za-z]:/").search(p) != null
	if not (p.begins_with("/") or windows_drive):
		return ""
	for part in p.split("/"):
		if part == "..":
			return ""
	p = p.simplify_path()
	return p if p.ends_with("/") else p + "/"


static func _is_inside(dir: String, root: String) -> bool:
	if root.is_empty():
		return false
	var case_insensitive := OS.get_name() in ["Windows", "macOS"]
	if case_insensitive:
		return dir.to_lower().begins_with(root.to_lower())
	return dir.begins_with(root)


## O [VNStorage] do boot. Num lançamento do Preview ([param preview] true), nunca
## [code]user://[/code]: a pasta de [code]--vn-user-dir[/code] quando ela veio (o Studio só a passa
## com "Manter saves do Preview", PP §1.2) e a memória no resto. O [code]preview.load[/code] confirma
## ou troca a escolha com [method configure]. Fora do Preview, [VNUserStorage].
static func boot_storage(preview: bool, args: PackedStringArray = VNPreview._all_args()) -> VNStorage:
	if not preview:
		return VNUserStorage.new()
	var opt := user_dir_option(args)
	if opt.has("dir"):
		return VNFolderStorage.new(opt["dir"])
	if opt.has("error"):
		push_warning("Preview: " + String(opt["error"]) + "; os dados do jogador ficam na memória.")
	return VNMemoryStorage.new()


# --- preview.load ------------------------------------------------------------

## Confere [code]user_data[/code] e [code]user_files[/code] de um [code]preview.load[/code] e troca o
## armazenamento no registro dos módulos da [param session]. Devolve null, ou o erro do
## [code]preview.load[/code] ([code]-32602[/code]) sem mudar nada.
func configure(params: Dictionary, session: VNPreviewSession = null) -> VNPreviewError:
	var mode_value: Variant = params.get("user_data", MEMORY)
	if not mode_value in [MEMORY, PROJECT]:
		return VNPreviewError.invalid_params("user_data deve ser \"memory\" ou \"project\"")
	var files := {}
	if params.has("user_files"):
		if transport != VNPreviewSession.Transport.PANEL or mode_value != PROJECT:
			return VNPreviewError.invalid_params("user_files só vem no painel com user_data \"project\" (PP §1.4)")
		var decoded: Variant = decode_user_files(params["user_files"])
		if decoded is String:
			return VNPreviewError.invalid_params(decoded)
		files = decoded
	if mode_value == PROJECT and transport == VNPreviewSession.Transport.WINDOW and user_dir.is_empty():
		return VNPreviewError.invalid_params(
			"user_data \"project\" na janela precisa de %s ao abrir o runtime (PP §1.2)" % USER_DIR_FLAG)

	var new_storage: VNStorage
	if mode_value == MEMORY:
		new_storage = VNMemoryStorage.new()
	elif transport == VNPreviewSession.Transport.WINDOW:
		new_storage = VNFolderStorage.new(user_dir)
	else:
		var panel := VNFolderStorage.new()
		panel.seed_files(files)
		new_storage = panel
	_replace(new_storage, mode_value, session)
	return null


## [code]user_files[/code] ([code]{ caminho → base64 }[/code]) em [code]{ caminho → bytes }[/code], ou
## o texto do erro quando um caminho sai da pasta ou um conteúdo não é base64.
static func decode_user_files(value: Variant) -> Variant:
	if not value is Dictionary:
		return "user_files deve ser um objeto { caminho → base64 }"
	var re := RegEx.create_from_string(_BASE64)
	var out := {}
	for key in value:
		var path := String(key)
		if not key is String or not VNStorage.is_valid_path(path):
			return "user_files: caminho inválido \"%s\" (relativo, com /, sem ..)" % path
		var data: Variant = value[key]
		if not data is String or re.search(data) == null:
			return "user_files: o conteúdo de \"%s\" não é base64" % path
		out[path] = Marshalls.base64_to_raw(data) if not String(data).is_empty() else PackedByteArray()
	return out


func _replace(new_storage: VNStorage, new_mode: String, session: VNPreviewSession) -> void:
	release()
	_storage = new_storage
	_mode = new_mode
	_session_ref = weakref(session) if session != null else null
	var panel_project := new_storage is VNFolderStorage and (new_storage as VNFolderStorage).is_panel_mode()
	if panel_project:
		# Métodos, não lambdas: uma lambda guardaria uma referência a este objeto e formaria ciclo.
		new_storage.file_written.connect(_on_written)
		new_storage.file_deleted.connect(_on_deleted)
	if session != null and session.modules != null:
		session.modules.storage = new_storage


## Solta o armazenamento e os sinais que o ligam a esta sessão (a sessão acabou ou o
## [code]preview.load[/code] trocou o armazenamento). Sem isto, os objetos se seguram uns aos outros.
func release() -> void:
	_disconnect()
	if _storage is VNFolderStorage:
		(_storage as VNFolderStorage).release()
	_storage = null
	_session_ref = null


func _disconnect() -> void:
	if _storage == null:
		return
	if _storage.file_written.is_connected(_on_written):
		_storage.file_written.disconnect(_on_written)
	if _storage.file_deleted.is_connected(_on_deleted):
		_storage.file_deleted.disconnect(_on_deleted)


# --- Notificações do painel (PP §4) ------------------------------------------

func _session() -> VNPreviewSession:
	return _session_ref.get_ref() as VNPreviewSession if _session_ref != null else null


func _on_written(path: String, data: PackedByteArray) -> void:
	var session := _session()
	if session != null:
		session.notify("storage.write", {"path": path, "data": Marshalls.raw_to_base64(data)})


func _on_deleted(path: String) -> void:
	var session := _session()
	if session != null:
		session.notify("storage.delete", {"path": path})
