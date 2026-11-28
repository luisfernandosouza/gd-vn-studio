extends VNCaseAdapter
## [code]rng[/code] (spec 08; RT §12.2; DM §6.1.1): PCG32 reproduzível. Operações: [code]sequence[/code]
## (saídas de 32 bits e estado final), [code]random_int[/code], [code]activity_seed[/code] e
## [code]plugin_seed[/code]. Usa [VNPcg32] e [VNGameRng] direto: o RNG não é um módulo trocável.


func kinds() -> PackedStringArray:
	return ["rng"]


func run(c: Dictionary) -> Dictionary:
	match String(c.get("op", "")):
		"sequence":
			var r := VNPcg32.from_seed(String(c["seed"]))
			var values := []
			for i in int(c["count"]):
				values.append(r.next_u32())
			return result({"values": values, "state_after": r.state_hex()})
		"random_int":
			var r := VNPcg32.from_seed(String(c["seed"]))
			var values := []
			for i in int(c["count"]):
				values.append(r.random_int(int(c["min"]), int(c["max"])))
			return result({"values": values})
		"activity_seed":
			return result({"seed": VNGameRng.activity_seed(String(c["seed"]), int(c["selection_count"]), String(c["node"]), int(c["activity_index"]))})
		"plugin_seed":
			return result({"seed": VNGameRng.plugin_seed(String(c["seed"]), String(c["namespace"]))})
	return skip("operação de rng desconhecida: %s" % c.get("op"))
