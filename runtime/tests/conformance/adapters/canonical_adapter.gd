extends VNCaseAdapter
## [code]canonical[/code] e [code]hmac[/code] (spec 08; BS §5.1, §8.3; RT §12.1): serializa
## [code]json[/code] com [VNCanonicalJson] e devolve [code]{text, hash}[/code], ou assina com a
## chave do caso (hex; ausente = chave de debug, RT §2.1) e devolve [code]{integrity}[/code].
## Tarefa: M2-10.


func kinds() -> PackedStringArray:
	return ["canonical", "hmac"]


func run(c: Dictionary) -> Dictionary:
	var parsed := VNCaseJson.parse(String(c.get("json", "")))
	if not parsed.ok:
		return result({"setup_error": parsed.error})
	if String(c.kind) == "canonical":
		return result({"text": VNCanonicalJson.stringify(parsed.value), "hash": VNCanonicalJson.hash_sri(parsed.value)})
	if not parsed.value is Dictionary:
		return result({"setup_error": "hmac espera um objeto"})
	var key := VNCanonicalJson.debug_key() if not c.has("key") else String(c.key).hex_decode()
	return result({"integrity": VNCanonicalJson.signature(parsed.value, key)})
