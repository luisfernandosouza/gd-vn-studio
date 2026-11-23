class_name VNEvalResult
extends RefCounted
## Resultado de uma avaliação do Condition Evaluator.
##
## Condições valem [code]bool[/code]; expressões têm valor e tipo, porque o
## JSON não distingue [code]2[/code] de [code]2.0[/code] (spec 08 §2.1). Em erro
## de conteúdo (RT §9), [member ok] é falso, [member error] traz o código e a
## condição vale [code]false[/code].

var ok: bool = true
var error: StringName = &""     ## código de VNErrors, &"" quando ok
var message: String = ""
var value: Variant = null
var type: StringName = &""      ## &"boolean", &"integer", &"number", &"string" (enum avalia como string)


static func of(p_value: Variant, p_type: StringName) -> VNEvalResult:
	var r := VNEvalResult.new()
	r.value = p_value
	r.type = p_type
	return r


static func failure(p_error: StringName, p_message: String = "") -> VNEvalResult:
	var r := VNEvalResult.new()
	r.ok = false
	r.error = p_error
	r.message = p_message
	r.value = false
	r.type = &"boolean"
	return r
