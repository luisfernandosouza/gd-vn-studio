extends VNSdkTest
## Plugin SDK §5.3: VNNarrativeAPI, VNVariableAPI e VNTransaction.


func _setup() -> Array:
	var b := FakePluginBridge.new()
	b.values = {
		"global.player_money": 30,
		"global.secret": "x",
		"global.flag": false,
		"plugin.fishing.total_caught": 2,
	}
	b.definitions = {"plugin.fishing.total_caught": {"id": "plugin.fishing.total_caught", "type": "integer", "default": 0}}
	var ctx := VNPluginContext.create(b, &"vnstudio.fishing", &"fishing")
	return [b, ctx.narrative]


func test_le_variavel_propria_sem_capacidade() -> void:
	var s := _setup()
	var b: FakePluginBridge = s[0]
	var n: VNNarrativeAPI = s[1]
	eq(n.variables.get_value("~total_caught", 0), 2, "atalho ~")
	eq(n.variables.get_value("plugin.fishing.total_caught"), 2, "id qualificado")
	check(n.variables.has("~total_caught"), "has próprio")
	eq(n.variables.get_definition("~total_caught").type, "integer", "get_definition")
	eq(b.denied.size(), 0, "nada recusado")


func test_leitura_sem_capacidade_devolve_fallback() -> void:
	var s := _setup()
	var b: FakePluginBridge = s[0]
	var n: VNNarrativeAPI = s[1]
	eq(n.variables.get_value("global.player_money", -1), -1, "fallback")
	eq(n.variables.has("global.player_money"), false, "has falso")
	eq(n.variables.get_definition("global.player_money"), {}, "definição vazia")
	eq(b.denied.size(), 3, "três recusas avisadas")
	eq(b.denied[0].capability, &"variables.read", "capacidade")


func test_leitura_com_capacidade_mas_sem_concessao() -> void:
	var s := _setup()
	var b: FakePluginBridge = s[0]
	var n: VNNarrativeAPI = s[1]
	b.capabilities = [&"variables.read"]
	b.readable = ["global.player_money"]
	eq(n.variables.get_value("global.player_money"), 30, "variável concedida")
	eq(n.variables.get_value("global.secret", "?"), "?", "variável não concedida")
	eq(b.denied.size(), 1, "uma recusa")


func test_escritas_viram_transacao_de_uma_operacao() -> void:
	var s := _setup()
	var b: FakePluginBridge = s[0]
	var n: VNNarrativeAPI = s[1]
	var r := n.variables.add_value("~total_caught", 3)
	check(r.ok, "add ok")
	eq(r.changes, [{"variable": "plugin.fishing.total_caught", "old": 2, "new": 5}] as Array[Dictionary], "changes")
	eq(b.commits[0].ops, [{"op": &"add", "variable": "plugin.fishing.total_caught", "value": 3}] as Array[Dictionary], "op enviada (inteiro continua inteiro)")
	n.variables.subtract_value("~total_caught", 1.5)
	eq(b.commits[1].ops[0].value, 1.5, "fração continua float")
	n.variables.set_value("~total_caught", 10)
	n.variables.reset("~total_caught")
	eq(b.values["plugin.fishing.total_caught"], 0, "reset volta ao default")
	eq(b.commits[3].ops[0].has("value"), false, "reset sem value")


func test_escrita_recusada_avisa_a_ponte() -> void:
	var s := _setup()
	var b: FakePluginBridge = s[0]
	var n: VNNarrativeAPI = s[1]
	var r := n.variables.set_value("global.player_money", 100)
	eq(r.ok, false, "não aplicada")
	eq(r.error, &"PERMISSION_DENIED", "erro")
	eq(b.denied[0].capability, &"variables.write", "capacidade avisada")
	eq(b.values["global.player_money"], 30, "valor intacto")
	var r2 := n.variables.toggle("global.nao_existe")
	eq(r2.error, &"VARIABLE_NOT_FOUND", "VARIABLE_NOT_FOUND antes de PERMISSION_DENIED (RT §6.2)")
	eq(b.denied.size(), 1, "não conta como recusa de permissão")


func test_sinal_changed_so_com_variaveis_legiveis() -> void:
	var s := _setup()
	var b: FakePluginBridge = s[0]
	var n: VNNarrativeAPI = s[1]
	var got: Array = []
	n.variables.changed.connect(func(c): got.append(c))
	b.state_changed.emit([
		{"variable": "global.player_money", "old": 30, "new": 130},
		{"variable": "plugin.fishing.total_caught", "old": 2, "new": 3},
	] as Array[Dictionary])
	eq(got.size(), 1, "um sinal")
	eq(got[0], [{"variable": "plugin.fishing.total_caught", "old": 2, "new": 3}] as Array[Dictionary], "só a variável própria")
	b.state_changed.emit([{"variable": "global.secret", "old": "x", "new": "y"}] as Array[Dictionary])
	eq(got.size(), 1, "nada visível, nenhum sinal")
	eq(b.denied.size(), 0, "filtro não conta como recusa")


func test_transacao_tudo_ou_nada() -> void:
	var s := _setup()
	var b: FakePluginBridge = s[0]
	var n: VNNarrativeAPI = s[1]
	b.capabilities = [&"transactions"]
	b.writable = ["global.player_money"]
	var tx := n.begin_transaction()
	tx.add("global.player_money", 100).add("~total_caught", 3)
	var r := tx.commit()
	check(r.ok, "commit ok")
	eq(b.values["global.player_money"], 130, "dinheiro")
	eq(b.values["plugin.fishing.total_caught"], 5, "peixes")
	eq(r.changes.size(), 2, "duas mudanças")
	eq(tx.commit().error, &"INVALID_STATE", "segundo commit recusado")
	tx.add("global.player_money", 1)
	eq(tx.pending_ops().size(), 2, "encerrada não aceita operações")

	var tx2 := n.begin_transaction()
	tx2.add("global.player_money", 1).set_value("global.secret", "y")
	var r2 := tx2.commit()
	eq(r2.error, &"PERMISSION_DENIED", "uma operação recusada")
	eq(b.values["global.player_money"], 130, "nada aplicado")


func test_transacao_expect_e_rollback() -> void:
	var s := _setup()
	var b: FakePluginBridge = s[0]
	var n: VNNarrativeAPI = s[1]
	b.capabilities = [&"transactions"]
	var tx := n.begin_transaction().toggle("~total_caught").expect("~total_caught", 2)
	eq(tx.pending_ops(), [{"op": &"toggle", "variable": "plugin.fishing.total_caught"}] as Array[Dictionary], "toggle sem value")
	tx.rollback()
	eq(tx.commit().error, &"INVALID_STATE", "rollback encerra")
	eq(b.commits.size(), 0, "nada enviado")
	var tx2 := n.begin_transaction().set_value("~total_caught", 9).expect("~total_caught", 7)
	eq(tx2.commit().error, &"CONFLICT", "expect não confere")
	eq(b.commits[0].expectations, [{"variable": "plugin.fishing.total_caught", "value": 7}] as Array[Dictionary], "expect qualificado")


func test_transacao_sem_capacidade() -> void:
	var s := _setup()
	var b: FakePluginBridge = s[0]
	var n: VNNarrativeAPI = s[1]
	var tx := n.begin_transaction()
	check(tx is VNTransaction, "existe mesmo sem capacidade")
	eq(b.denied[0].capability, &"transactions", "recusa avisada no begin")
	var r := tx.add("~total_caught", 1).commit()
	eq(r.error, &"PERMISSION_DENIED", "commit recusado")
	eq(b.commits.size(), 0, "nada enviado")


func test_escrita_fora_da_thread_principal() -> void:
	var s := _setup()
	var b: FakePluginBridge = s[0]
	var n: VNNarrativeAPI = s[1]
	var out: Array = []
	var t := Thread.new()
	t.start(func():
		out.append(n.variables.set_value("~total_caught", 1))
		out.append(n.variables.get_value("~total_caught", -7)))
	t.wait_to_finish()
	eq((out[0] as VNResult).error, &"WRONG_THREAD", "escrita recusada")
	eq(out[1], -7, "leitura devolve fallback")
	eq(b.commits.size(), 0, "nada enviado")
	eq(b.errors.size(), 2, "erros contados")
	eq(b.values["plugin.fishing.total_caught"], 2, "valor intacto")
