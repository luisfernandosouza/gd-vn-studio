@abstract
class_name VNModule
extends RefCounted
## Base de todo módulo do runtime (RT §1).
##
## Cada módulo da tabela do RT §1 tem uma classe base abstrata nesta árvore
## (`vn_runtime/<módulo>/`), com assinaturas, sinais e documentação, e um dublê
## em `tests/fakes/<módulo>/`. Os módulos se encontram pelo registro
## [VNModules], que guarda uma referência forte a cada um; cada módulo guarda só
## uma referência fraca ao registro, para não formar ciclo de [RefCounted].
##
## Os módulos de apresentação (Stage, Audio, UI Manager, Plugin Host) também são
## [RefCounted]: eles recebem o nó onde desenham por [method attach], e por isso
## os módulos lógicos podem ser testados sem árvore de cena.

var _modules_ref: WeakRef = null


## Liga o módulo ao registro. Chamado por [method VNModules.bind_all].
func bind(modules: VNModules) -> void:
	_modules_ref = weakref(modules)


## O registro dos módulos, ou [code]null[/code] se o módulo não foi ligado.
func modules() -> VNModules:
	if _modules_ref == null:
		return null
	return _modules_ref.get_ref() as VNModules


## Nome estável do módulo, igual ao campo do [VNModules] (ex.: [code]&"state"[/code]).
@abstract func module_id() -> StringName


## Recebe o bundle já carregado e validado (RT §2, [code]bundle.schema.json[/code]).
## Cada módulo lê só a parte que é dele. Padrão: não faz nada.
func load_bundle(_bundle: Dictionary) -> void:
	pass


## Liga o módulo a um nó da árvore (módulos que desenham, tocam som ou hospedam
## plugins). Módulos lógicos ignoram. Padrão: não faz nada.
func attach(_parent: Node) -> void:
	pass


## Desfaz [method attach] e libera os nós criados. Padrão: não faz nada.
func detach() -> void:
	pass
