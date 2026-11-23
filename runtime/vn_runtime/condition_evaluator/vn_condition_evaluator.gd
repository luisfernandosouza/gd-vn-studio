@abstract
class_name VNConditionEvaluator
extends VNModule
## Condition Evaluator (RT §1): avalia condições e expressões de valor.
##
## É **puro**: não escreve estado, não emite eventos e não sorteia, exceto
## [code]random_int[/code] em [method evaluate_expression] com
## [param allow_random] (DM §6.1.1, T008). Lê variáveis do Variable Manager
## ([code]modules().variables[/code]) e os eventos desde a última seleção do
## Scheduler ([code]modules().scheduler.events_since_selection()[/code]).
##
## Specs: DM §5, §5.1–§5.3 (condições, operadores, curto-circuito), DM §6.1 e
## §6.1.1 (expressões e funções), RT §12.1 (números, intervalo de inteiros).
## Vetores: [code]conformance/expressions.json[/code], [code]conditions.json[/code].
## Tarefas: M1-02 (tipos), M1-03 (expressões), M1-04 (condições).


func module_id() -> StringName:
	return &"conditions"


## Avalia um campo [code]conditions[/code] (DM §5): uma lista vale "todas
## verdadeiras" (lista vazia é verdadeira) e um objeto é uma condição única.
## [param bindings] fornece valores locais, como [code]{ "result": payload }[/code]
## para [code]{"result": …}[/code] dentro de [code]value[/code].
## Variável inexistente: [code]ok = false[/code], erro [code]VARIABLE_NOT_FOUND[/code], valor [code]false[/code].
@abstract func evaluate_conditions(conditions: Variant, bindings: Dictionary = {}) -> VNEvalResult


## Avalia uma expressão de valor (DM §6.1): literal, [code]{"var"}[/code],
## [code]{"fn", "args"}[/code], [code]{"if", "then", "else"}[/code] ou
## [code]{"result"}[/code] (só com [param bindings] de [code]on_result[/code]).
## [param target_type] é o tipo da variável de destino, usado no padrão de
## [code]{"result"}[/code] ausente. [param allow_random] só é verdadeiro em
## efeitos e payloads de [code]emit[/code] (T008).
@abstract func evaluate_expression(expr: Variant, bindings: Dictionary = {}, target_type: StringName = &"", allow_random: bool = false) -> VNEvalResult


## Explica por que [param conditions] falham, sem efeitos colaterais: uma
## entrada por folha falsa, no formato [code]failed[/code] de
## [code]SchedulerEvaluation[/code] (RT §11, Preview Protocol §4.3):
## [code]{ path, variable, operator, expected, actual }[/code].
@abstract func explain_conditions(conditions: Variant) -> Array[Dictionary]
