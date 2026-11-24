extends VNCaseAdapter
## Tipos de caso cujo módulo não tem contrato no M0-07: o executor não tem o que chamar, então os
## casos são pulados com a tarefa que vai ligá-los. Ao entregar o módulo, a tarefa cria o adaptador
## dela em [code]adapters/[/code] e tira o [code]kind[/code] desta lista.

const PENDING := {
	"text": "formatador de texto e interpolação sem contrato (M1-07)",
	"rng": "PCG32 reproduzível sem contrato (M1-08)",
	"record": "recordes de plugin: entram com o M3-06",
}


func kinds() -> PackedStringArray:
	return PackedStringArray(PENDING.keys())


func run(c: Dictionary) -> Dictionary:
	return skip(PENDING[String(c.get("kind", ""))])
