class_name VNAssetsLoader
extends VNAssets
## O [VNAssets] do runtime: resolve ids de asset em recursos, no jogo e no Preview.
##
## [b]No jogo[/b] (sem [code]assets_base[/code]), o id vira o caminho
## [code]res://[/code] de [code]bundle.json → assets[/code] e o recurso vem do
## import do Godot ([method ResourceLoader.load]).
##
## [b]No Preview[/b] ([method set_assets_base]), o prefixo
## [code]res://vn_content/assets/[/code] é trocado por [code]assets_base[/code]
## na hora de ler, e o recurso é criado dos bytes do arquivo do autor pelo
## [VNAssetDecoder], com as opções de import do asset (PP §1.3, D18, D24). O
## bundle não é reescrito: o Preview e o build usam o mesmo [code]bundle.json[/code]
## e o mesmo [code]content_hash[/code] (RT §2). Três formas de base:
## [br]- URL ([code]vnpreview://localhost/project/assets/[/code],
##   [code]http://vnpreview.localhost/project/assets/[/code]): painel. Cada
##   segmento do resto do caminho é codificado (RFC 3986) e os bytes chegam
##   pelo [code]fetch[/code] da página ([VNAssetWebFetcher]), sem o cache do
##   navegador. A leitura é assíncrona: [method load_asset] devolve
##   [code]null[/code] enquanto o arquivo não chegou e emite
##   [signal asset_ready] quando chega; [method fetch_asset] espera.
## [br]- Caminho absoluto da pasta [code]assets/[/code] (janela): leitura direta,
##   síncrona, sem codificação; [code]\\[/code] do Windows vira [code]/[/code].
## [br]- [code]res://<pasta>/assets/[/code] ([code]--vn-bundle[/code], RT §2.1):
##   recursos importados pelo editor, como no jogo; um arquivo sem import é lido
##   pelos bytes.
##
## Os assets do preset ([code]res://vn_runtime/…[/code]) são sempre lidos como no jogo.
##
## [b]Cache.[/b] LRU limitado por memória ([member cache_limit_bytes], padrão
## 256 MiB, sempre ligado): uma textura de 1920 × 1080 ocupa 7,9 MiB sem
## compressão (spike M4-01). Um recurso ainda em uso fora do cache (numa
## textura da tela, num player de som) nunca é descartado.
##
## [b]Troca[/b] (PP §3, [code]/assets/<id>[/code] em [code]preview.reload[/code]):
## [method invalidate] descarta o id; se ele estava em uso, o arquivo novo é
## lido e [signal asset_changed] avisa quem desenha ou toca o asset (com o id
## próprio e com cada id cuja substituta do modo stream é ele) para pedir de
## novo por [method load_asset]. [method load_bundle] com um bundle novo
## descarta só os ids cuja entrada mudou.
##
## Specs: RT §2, §5.5, §11; PP §1.3, §3; BS §6.2; DM §10.1, §10.4. Tarefa: M4-07.

## Um asset pedido por [method load_asset] no modo assíncrono (painel) chegou;
## [method load_asset] agora o devolve.
signal asset_ready(asset_id: String)
## Não foi possível ler ou decodificar o asset ([param message] em linguagem simples).
signal asset_failed(asset_id: String, message: String)
## Há uma versão nova do asset (troca [code]/assets/<id>[/code]): quem o mostra
## deve pedir de novo por [method load_asset].
signal asset_changed(asset_id: String)

## Prefixo dos assets do projeto no bundle (RT §2, PP §1.3).
const PROJECT_PREFIX := "res://vn_content/assets/"
## Limite padrão do cache (spike M4-01: LRU de 16 fundos ≈ 134 MiB).
const DEFAULT_CACHE_LIMIT := 256 * 1024 * 1024

## Como os bytes do Preview são lidos.
enum BaseKind { NONE, RES, FILE, URL }

## Limite do cache em bytes (estimativa da memória do recurso); 0 = sem limite.
var cache_limit_bytes: int = DEFAULT_CACHE_LIMIT
## Leitor assíncrono do modo URL: um [VNAssetWebFetcher] no Web. Os testes
## trocam por um dublê com o mesmo formato ([code]start(url) -> int[/code] e
## o sinal [code]fetched(key, status, bytes)[/code]).
var fetcher: RefCounted = null

var _entries: Dictionary = {}       # id → entrada do bundle (Dictionary)
var _replaced_by: Dictionary = {}   # id da substituta → [ids que a usam no modo stream]
var _content_filter := false
var _base := ""
var _base_kind := BaseKind.NONE
var _decoder := VNAssetDecoder.new()

var _cache: Dictionary = {}         # id resolvido → { res, cost }
var _lru: Array[String] = []        # do menos para o mais recente
var _cache_bytes := 0
var _reload_from_disk: Dictionary = {}  # ids a reler com CACHE_MODE_REPLACE (modo res://)

var _pending: Dictionary = {}       # chave do fetcher → { id, gen, notify: Array[String], changed: bool }
var _pending_by_id: Dictionary = {} # id resolvido → chave
var _gen: Dictionary = {}           # id → geração (sobe a cada invalidate)
var _gen_all := 0
var _refs_baseline := -1

signal _settled(asset_id: String)


# --- Bundle e modos ----------------------------------------------------------

func load_bundle(bundle: Dictionary) -> void:
	var src: Dictionary = bundle.get("assets", {})
	var fresh := {}
	for id in src:
		var e: Variant = src[id]
		fresh[String(id)] = e.duplicate(true) if e is Dictionary else {"path": String(e)}
	# Recarga (preview.reload completo ou patch aplicado ao bundle): só sai do cache o que mudou.
	for id in _entries.keys():
		if not fresh.has(id) or fresh[id] != _entries[id]:
			_drop(id)
	_entries = fresh
	_replaced_by.clear()
	for id in _entries:
		var c: Variant = _entries[id].get("censored")
		if c is Dictionary and c.has("replace_with"):
			var to := String(c["replace_with"])
			if not _replaced_by.has(to):
				_replaced_by[to] = []
			_replaced_by[to].append(id)


func has_asset(asset_id: String) -> bool:
	return _entries.has(asset_id)


func resolve_id(asset_id: String) -> String:
	if not _content_filter:
		return asset_id
	var e: Dictionary = _entries.get(asset_id, {})
	var c: Variant = e.get("censored")
	if not (c is Dictionary):
		return asset_id
	if c.get("hide", false):
		return ""
	return String(c.get("replace_with", asset_id))


func resolve_path(asset_id: String) -> String:
	var e: Dictionary = _entries.get(asset_id, {})
	var path := String(e.get("path", ""))
	if path.is_empty() or _base_kind == BaseKind.NONE or not path.begins_with(PROJECT_PREFIX):
		return path
	var rest := path.substr(PROJECT_PREFIX.length())
	if _base_kind == BaseKind.URL:
		var enc := PackedStringArray()
		for seg in rest.split("/"):
			enc.append(seg.uri_encode())
		return _base + "/".join(enc)
	return _base + rest


func set_assets_base(assets_base: String) -> void:
	var base := assets_base.strip_edges()
	var kind := BaseKind.NONE
	if base.is_empty():
		kind = BaseKind.NONE
	elif base.begins_with("res://"):
		kind = BaseKind.RES
	elif base.contains("://"):
		kind = BaseKind.URL
	else:
		kind = BaseKind.FILE
		base = base.replace("\\", "/")
	if kind != BaseKind.NONE and not base.ends_with("/"):
		base += "/"
	if base == _base and kind == _base_kind:
		return
	_base = base
	_base_kind = kind
	invalidate()
	if kind == BaseKind.URL and fetcher == null and VNAssetWebFetcher.is_available():
		fetcher = VNAssetWebFetcher.new()


## A base atual, já normalizada (termina em [code]/[/code]); vazia fora do Preview.
func assets_base() -> String:
	return _base


func set_content_filter(enabled: bool) -> void:
	_content_filter = enabled


# --- Carga -------------------------------------------------------------------

func load_asset(asset_id: String) -> Resource:
	var id := resolve_id(asset_id)
	if id.is_empty() or not _entries.has(id):
		return null
	if _cache.has(id):
		_touch(id)
		return _cache[id].res
	var path := resolve_path(id)
	if _is_async(path):
		_start_fetch(id, asset_id, false)
		return null
	var res := _load_sync(id, path)
	if res != null:
		_store(id, res)
	return res


## Igual a [method load_asset], mas espera a leitura no modo assíncrono.
## [code]null[/code] para [code]hide[/code], id inexistente ou falha de leitura.
func fetch_asset(asset_id: String) -> Resource:
	var res := load_asset(asset_id)
	var id := resolve_id(asset_id)
	while res == null and _pending_by_id.has(id):
		var done: String = await _settled
		if done == id:
			res = _cache[id].res if _cache.has(id) else null
	return res


## Começa a ler os ids no modo assíncrono (por exemplo, os do próximo bloco de
## nós enquanto o jogador lê). Nos outros modos, carrega na hora.
func prefetch(asset_ids: PackedStringArray) -> void:
	for a in asset_ids:
		load_asset(a)


## O asset está em cache (ou nada a carregar, para [code]hide[/code]).
func is_loaded(asset_id: String) -> bool:
	var id := resolve_id(asset_id)
	return id.is_empty() or _cache.has(id)


## Bytes estimados do que está em cache.
func cache_bytes() -> int:
	return _cache_bytes


## Ids em cache, do menos para o mais recente.
func cached_ids() -> PackedStringArray:
	return PackedStringArray(_lru)


func invalidate(asset_id: String = "") -> void:
	if asset_id.is_empty():
		_gen_all += 1
		for id in _cache.keys():
			_reload_from_disk[id] = true
		_cache.clear()
		_lru.clear()
		_cache_bytes = 0
		for key in _pending.keys():
			_settle_pending(key)
		return
	_gen[asset_id] = int(_gen.get(asset_id, 0)) + 1
	var was_cached := _cache.has(asset_id)
	var in_use := was_cached and _in_use(asset_id)
	_drop(asset_id)
	_reload_from_disk[asset_id] = true
	if _pending_by_id.has(asset_id):
		# Leitura em andamento com o arquivo antigo: descarta e lê de novo.
		var key: int = _pending_by_id[asset_id]
		var notify: Array = _pending[key].notify
		_settle_pending(key)
		for n in notify:
			_start_fetch(asset_id, n, true)
		return
	if not in_use:
		return
	var path := resolve_path(asset_id)
	if _is_async(path):
		_start_fetch(asset_id, asset_id, true)
	else:
		_emit_changed(asset_id)


# --- Interno -----------------------------------------------------------------

func _is_async(path: String) -> bool:
	return _base_kind == BaseKind.URL and path.begins_with(_base)


func _load_sync(id: String, path: String) -> Resource:
	var e: Dictionary = _entries[id]
	var res: Resource = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var mode := ResourceLoader.CACHE_MODE_REPLACE if _reload_from_disk.has(id) else ResourceLoader.CACHE_MODE_REUSE
		res = ResourceLoader.load(path, "", mode)
		if res == null:
			_fail(id, "não foi possível carregar %s" % path)
	elif _base_kind == BaseKind.URL and path.contains("://") and not path.begins_with("res://"):
		_fail(id, "a URL %s só é lida no painel (runtime Web)" % path)
		return null
	else:
		res = _decode_file(id, path, e)
	_reload_from_disk.erase(id)
	if res == null:
		return null
	_apply_meta(res, e)
	return res


func _decode_file(id: String, path: String, e: Dictionary) -> Resource:
	var type := String(e.get("type", ""))
	if type == "video" and path.get_extension().to_lower() == "ogv":
		if not FileAccess.file_exists(path):
			_fail(id, "arquivo não encontrado: %s" % path)
			return null
		var v := VideoStreamTheora.new()
		v.file = path
		return v
	if not FileAccess.file_exists(path):
		_fail(id, "arquivo não encontrado: %s" % path)
		return null
	return _decode_bytes(id, FileAccess.get_file_as_bytes(path), path, e)


func _decode_bytes(id: String, bytes: PackedByteArray, path: String, e: Dictionary) -> Resource:
	var opts: Variant = e.get("import", {})
	var res := _decoder.decode(bytes, path, String(e.get("type", "")), opts if opts is Dictionary else {})
	if res == null:
		_fail(id, _decoder.last_error)
	return res


func _apply_meta(res: Resource, e: Dictionary) -> void:
	var ns: Variant = e.get("nine_slice")
	if ns is Array and ns.size() == 4:
		res.set_meta(VNAssetDecoder.META_NINE_SLICE, PackedInt32Array(ns.map(func(v): return int(v))))


func _start_fetch(id: String, requested_as: String, changed: bool) -> void:
	if _pending_by_id.has(id):
		var p: Dictionary = _pending[_pending_by_id[id]]
		if not p.notify.has(requested_as):
			p.notify.append(requested_as)
		p.changed = p.changed or changed
		return
	if fetcher == null:
		_fail(id, "o runtime não tem leitor para %s" % resolve_path(id))
		return
	if not fetcher.is_connected(&"fetched", _on_fetched):
		fetcher.connect(&"fetched", _on_fetched)
	var key: int = fetcher.start(resolve_path(id))
	_pending[key] = {"id": id, "gen": [_gen_all, int(_gen.get(id, 0))], "notify": [requested_as], "changed": changed}
	_pending_by_id[id] = key


func _on_fetched(key: int, status: int, bytes: PackedByteArray) -> void:
	if not _pending.has(key):
		return
	var p: Dictionary = _pending[key]
	var id: String = p.id
	_settle_pending(key, false)
	if p.gen != [_gen_all, int(_gen.get(id, 0))] or not _entries.has(id):
		_settled.emit(id)
		return  # descartado por invalidate; outra leitura já começou se o asset estava em uso
	if status != 200:
		_fail(id, "não foi possível ler %s (HTTP %d)" % [resolve_path(id), status])
		_settled.emit(id)
		return
	var e: Dictionary = _entries[id]
	var res := _decode_bytes(id, bytes, String(e.get("path", "")), e)
	if res != null:
		_apply_meta(res, e)
		_store(id, res)
		for n in p.notify:
			asset_ready.emit(n)
		if p.changed:
			_emit_changed(id)
	_settled.emit(id)


func _settle_pending(key: int, emit := true) -> void:
	var p: Dictionary = _pending[key]
	_pending.erase(key)
	if _pending_by_id.get(p.id) == key:
		_pending_by_id.erase(p.id)
	if emit:
		_settled.emit(p.id)


func _emit_changed(id: String) -> void:
	asset_changed.emit(id)
	for other in _replaced_by.get(id, []):
		asset_changed.emit(other)


func _store(id: String, res: Resource) -> void:
	_drop(id)
	var cost := _estimate_bytes(res)
	_cache[id] = {"res": res, "cost": cost}
	_lru.append(id)
	_cache_bytes += cost
	_evict()


func _touch(id: String) -> void:
	_lru.erase(id)
	_lru.append(id)


func _drop(id: String) -> void:
	if _cache.has(id):
		_cache_bytes -= int(_cache[id].cost)
		_cache.erase(id)
		_lru.erase(id)


# Descarta os menos recentes até caber no limite, pulando os que estão em uso
# fora do cache (contagem de referências > 1) e o que acabou de entrar.
func _evict() -> void:
	if cache_limit_bytes <= 0:
		return
	var i := 0
	while _cache_bytes > cache_limit_bytes and i < _lru.size() - 1:
		var id := _lru[i]
		if _in_use(id):
			i += 1
			continue
		_drop(id)


# O recurso tem referências fora do cache (uma textura na tela, um player de som).
# A contagem lida daqui inclui as do próprio acesso; a base é medida uma vez
# com um objeto guardado do mesmo jeito.
func _in_use(id: String) -> bool:
	if _refs_baseline < 0:
		var probe := {"x": {"res": RefCounted.new()}}
		_refs_baseline = _ref_count(probe, "x")
	return _ref_count(_cache, id) > _refs_baseline


static func _ref_count(d: Dictionary, id: String) -> int:
	return d[id].res.get_reference_count()


static func _estimate_bytes(res: Resource) -> int:
	if res is Texture2D:
		# RGBA8 sem compressão, como no Preview (spike M4-01: 7,9 MiB por fundo de 1920 × 1080).
		var n: int = res.get_width() * res.get_height() * 4
		return n * 4 / 3 if res.has_mipmaps() else n
	if res is AudioStreamWAV:
		return res.data.size()
	if res is AudioStreamMP3:
		return res.data.size()
	if res is AudioStreamOggVorbis and res.packet_sequence != null:
		var n := 0
		for page in res.packet_sequence.packet_data:
			for packet in page:
				n += packet.size()
		return n
	if res is FontFile:
		return res.data.size()
	return 4096


func _fail(id: String, msg: String) -> void:
	push_warning("VNAssets: %s: %s" % [id, msg])
	asset_failed.emit(id, msg)
