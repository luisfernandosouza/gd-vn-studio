@abstract
class_name VNCaseAdapter
extends RefCounted
## Adaptador de um ou mais [code]kind[/code] de caso de conformidade (spec 08 §2.2): monta o estado
## mínimo do caso, chama os módulos do runtime e devolve o resultado no formato de [code]expect[/code].
##
## Cada [code]kind[/code] tem um arquivo em [code]tests/conformance/adapters/[/code]. Um adaptador
## devolve [method skip] quando o módulo de que depende ainda não tem implementação real: o caso
## aparece como pulado, nunca como passado (aceite do M1-01). A tarefa que entrega um módulo sem
## contrato no M0-07 (formatador de texto, PCG32, JCS, recordes) liga o adaptador dela aqui.

## Módulos reais disponíveis (ver [VNCaseModules]).
var modules: VNCaseModules


## Os [code]kind[/code] que este adaptador executa.
@abstract func kinds() -> PackedStringArray


## Executa o caso. Devolve [code]{"result": <obtido>}[/code] ou [code]{"skip": <motivo>}[/code].
@abstract func run(c: Dictionary) -> Dictionary


static func result(v: Variant) -> Dictionary:
	return {"result": v}


static func skip(reason: String) -> Dictionary:
	return {"skip": reason}


## Pula se faltar implementação real de algum dos módulos [param ids]; senão devolve vazio.
func require(ids: Array) -> Dictionary:
	var missing := modules.missing(ids)
	return {} if missing == "" else skip("sem implementação real de " + missing)
