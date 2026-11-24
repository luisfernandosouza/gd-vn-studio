extends VNSdkTest
## Plugin SDK §5.4 (EventAPI), §5.5 (SceneAPI) e §7 (eventos).


func _ctx(b: FakePluginBridge) -> VNPluginContext:
	return VNPluginContext.create(b, &"vnstudio.fishing", &"fishing")


func test_emite_no_proprio_namespace() -> void:
	var b := FakePluginBridge.new()
	b.capabilities = [&"events.emit"]
	b.emits = ["fishing.completed"]
	var ev := _ctx(b).narrative.events
	var r := ev.emit("fishing.completed", {"fish_count": 3, "score": 850})
	check(r.ok, "emit ok")
	eq(b.emitted, [{"name": "fishing.completed", "payload": {"fish_count": 3, "score": 850}}] as Array[Dictionary], "evento enviado")


func test_emit_recusado() -> void:
	var b := FakePluginBridge.new()
	b.emits = ["fishing.completed", "story.x"]
	var ev := _ctx(b).narrative.events
	eq(ev.emit("fishing.completed").error, &"PERMISSION_DENIED", "sem events.emit")
	b.capabilities = [&"events.emit"]
	eq(ev.emit("story.x").error, &"PERMISSION_DENIED", "fora do namespace (P009)")
	eq(ev.emit("fishing.nao_declarado").error, &"PERMISSION_DENIED", "não declarado em events.emits")
	eq(b.emitted.size(), 0, "nada enviado")
	eq(b.denied.size(), 3, "três recusas")


func test_on_off_e_callback() -> void:
	var b := FakePluginBridge.new()
	b.capabilities = [&"events.subscribe"]
	var ev := _ctx(b).narrative.events
	var got: Array = []
	var id := ev.on("story.*", func(name, payload, source): got.append([name, payload, source]))
	check(id >= 1, "id da assinatura")
	b.deliver("story.festival", {"a": 1}, "story")
	b.deliver("sys.scene_ended", {}, "sys")
	eq(got, [["story.festival", {"a": 1}, "story"]], "só casa com o padrão")
	ev.off(id)
	b.deliver("story.festival", {}, "story")
	eq(got.size(), 1, "off remove")
	ev.off(999)
	ev.off(0)


func test_on_sem_capacidade() -> void:
	var b := FakePluginBridge.new()
	var ev := _ctx(b).narrative.events
	eq(ev.on("sys.scene_ended", func(_n, _p, _s): pass), 0, "sys.* recusado")
	eq(b.denied[0].capability, &"events.subscribe", "capacidade")
	check(ev.on("fishing.*", func(_n, _p, _s): pass) >= 1, "próprio namespace é livre")
	b.capabilities = [&"events.subscribe"]
	b.subscribes = ["story.*"]
	eq(ev.on("other.*", func(_n, _p, _s): pass), 0, "fora de events.subscribes")
	eq(ev.on("story.*x", func(_n, _p, _s): pass), 0, "* só no fim")
	eq(b.errors.size(), 1, "padrão inválido é erro")


func test_pedido_de_cena() -> void:
	var b := FakePluginBridge.new()
	var sc := _ctx(b).scenes
	eq(sc.request("scene_fishing_master").error, &"PERMISSION_DENIED", "sem scenes.request")
	b.capabilities = [&"scenes.request"]
	eq(sc.request("scene_fishing_master").error, &"PERMISSION_DENIED", "fora de grants.scenes")
	b.scene_grants = ["scene_fishing_master"]
	check(sc.request("scene_fishing_master").ok, "concedida")
	eq(b.requests, ["scene_fishing_master"] as Array[String], "pedido repassado ao Scheduler")
	eq(b.denied.size(), 2, "duas recusas")


func test_padroes_de_evento() -> void:
	check(VNRuntimeSDK.is_valid_event_pattern("story.*"), "story.*")
	check(VNRuntimeSDK.is_valid_event_pattern("sys.scene_ended"), "nome exato")
	check(VNRuntimeSDK.is_valid_event_pattern("*"), "*")
	check(not VNRuntimeSDK.is_valid_event_pattern("story*"), "* depois de ponto")
	check(not VNRuntimeSDK.is_valid_event_pattern(""), "vazio")
	check(VNRuntimeSDK.event_matches("story.*", "story.a.b"), "prefixo")
	check(not VNRuntimeSDK.event_matches("story.a", "story.ab"), "exato")
