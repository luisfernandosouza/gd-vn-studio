# Spike M4-02: plugins como .pck montados depois do boot, no painel (Web) e na janela (nativo).
#
# Não é o runtime do v1. Responde a mensagens JSON-RPC 2.0 (o mesmo formato do Preview Protocol,
# com métodos `spike.*` só deste spike):
#   spike.hello                         versão do motor e tempo desde o boot
#   spike.mount {path|url, replace}     monta um .pck com ProjectSettings.load_resource_pack
#   spike.probe {}                      carrega os plugins montados e confere os class_name
#   spike.reload {namespace, passes}    relê do pacote (já trocado) os scripts e cenas de um plugin
#   spike.fetch {url}                   lê bytes pelo fetch do navegador (como o VNAssets leria no painel)
#   spike.http {url}                    tenta o mesmo com o HTTPRequest do Godot
#
# No painel, a ponte é a do PP §1.1: o runtime cria `vnPreview.send(text)` e responde chamando
# `vnPreview.onmessage(text)`, que a página registrou antes de iniciar o motor.
# No nativo (`-- --spike-pck <dir>`), roda o roteiro sozinho e imprime o resultado em JSON.
extends Control

@onready var _status: Label = $Status
@onready var _overlays: Control = $Overlays

var _boot_usec := Time.get_ticks_usec()
var _bridge: JavaScriptObject = null
var _send_cb: JavaScriptObject = null
var _fetch_cb: JavaScriptObject = null
var _pending := {}          # id do fetch → resultado [tamanho, erro]
var _next_fetch := 0
var _mount_count := 0
var _log: PackedStringArray = []

signal fetch_done(id: int)


func _ready() -> void:
	_status.text = "Spike M4-02: %s" % Engine.get_version_info().string
	if OS.has_feature("web"):
		_install_bridge()
		await RenderingServer.frame_post_draw
		_notify("spike.ready", {"engine_ms": _since_boot(), "godot": Engine.get_version_info().string})
		return
	var args := OS.get_cmdline_user_args()
	var i := args.find("--spike-pck")
	if i >= 0 and i + 1 < args.size():
		await _run_native(args[i + 1])
		get_tree().quit()


func _since_boot() -> float:
	return (Time.get_ticks_usec() - _boot_usec) / 1000.0


# ---------------------------------------------------------------- ponte JS (painel)

func _install_bridge() -> void:
	var window := JavaScriptBridge.get_interface("window")
	_bridge = window.vnPreview
	if _bridge == null:
		_bridge = JavaScriptBridge.create_object("Object")
		window.vnPreview = _bridge
	_send_cb = JavaScriptBridge.create_callback(_on_js_send)
	_bridge.send = _send_cb
	_fetch_cb = JavaScriptBridge.create_callback(_on_js_fetch_done)
	JavaScriptBridge.eval("""
		window.__vnSpike = {
			bufs: {},
			fetch(url, id, cb) {
				fetch(url)
					.then((r) => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.arrayBuffer(); })
					.then((b) => { this.bufs[id] = b; cb(id, b.byteLength, ''); })
					.catch((e) => cb(id, -1, String(e)));
			},
			take(id) { const b = this.bufs[id]; delete this.bufs[id]; return b; },
		};
	""", true)


func _on_js_send(args: Array) -> void:
	var msg = JSON.parse_string(str(args[0]))
	if typeof(msg) != TYPE_DICTIONARY:
		return
	var result = await _dispatch(str(msg.get("method", "")), msg.get("params", {}))
	_reply(msg.get("id"), result)


func _reply(id, result: Dictionary) -> void:
	var text := JSON.stringify({"jsonrpc": "2.0", "id": id, "result": result})
	if _bridge != null and _bridge.onmessage != null:
		_bridge.onmessage(text)
	else:
		print(text)


func _notify(method: String, params: Dictionary) -> void:
	var text := JSON.stringify({"jsonrpc": "2.0", "method": method, "params": params})
	if _bridge != null and _bridge.onmessage != null:
		_bridge.onmessage(text)
	else:
		print(text)


func _on_js_fetch_done(args: Array) -> void:
	_pending[int(args[0])] = [int(args[1]), str(args[2])]
	fetch_done.emit(int(args[0]))


## Lê bytes por `fetch` no navegador e traz para o GDScript como PackedByteArray.
func _js_fetch(url: String) -> Dictionary:
	var id := _next_fetch
	_next_fetch += 1
	var t0 := Time.get_ticks_usec()
	JavaScriptBridge.get_interface("window").__vnSpike.fetch(url, id, _fetch_cb)
	while not _pending.has(id):
		await fetch_done
	var res: Array = _pending[id]
	_pending.erase(id)
	var fetch_ms := (Time.get_ticks_usec() - t0) / 1000.0
	if int(res[0]) < 0:
		return {"ok": false, "error": res[1], "fetch_ms": fetch_ms}
	var t1 := Time.get_ticks_usec()
	var bytes: PackedByteArray = JavaScriptBridge.eval("window.__vnSpike.take(%d)" % id, true)
	return {"ok": true, "bytes": bytes, "fetch_ms": fetch_ms, "to_gd_ms": (Time.get_ticks_usec() - t1) / 1000.0}


# ---------------------------------------------------------------- métodos

func _dispatch(method: String, params: Dictionary) -> Dictionary:
	match method:
		"spike.hello":
			return {"engine_ms": _since_boot(), "godot": Engine.get_version_info().string, "web": OS.has_feature("web")}
		"spike.mount":
			return await _mount(params)
		"spike.probe":
			return _probe()
		"spike.reload":
			return _reload_plugin(str(params.namespace), int(params.get("passes", 1)))
		"spike.fetch":
			var r := await _js_fetch(str(params.url))
			if r.ok:
				r["size"] = (r.bytes as PackedByteArray).size()
				r["sha256"] = _sha256(r.bytes)
				r.erase("bytes")
			return r
		"spike.http":
			return await _http(str(params.url))
	return {"error": "método desconhecido: " + method}


## Monta um .pck. No painel, o arquivo chega por fetch e vai para o MEMFS do Emscripten
## (/tmp, que não persiste: nada do Preview em user://, D25); na janela, abre direto do disco.
func _mount(params: Dictionary) -> Dictionary:
	var out := {}
	var path := str(params.get("path", ""))
	if params.has("url"):
		var r := await _js_fetch(str(params.url))
		if not r.ok:
			return {"ok": false, "error": r.error}
		out["fetch_ms"] = r.fetch_ms
		out["to_gd_ms"] = r.to_gd_ms
		out["size"] = (r.bytes as PackedByteArray).size()
		var t0 := Time.get_ticks_usec()
		DirAccess.make_dir_recursive_absolute("/tmp/vnpreview")
		# Nome novo a cada montagem: trocar o arquivo de um pacote já montado não é seguro.
		_mount_count += 1
		path = "/tmp/vnpreview/%s-%d.pck" % [str(params.get("name", "plugin")), _mount_count]
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return {"ok": false, "error": "não abriu %s: %s" % [path, error_string(FileAccess.get_open_error())]}
		f.store_buffer(r.bytes)
		f.close()
		out["write_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	var t1 := Time.get_ticks_usec()
	var ok := ProjectSettings.load_resource_pack(path, bool(params.get("replace", true)))
	out["mount_ms"] = (Time.get_ticks_usec() - t1) / 1000.0
	out["ok"] = ok
	out["path"] = path
	return out


## Carrega os plugins montados como o Plugin Host carregaria, sempre relendo do pacote
## (CACHE_MODE_REPLACE_DEEP; para GDScript isso não relê o arquivo, ver _reload_plugin), e confere os class_name.
func _probe() -> Dictionary:
	var out := {}
	var t0 := Time.get_ticks_usec()
	var names: Array = []
	for c in ProjectSettings.get_global_class_list():
		names.append(str(c["class"]))
	out["global_classes"] = names.filter(func(n): return n.begins_with("Probe") or n.begins_with("Fishing"))

	# 1. Plugin de prova: class_name do próprio pacote usado como tipo, com .new(), constante e
	#    método estático; e herança de uma classe do pacote principal (VNRuntimePlugin, do SDK).
	var probe := {}
	var probe_path := "res://vn_plugins/probe/runtime/src/probe_plugin.gd"
	var script: Script = ResourceLoader.load(probe_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP) if ResourceLoader.exists(probe_path) else null
	probe["loaded"] = script != null
	probe["can_instantiate"] = script != null and script.can_instantiate()
	if probe.can_instantiate:
		var plugin = script.new()
		probe["is_vn_runtime_plugin"] = plugin is VNRuntimePlugin
		probe["describe"] = plugin.describe()
		var panel: Node = plugin.make_panel()
		probe["panel_class"] = panel.get_script().get_global_name() if panel != null else ""
		if panel != null:
			_overlays.add_child(panel)
			panel.queue_free()
	out["probe"] = probe

	# 2. O plugin de pesca do exemplo (specs/examples/fishing-plugin), sem mudança: preload da cena,
	#    `var _game: FishingGame` e `as FishingGame`.
	var fishing := {}
	var fishing_path := "res://vn_plugins/fishing/runtime/src/fishing_plugin.gd"
	var fscript: Script = ResourceLoader.load(fishing_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP) if ResourceLoader.exists(fishing_path) else null
	fishing["loaded"] = fscript != null
	fishing["can_instantiate"] = fscript != null and fscript.can_instantiate()
	if fishing.can_instantiate:
		var p = fscript.new()
		var ctx := VNPluginContext.create(_overlays, {"rare_fish_chance": 0.1, "show_tutorial": false}, {}, {})
		p._vn_init(ctx)
		var handle := VNActivityHandle.new()
		p._vn_start_activity(&"fishing_game", {"difficulty": "normal", "duration_seconds": 30, "target_fish": 3}, handle)
		var game = p.get("_game")
		fishing["game_class"] = game.get_script().get_global_name() if game != null else ""
		fishing["game_is_control"] = game is Control
		if game != null:
			game.queue_free()
	out["fishing"] = fishing
	out["probe_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return out


## Recarga de um plugin depois de montar o pacote novo por cima (replace_files).
## ResourceLoader.load com CACHE_MODE_REPLACE(_DEEP) não relê um GDScript já carregado: o
## GDScriptCache devolve o que tem. Com CACHE_MODE_IGNORE, o cache relê o arquivo (.gd ou .gdc)
## do pacote e recompila o MESMO objeto Script, então as instâncias e os preload já feitos passam a
## ver o código novo. Um script que usa a constante de outro precisa ser recompilado depois dele,
## por isso `passes` = 2 refaz a lista.
func _reload_plugin(ns: String, passes: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var scripts: PackedStringArray = []
	var scenes: PackedStringArray = []
	_collect("res://vn_plugins/" + ns, scripts, scenes)
	var errors := 0
	for _i in passes:
		for path in scripts:
			var s: Script = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if s == null or not s.can_instantiate():
				errors += 1
	for path in scenes:
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	return {"scripts": scripts, "scenes": scenes, "errors": errors, "reload_ms": (Time.get_ticks_usec() - t0) / 1000.0}


## Lista os scripts e cenas de uma pasta do pacote. Num pacote exportado, os scripts aparecem como
## `x.gd.remap` (o código vai compilado em `x.gdc`) e as cenas como `x.tscn.remap`.
func _collect(dir: String, scripts: PackedStringArray, scenes: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		var name := f.trim_suffix(".remap")
		var path := dir.path_join(name)
		if name.ends_with(".gd") and not scripts.has(path):
			scripts.append(path)
		elif name.ends_with(".tscn") or name.ends_with(".scn"):
			if not scenes.has(path):
				scenes.append(path)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), scripts, scenes)


func _http(url: String) -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	var err := req.request(url)
	if err != OK:
		req.queue_free()
		return {"ok": false, "request_error": error_string(err)}
	var res: Array = await req.request_completed
	req.queue_free()
	return {"ok": res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200, "result": res[0], "code": res[1], "size": (res[3] as PackedByteArray).size()}


func _sha256(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()


# ---------------------------------------------------------------- roteiro nativo

## Mesmo roteiro que a bancada da página roda no painel, lendo os .pck direto do disco.
func _run_native(dir: String) -> void:
	var steps := []
	steps.append({"step": "hello", "result": await _dispatch("spike.hello", {})})
	steps.append({"step": "probe_before_mount", "result": _probe()})
	for name in ["fishing", "probe-v1"]:
		steps.append({"step": "mount " + name, "result": await _mount({"path": dir.path_join(name + ".pck")})})
	steps.append({"step": "probe_v1", "result": _probe()})
	steps.append({"step": "mount probe-v2", "result": await _mount({"path": dir.path_join("probe-v2.pck")})})
	steps.append({"step": "probe_v2_replace_deep", "result": _probe()})
	steps.append({"step": "reload probe 1 pass", "result": _reload_plugin("probe", 1)})
	steps.append({"step": "probe_v2_after_1_pass", "result": _probe()})
	steps.append({"step": "reload probe 2 passes", "result": _reload_plugin("probe", 2)})
	steps.append({"step": "probe_v2_after_2_passes", "result": _probe()})
	print("SPIKE_RESULT " + JSON.stringify(steps))
