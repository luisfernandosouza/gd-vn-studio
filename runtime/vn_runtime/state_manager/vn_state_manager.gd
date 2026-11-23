@abstract
class_name VNStateManager
extends VNModule
## State Manager (RT §1): única porta de escrita do estado narrativo.
##
## Narrative Engine (efeitos de nós), plugins (pelo Runtime SDK), ações
## [code]effects[/code] de telas e o Preview escrevem só por aqui; só daqui se
## escreve no Variable Manager. Toda escrita valida na ordem do RT §6.2
## ([constant VNErrors.WRITE_CHECK_ORDER]) e devolve [VNResult].
##
## Specs: RT §6.1 (escritor único, transações, expect), §6.2 (validação),
## §6.3 ([VNResult]), §6.4 (notificação), §9; DM §6.2 (efeitos, truncamento,
## on_fail); Plugin SDK §5.2–§5.3 (permissões, VNVariableAPI, VNTransaction).
## Vetores: [code]conformance/effects.json[/code]. Tarefa: M1-06.

## Emitido **uma vez** depois de cada operação ou transação aplicada, com
## todas as mudanças (RT §6.4). Mudanças não geram eventos no Event Bus.
## Cada item: [code]{ "variable": id, "old": v0, "new": v1 }[/code].
signal state_changed(changes: Array[Dictionary])

## Chamadores (verificação 6 do RT §6.2). Plugins usam [method plugin_caller].
const CALLER_CONTENT := &"content"   ## nós da cena (efeitos, escolhas, on_result)
const CALLER_UI := &"ui"             ## ações effects de telas (UI Spec §4)
const CALLER_PREVIEW := &"preview"   ## preview.set_variables (Preview Protocol §3)
const CALLER_RUNTIME := &"runtime"   ## o próprio runtime (sys.*, restauração de save)


func module_id() -> StringName:
	return &"state"


## Chamador de um plugin: [code]&"plugin:<namespace>"[/code].
static func plugin_caller(plugin_ns: StringName) -> StringName:
	return StringName("plugin:%s" % plugin_ns)


## Namespace do plugin de um chamador, ou [code]&""[/code] se não é plugin.
static func caller_plugin(caller: StringName) -> StringName:
	var s := String(caller)
	return StringName(s.substr(7)) if s.begins_with("plugin:") else &""


## Leitura com as verificações 1, 3, 5 e permissão de leitura (RT §6.2).
## Em falha, registra no log e devolve [param fallback] (Plugin SDK §5.2).
@abstract func read_value(id: String, fallback: Variant = null, caller: StringName = CALLER_CONTENT) -> Variant

## Uma operação isolada ([code]set[/code], [code]add[/code],
## [code]subtract[/code], [code]multiply[/code], [code]toggle[/code],
## [code]reset[/code]; DM §6.2). Equivale a uma transação de uma operação.
@abstract func write(op: StringName, id: String, value: Variant = null, caller: StringName = CALLER_CONTENT) -> VNResult

## Abre uma transação. Ela só valida e aplica em [method VNStateTransaction.commit].
func begin_transaction(caller: StringName = CALLER_CONTENT) -> VNStateTransaction:
	return VNStateTransaction.new(self, caller)

## Valida e aplica a transação, tudo ou nada (RT §6.1–§6.3). Em sucesso,
## emite [signal state_changed] e drena a fila do Event Bus (RT §7.2, "fim do commit").
@abstract func commit_transaction(tx: VNStateTransaction) -> VNResult

## Aplica uma lista de efeitos do conteúdo (DM §6.2) como uma transação:
## avalia cada [code]value[/code] pelo Condition Evaluator, com
## [param bindings] para [code]{"result": …}[/code] de [code]on_result[/code]
## (RT §5.3 passo 6), e cada efeito enxerga o resultado dos anteriores.
## [param extra] são operações a juntar na mesma transação (o
## [code]record[/code] de uma escolha, RT §5.2).
@abstract func apply_effects(effects: Array, bindings: Dictionary = {}, caller: StringName = CALLER_CONTENT, extra: Array[Dictionary] = []) -> VNResult

## Grava uma variável [code]sys.*[/code] mantida pelo runtime (DM §4.3).
## Só módulos do runtime chamam; não passa pelas verificações de conteúdo e
## não emite [signal state_changed] (as variáveis sys.* não são estado narrativo).
@abstract func set_system_value(id: String, value: Variant) -> void

## Marca o início e o fim de uma avaliação de condição: no meio dela, toda
## escrita falha com [code]INVALID_STATE[/code] (RT §6.2, verificação 2).
@abstract func set_evaluating(evaluating: bool) -> void
