extends VNCaseAdapter
## [code]flow[/code] (spec 08 §2.2, §4; RT §5.1–§5.5, §7.2): roda uma cena inteira e compara o traço.
##
## Precisa do Narrative Engine real e de todos os módulos que ele coordena, e o contrato do M0-07 não
## tem como iniciar uma cena solta; a montagem do traço entra com a integração do núcleo (M1-12), que
## troca os dublês pelos módulos reais. Até lá, os casos são pulados.


func kinds() -> PackedStringArray:
	return ["flow"]


func run(_c: Dictionary) -> Dictionary:
	var missing := require([&"engine", &"conditions", &"state", &"variables", &"events"])
	if not missing.is_empty():
		return missing
	return skip("traço de fluxo de cena: entra com a integração do núcleo (M1-12)")
