extends SceneTree
## Testes unitários do Variable Manager real (tarefa M1-05).
##
##   godot --headless --path runtime --script res://tests/variable_manager/test_variable_manager.gd
##
## Cobrem a tabela do ciclo de vida por escopo (RT §6.5), defaults (DM §4.2),
## persistência (DM §4.4), derivadas (DM §4.5), sys.* (DM §4.3), aliases de
## renamed_from (DM §12) e o save de versão antiga (RT §8.4). O módulo roda
## com os dublês dos outros módulos (VNFakeModules). Sai com 1 se algo falhar.

const CH1 := "01930001-0000-7000-8000-0000000000c1"
const CH2 := "01930001-0000-7000-8000-0000000000c2"
const SC1 := "01930001-0000-7000-8000-0000000000a1"
const SC2 := "01930001-0000-7000-8000-0000000000a2"

var _passed := 0
var _failed := 0
var _err := ""
## Registros criados no teste atual; liberados ao fim de cada teste.
var _registries: Array[VNModules] = []


func _init() -> void:
	for t in [
		"defaults_por_tipo", "personagem_e_plugin", "ids_ordenados_e_definicao",
		"global_novo_jogo", "capitulo_ciclo_de_vida", "cena_ciclo_de_vida",
		"profile_sobrevive", "session_nunca_salva", "save_values_escopo_ativo",
		"restore_reinicia_e_aplica", "restore_capitulo_e_cena_pendentes",
		"restore_versao_antiga", "aliases_renamed_from", "derivadas",
		"derivadas_ciclo", "sys_fixas_e_entidades", "sys_do_historico",
		"sys_novo_jogo", "store_recusa_invalidas", "integra_com_dubles",
	]:
		_run(t)
	print("%d/%d testes do Variable Manager passaram." % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func _run(test: String) -> void:
	_err = ""
	call("test_" + test)
	_registries.clear()
	if _err.is_empty():
		_passed += 1
		print("ok      ", test)
	else:
		_failed += 1
		print("FALHOU  ", test, ": ", _err)


func _eq(actual: Variant, expected: Variant, what: String) -> bool:
	if _err.is_empty() and not (typeof(actual) == typeof(expected) and actual == expected):
		_err = "%s: esperado %s (%s), veio %s (%s)" % [what, var_to_str(expected), type_string(typeof(expected)), var_to_str(actual), type_string(typeof(actual))]
	return _err.is_empty()


func _ok(cond: bool, what: String) -> bool:
	if _err.is_empty() and not cond:
		_err = what
	return _err.is_empty()


# --- Bundle de teste --------------------------------------------------------

func _bundle() -> Dictionary:
	return {
		"project": {
			"default_locale": "pt-BR",
			"endings": [{"id": "good", "title": "Bom"}, {"id": "bad", "title": "Ruim"}],
			"gallery": {"sections": ["endings", "music"]},
		},
		"variables": {
			"global.money": {"key": "money", "type": "integer", "default": 10, "persistence": "save",
				"constraints": {"min": 0, "max": 100, "on_overflow": "clamp"}, "renamed_from": ["cash"]},
			"global.ratio": {"key": "ratio", "type": "number", "default": 1, "persistence": "save"},
			"global.flag": {"key": "flag", "type": "boolean", "persistence": "save"},
			"global.name": {"key": "name", "type": "string", "persistence": "save", "constraints": {"max_length": 5}},
			"global.mood": {"key": "mood", "type": "enum", "persistence": "save", "constraints": {"values": ["calm", "angry"]}},
			"global.ng_plus": {"key": "ng_plus", "type": "integer", "default": 0, "persistence": "profile", "renamed_from": ["newgame"]},
			"global.temp": {"key": "temp", "type": "integer", "default": 3, "persistence": "session"},
			"global.rich": {"key": "rich", "type": "integer", "derived": {"var": "global.money"}},
			"global.richer": {"key": "richer", "type": "number", "derived": {"var": "global.rich"}},
			"character.alice.affection": {"key": "affection", "type": "integer", "default": 10, "persistence": "save"},
			"character.bob.affection": {"key": "affection", "type": "integer", "default": 0, "persistence": "save"},
			"plugin.fishing.best": {"key": "best", "type": "integer", "default": 0, "persistence": "profile"},
			"plugin.fishing.casts": {"key": "casts", "type": "integer", "default": 0, "persistence": "save"},
		},
		"aliases": {
			"global.cash": "global.money",
			"global.newgame": "global.ng_plus",
			"old_scene_id": SC1,
		},
		"chapters": {
			CH1: {"id": CH1, "variables": [
				{"key": "visits", "type": "integer", "default": 1, "persistence": "save", "renamed_from": ["seen"]},
				{"key": "hint", "type": "boolean", "persistence": "session"},
			]},
			CH2: {"id": CH2, "variables": []},
		},
		"scenes": {
			SC1: {"id": SC1, "chapter": CH1, "variables": [
				{"key": "tries", "type": "integer", "default": 2, "persistence": "save"},
				{"key": "double", "type": "integer", "derived": {"var": "scene.tries"}},
			]},
			SC2: {"id": SC2, "chapter": CH1, "variables": []},
		},
	}


func _vm(bundle: Dictionary = _bundle()) -> VNVariableManagerImpl:
	var m := VNFakeModules.create()
	var vm := VNVariableManagerImpl.new()
	vm.quiet = true
	m.variables = vm
	m.bind_all()
	vm.load_bundle(bundle)
	_registries.append(m)  # mantém o registro vivo (o módulo guarda só referência fraca)
	return vm


func _mods(vm: VNVariableManagerImpl) -> VNModules:
	return vm.modules()


# --- Defaults (DM §4.2) -----------------------------------------------------

func test_defaults_por_tipo() -> void:
	var vm := _vm()
	_eq(vm.read("global.money"), 10, "integer com default")
	_eq(vm.read("global.ratio"), 1.0, "number: 1 do JSON vira 1.0")
	_eq(vm.read("global.flag"), false, "boolean sem default")
	_eq(vm.read("global.name"), "", "string sem default")
	_eq(vm.read("global.mood"), "calm", "enum sem default: primeiro valor")
	_eq(vm.get_definition("global.flag").default, false, "default efetivo na definição")
	_eq(vm.get_definition("global.money").persistence, &"save", "persistence")
	var b := _bundle()
	b.variables["global.flag"].erase("persistence")
	b.variables["global.money"]["default"] = 10.0
	vm = _vm(b)
	_eq(vm.get_definition("global.flag").persistence, &"save", "persistence padrão é save")
	_eq(vm.read("global.money"), 10, "integer: 10.0 do JSON vira 10")


func test_personagem_e_plugin() -> void:
	var vm := _vm()
	_eq(vm.read("character.alice.affection"), 10, "initial_values do personagem")
	_eq(vm.read("character.bob.affection"), 0, "modelo instanciado por personagem")
	_eq(vm.read("plugin.fishing.casts"), 0, "variável de plugin")
	_ok(not vm.is_read_only("plugin.fishing.casts"), "plugin.* não é somente leitura no Variable Manager")
	_eq(vm.get_definition("character.alice.affection").scope, &"character", "escopo")


func test_ids_ordenados_e_definicao() -> void:
	var vm := _vm()
	var ids := vm.ids()
	var sorted := ids.duplicate()
	sorted.sort()
	_eq(ids, sorted, "ids() em ordem lexicográfica")
	_ok(ids.has("chapter.visits") and ids.has("scene.tries"), "ids() inclui chapter.* e scene.*")
	_ok(ids.has("sys.selection_count"), "ids() inclui sys.*")
	_ok(vm.get_definition("global.nada").is_empty(), "definição de inexistente é vazia")
	var d := vm.get_definition("global.money")
	d.default = 99
	_eq(vm.get_definition("global.money").default, 10, "get_definition devolve cópia")


# --- RT §6.5: global.*, character.*, plugin.* -------------------------------

func test_global_novo_jogo() -> void:
	var vm := _vm()
	vm.store("global.money", 50)
	vm.store("character.alice.affection", 40)
	vm.store("plugin.fishing.casts", 7)
	_eq(vm.read("global.money"), 50, "store grava")
	_ok(not vm.is_default("global.money"), "is_default falso depois da escrita")
	vm.reset_game()
	_eq(vm.read("global.money"), 10, "novo jogo reinicia global.*")
	_eq(vm.read("character.alice.affection"), 10, "novo jogo reinicia character.* com initial_values")
	_eq(vm.read("plugin.fishing.casts"), 0, "novo jogo reinicia plugin.*")
	_ok(vm.is_default("global.money"), "is_default depois do novo jogo")


# --- RT §6.5: chapter.* -----------------------------------------------------

func test_capitulo_ciclo_de_vida() -> void:
	var vm := _vm()
	_ok(vm.has("chapter.visits"), "chapter.* existe mesmo sem capítulo ativo")
	_ok(not vm.is_scope_active("chapter.visits"), "inativa antes da entrada")
	_eq(vm.read("chapter.visits", -9), -9, "leitura com escopo inativo devolve fallback")
	vm.enter_chapter(CH1)
	_ok(vm.is_scope_active("chapter.visits"), "ativa depois da entrada")
	_eq(vm.read("chapter.visits"), 1, "criada com o default na entrada")
	vm.store("chapter.visits", 5)
	_eq(vm.read("chapter.visits"), 5, "store em chapter.*")
	vm.enter_chapter(CH1)
	_eq(vm.read("chapter.visits"), 1, "reiniciada a cada entrada")
	vm.store("chapter.visits", 5)
	vm.exit_chapter()
	_ok(not vm.is_scope_active("chapter.visits"), "destruída na saída")
	_eq(vm.read("chapter.visits", null), null, "sem valor depois da saída")
	vm.enter_chapter(CH2)
	_ok(not vm.is_scope_active("chapter.visits"), "outro capítulo não a declara")
	_ok(vm.has("chapter.visits"), "continua existindo (SCOPE_INACTIVE, não VARIABLE_NOT_FOUND)")
	vm.exit_chapter()
	vm.enter_chapter(CH1)
	_eq(vm.read("chapter.visits"), 1, "reentrada começa do default")


# --- RT §6.5: scene.* -------------------------------------------------------

func test_cena_ciclo_de_vida() -> void:
	var vm := _vm()
	vm.enter_chapter(CH1)
	_ok(not vm.is_scope_active("scene.tries"), "inativa antes do início")
	vm.enter_scene(SC1)
	_eq(vm.read("scene.tries"), 2, "criada com o default no início")
	vm.store("scene.tries", 0)
	vm.enter_scene(SC1)
	_eq(vm.read("scene.tries"), 2, "reiniciada a cada início")
	vm.store("scene.tries", 0)
	vm.exit_scene()
	_ok(not vm.is_scope_active("scene.tries"), "destruída no fim")
	_eq(vm.read("scene.tries", -1), -1, "fallback depois do fim")
	_ok(vm.is_scope_active("chapter.visits"), "fim da cena não mexe no capítulo")
	vm.enter_scene(SC2)
	_ok(not vm.is_scope_active("scene.tries"), "outra cena não a declara")


# --- RT §6.5: profile e session ---------------------------------------------

func test_profile_sobrevive() -> void:
	var vm := _vm()
	_eq(vm.read("global.ng_plus"), 0, "profile começa no default (primeiro boot)")
	vm.apply_profile({"global.ng_plus": 2, "plugin.fishing.best": 30.0})
	_eq(vm.read("global.ng_plus"), 2, "apply_profile")
	_eq(vm.read("plugin.fishing.best"), 30, "apply_profile converte 30.0 em inteiro")
	vm.store("global.ng_plus", 3)
	vm.reset_game()
	_eq(vm.read("global.ng_plus"), 3, "novo jogo não reinicia profile")
	_eq(vm.profile_values(), {"global.ng_plus": 3, "plugin.fishing.best": 30}, "profile_values")
	_ok(not vm.save_values().has("global.ng_plus"), "profile não vai para o save")
	vm.restore_save_values({"global.money": 20})
	_eq(vm.read("global.ng_plus"), 3, "carregar save não reinicia profile")
	vm.apply_profile({"global.money": 99, "global.sumiu": 1})
	_eq(vm.read("global.money"), 20, "apply_profile ignora variável que não é profile")


func test_session_nunca_salva() -> void:
	var vm := _vm()
	vm.store("global.temp", 9)
	_ok(not vm.save_values().has("global.temp"), "session não vai para o save")
	_ok(not vm.profile_values().has("global.temp"), "session não vai para o perfil")
	vm.restore_save_values({})
	_eq(vm.read("global.temp"), 3, "session volta ao padrão ao carregar save")
	vm.store("global.temp", 9)
	vm.reset_game()
	_eq(vm.read("global.temp"), 3, "session volta ao padrão em novo jogo")
	vm.enter_chapter(CH1)
	vm.store("chapter.hint", true)
	_ok(not vm.save_values().has("chapter.hint"), "session de capítulo não vai para o save")


# --- RT §8.2 ----------------------------------------------------------------

func test_save_values_escopo_ativo() -> void:
	var vm := _vm()
	var s := vm.save_values()
	_eq(s.get("global.money"), 10, "valores no padrão também vão para o save")
	_ok(not s.has("global.rich"), "derivadas nunca vão para o save")
	_ok(not s.has("chapter.visits"), "chapter.* só com capítulo ativo")
	_ok(not s.keys().any(func(k): return String(k).begins_with("sys.")), "sys.* nunca vai para o save")
	vm.enter_chapter(CH1)
	vm.enter_scene(SC1)
	s = vm.save_values()
	_eq(s.get("chapter.visits"), 1, "chapter.* ativo vai para o save")
	_eq(s.get("scene.tries"), 2, "scene.* ativo vai para o save")
	_ok(not s.has("scene.double"), "derivada de cena não vai para o save")
	var keys := PackedStringArray(s.keys())
	var sorted := keys.duplicate()
	sorted.sort()
	_eq(keys, sorted, "chaves em ordem lexicográfica")


# --- RT §8.3 e §8.4 ---------------------------------------------------------

func test_restore_reinicia_e_aplica() -> void:
	var vm := _vm()
	vm.store("global.money", 77)
	vm.store("global.name", "Ana")
	var w := vm.restore_save_values({"global.money": 30, "character.alice.affection": 12.0})
	_eq(w.size(), 0, "sem avisos")
	_eq(vm.read("global.money"), 30, "valor do save")
	_eq(vm.read("global.name"), "", "o que não está no save volta ao default")
	_eq(vm.read("character.alice.affection"), 12, "12.0 do JSON vira inteiro")


func test_restore_capitulo_e_cena_pendentes() -> void:
	var vm := _vm()
	var w := vm.restore_save_values({"chapter.visits": 4, "scene.tries": 9, "global.money": 1})
	_eq(w.size(), 0, "sem avisos")
	_eq(vm.read("chapter.visits", null), null, "ainda sem capítulo ativo")
	vm.enter_chapter(CH1)
	vm.enter_scene(SC1)
	_eq(vm.read("chapter.visits"), 4, "pendente aplicado na entrada do capítulo")
	_eq(vm.read("scene.tries"), 9, "pendente aplicado no início da cena")
	vm.enter_scene(SC1)
	_eq(vm.read("scene.tries"), 2, "pendente vale uma vez só")
	# Ordem inversa: capítulo e cena já ativos quando o save é aplicado.
	vm.restore_save_values({"chapter.visits": 6, "scene.tries": 8})
	_eq(vm.read("chapter.visits"), 6, "aplicado direto no capítulo ativo")
	_eq(vm.read("scene.tries"), 8, "aplicado direto na cena ativa")
	# Nó inexistente (RT §8.4): exit_scene descarta os pendentes.
	vm.exit_scene()
	vm.exit_chapter()
	vm.restore_save_values({"scene.tries": 5})
	vm.exit_scene()
	vm.enter_chapter(CH1)
	vm.enter_scene(SC1)
	_eq(vm.read("scene.tries"), 2, "exit_scene descarta os pendentes")


func test_restore_versao_antiga() -> void:
	var vm := _vm()
	var w := vm.restore_save_values({
		"global.money": 500,                # fora de max 100 → clamp
		"global.ratio": 3,                  # int → number
		"global.flag": 1,                   # int → boolean
		"global.name": "Mariana",           # max_length 5 → corta
		"global.mood": "sleepy",            # fora do enum → default
		"plugin.fishing.casts": true,       # boolean → integer
		"character.bob.affection": "muito", # incompatível → default
		"global.removida": 3,               # não existe mais → descarta
		"global.rich": 9,                   # derivada → descarta
		"global.ng_plus": 9,                # profile não vem do save
	})
	_eq(vm.read("global.money"), 100, "clamp nas restrições novas")
	_eq(vm.read("global.ratio"), 3.0, "int → number")
	_eq(vm.read("global.flag"), true, "int → boolean")
	_eq(vm.read("global.name"), "Maria", "max_length")
	_eq(vm.read("global.mood"), "calm", "enum inválido → default")
	_eq(vm.read("plugin.fishing.casts"), 1, "boolean → integer")
	_eq(vm.read("character.bob.affection"), 0, "incompatível → default")
	_eq(vm.read("global.ng_plus"), 0, "profile não é lido do save")
	_ok(w.size() >= 7, "avisos para cada ajuste e descarte (veio %d)" % w.size())
	_ok(Array(w).any(func(s): return s.contains("global.removida")), "aviso da variável descartada")
	w = vm.restore_save_values({"global.money": -5})
	_eq(vm.read("global.money"), 0, "clamp no mínimo")


func test_aliases_renamed_from() -> void:
	var vm := _vm()
	_eq(vm.resolve_alias("global.cash"), "global.money", "alias do bundle")
	_eq(vm.resolve_alias("chapter.seen"), "chapter.visits", "alias de chapter.* lido da definição")
	_eq(vm.resolve_alias("global.money"), "global.money", "sem alias devolve o próprio id")
	_eq(vm.resolve_alias("old_scene_id"), "old_scene_id", "aliases que não são de variável ficam de fora")
	_ok(not vm.has("global.cash"), "alias não conta como variável")
	vm.restore_save_values({"global.cash": 42, "chapter.seen": 3})
	_eq(vm.read("global.money"), 42, "save antigo lido pelo alias")
	vm.enter_chapter(CH1)
	_eq(vm.read("chapter.visits"), 3, "chapter.* antigo lido pelo alias")
	vm.apply_profile({"global.newgame": 1})
	_eq(vm.read("global.ng_plus"), 1, "perfil antigo lido pelo alias")


# --- DM §4.5 ----------------------------------------------------------------

func test_derivadas() -> void:
	var vm := _vm()
	_ok(vm.is_read_only("global.rich"), "derivada é somente leitura")
	_ok(not vm.is_read_only("global.money"), "comum não é")
	_eq(vm.read("global.rich"), 10, "calculada pelo Condition Evaluator")
	vm.store("global.money", 60)
	_eq(vm.read("global.rich"), 60, "recalculada a cada leitura")
	_eq(vm.read("global.richer"), 60.0, "derivada de derivada, com o tipo da definição")
	_ok(not vm.is_default("global.rich"), "derivada não tem padrão")
	vm.store("global.rich", 1)
	_eq(vm.read("global.rich"), 60, "store em derivada é recusado")
	vm.enter_chapter(CH1)
	vm.enter_scene(SC1)
	_eq(vm.read("scene.double"), 2, "derivada de cena")
	_ok(vm.is_read_only("scene.double"), "derivada de cena é somente leitura")
	var cond: FakeConditionEvaluator = _mods(vm).conditions
	cond.fail_with = VNErrors.OUT_OF_RANGE
	_eq(vm.read("global.rich", -1), -1, "erro de conteúdo na derivada devolve fallback")


func test_derivadas_ciclo() -> void:
	var b := _bundle()
	b.variables["global.a"] = {"key": "a", "type": "integer", "derived": {"fn": "add", "args": [{"var": "global.b"}, 1]}}
	b.variables["global.b"] = {"key": "b", "type": "integer", "derived": {"if": [{"variable": "global.a", "operator": "equals", "value": 1}], "then": 1, "else": 0}}
	var vm := _vm(b)
	_ok(Array(vm.diagnostics).any(func(s): return s.contains("ciclo")), "ciclo acusado no load_bundle")
	_eq(vm.read("global.a", -1), -1, "derivada em ciclo devolve fallback")
	_eq(vm.read("global.rich"), 10, "as outras derivadas seguem funcionando")


# --- DM §4.3 ----------------------------------------------------------------

func test_sys_fixas_e_entidades() -> void:
	var vm := _vm()
	for id in ["sys.chapter.id", "sys.scene.id", "sys.selection_count", "sys.locale", "sys.save_modified",
			"sys.ui.has_save", "sys.ui.in_game", "sys.ui.activity", "sys.ui.activity_skippable",
			"sys.ui.platform", "sys.ui.has_minigames", "sys.ui.last_activity_outcome",
			"sys.ui.last_record_rank", "sys.ui.content_filter", "sys.ui.has_gallery",
			"sys.ui.gallery_endings", "sys.ui.gallery_images", "sys.ui.gallery_music",
			"sys.ui.content_filter_available",
			"sys.scenes.%s.plays" % SC1, "sys.scenes.%s.last_selection" % SC2,
			"sys.chapters.%s.completed" % CH1, "sys.endings.good", "sys.endings.bad"]:
		if not _ok(vm.has(id), "falta %s" % id):
			return
		_ok(vm.is_read_only(id), "%s deveria ser somente leitura" % id)
	_ok(not vm.has("sys.endings.ugly"), "final não declarado")
	_eq(vm.read("sys.locale"), "pt-BR", "sys.locale começa no default_locale")
	_eq(vm.read("sys.ui.platform"), VNVariableManagerImpl.platform_name(), "sys.ui.platform")
	_eq(vm.read("sys.ui.has_gallery"), true, "sys.ui.has_gallery")
	_eq(vm.read("sys.ui.gallery_endings"), true, "seção endings")
	_eq(vm.read("sys.ui.gallery_images"), false, "seção images ausente")
	_eq(vm.read("sys.ui.last_record_rank"), 0, "inteiro no padrão")
	_eq(vm.get_definition("sys.save_modified").persistence, &"session", "sys.* é session")
	vm.store("sys.endings.good", true)
	_eq(vm.read("sys.endings.good"), true, "runtime grava sys.* por store")
	vm.store("sys.ui.last_record_rank", 2.0)
	_eq(vm.read("sys.ui.last_record_rank"), 2, "sys.* inteiro normalizado")
	vm.enter_chapter(CH1)
	vm.enter_scene(SC1)
	_eq(vm.read("sys.chapter.id"), CH1, "sys.chapter.id na entrada do capítulo")
	_eq(vm.read("sys.scene.id"), SC1, "sys.scene.id no início da cena")
	vm.exit_scene()
	_eq(vm.read("sys.scene.id"), "", "sys.scene.id vazia no ponto de seleção")
	vm.exit_chapter()
	_eq(vm.read("sys.chapter.id"), "", "sys.chapter.id vazia fora de capítulo")
	vm.store("sys.scenes.nova.plays", 1)
	_ok(vm.has("sys.scenes.nova.plays"), "store cria sys.* de entidade nova")


func test_sys_do_historico() -> void:
	var vm := _vm()
	var sched: FakeSceneScheduler = _mods(vm).scheduler
	_eq(vm.read("sys.selection_count"), 0, "selection_count do Scheduler")
	_eq(vm.read("sys.scenes.%s.last_selection" % SC1), -1, "last_selection -1 se nunca")
	sched.start_direct(SC1)
	sched.complete_scene(SC1)
	sched.complete_chapter(CH1)
	_eq(vm.read("sys.selection_count"), sched.selection_count(), "selection_count acompanha o histórico")
	_eq(vm.read("sys.scenes.%s.plays" % SC1), 1, "plays do histórico")
	_eq(vm.read("sys.scenes.%s.last_selection" % SC1), int(sched.get_history().scenes[SC1].last_selection), "last_selection do histórico")
	_eq(vm.read("sys.chapters.%s.completed" % CH1), true, "completed do histórico")
	# Sem Scheduler no registro, valem os valores gravados.
	_mods(vm).scheduler = null
	vm.store("sys.selection_count", 7)
	_eq(vm.read("sys.selection_count"), 7, "sem Scheduler usa o valor gravado")


func test_sys_novo_jogo() -> void:
	var vm := _vm()
	_mods(vm).scheduler = null
	vm.store("sys.selection_count", 4)
	vm.store("sys.scenes.%s.plays" % SC1, 2)
	vm.store("sys.endings.good", true)
	vm.store("sys.locale", "en")
	vm.store("sys.ui.has_save", true)
	vm.enter_chapter(CH1)
	vm.reset_game()
	_eq(vm.read("sys.selection_count"), 0, "progresso volta ao padrão")
	_eq(vm.read("sys.scenes.%s.plays" % SC1), 0, "plays volta ao padrão")
	_eq(vm.read("sys.chapter.id"), "", "sem capítulo depois do novo jogo")
	_eq(vm.read("sys.endings.good"), true, "finais vêm do perfil e ficam")
	_eq(vm.read("sys.locale"), "en", "idioma fica")
	_eq(vm.read("sys.ui.has_save"), true, "interface fica")


func test_store_recusa_invalidas() -> void:
	var vm := _vm()
	vm.store("global.nada", 1)
	_ok(not vm.has("global.nada"), "store não cria variável do conteúdo")
	vm.store("chapter.visits", 3)
	_eq(vm.read("chapter.visits", null), null, "store com escopo inativo é ignorado")
	_ok(vm.diagnostics.size() == 2, "dois erros registrados (veio %d)" % vm.diagnostics.size())
	vm.store("global.ratio", 2)
	_eq(vm.read("global.ratio"), 2.0, "store normaliza integer → number")


func test_integra_com_dubles() -> void:
	# O State Manager (dublê) é a única porta de escrita: write → store.
	var vm := _vm()
	var m := _mods(vm)
	var r := m.state.write(&"add", "global.money", 5)
	_ok(r.ok, "write pelo State Manager: %s" % r.message)
	_eq(vm.read("global.money"), 15, "valor gravado pelo State Manager")
	m.state.set_system_value("sys.ui.in_game", true)
	_eq(vm.read("sys.ui.in_game"), true, "set_system_value chega ao Variable Manager")
	var e := m.conditions.evaluate_conditions([{"variable": "global.money", "operator": "equals", "value": 15}])
	_ok(e.ok, "Condition Evaluator lê pelo registro")
	# O dublê do Save Manager monta e restaura o save com o módulo real.
	var save := m.saves.build_save()
	_eq(save.state.variables.get("global.money"), 15, "save_values no save")
	vm.store("global.money", 1)
	(m.engine as FakeNarrativeEngine).set_phase(VNPhase.SELECTION_POINT)
	_ok(m.saves.save(VNSaveManager.QUICK).ok, "save pelo dublê")
	vm.store("global.money", 2)
	_ok(m.saves.load_slot(VNSaveManager.QUICK).ok, "load pelo dublê")
	_eq(vm.read("global.money"), 1, "load_slot restaura pelo restore_save_values")
