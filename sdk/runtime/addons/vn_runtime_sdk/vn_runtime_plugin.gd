class_name VNRuntimePlugin
extends Node
## Classe base do entrypoint de runtime de um plugin (Plugin SDK §5.1).
##
## O script de [code]entrypoints.runtime[/code] do manifesto estende esta classe e
## sobrescreve só os métodos que usa. O Plugin Host cria o nó, chama os métodos
## nesta ordem e nunca os chama de outra thread:
##
## [code]_vn_init[/code] (todos os plugins, em ordem topológica de dependências,
## empate pela ordem lexicográfica do id) → [code]_vn_ready[/code] (todos) →
## [code]_vn_game_started[/code] → … → [code]_vn_game_ended[/code] →
## [code]_vn_shutdown[/code].
##
## Ao carregar um save (RT §8.3): [code]_vn_game_ended()[/code] se havia jogo →
## [code]_vn_game_started(false)[/code] → [code]_vn_migrate_save_data[/code] (se
## preciso) → [code]_vn_load(data)[/code]. Sem dados do plugin no save,
## [code]_vn_load(null)[/code] é chamado mesmo assim e o plugin DEVE voltar ao
## estado inicial.


## Chamado uma vez ao carregar o plugin. Registrar ouvintes aqui.
func _vn_init(_ctx: VNPluginContext) -> void:
	pass


## Bundle narrativo e todos os plugins carregados.
func _vn_ready() -> void:
	pass


func _vn_game_started(_is_new_game: bool) -> void:
	pass


## Começa a atividade [param activity_id] (sem o namespace) com os
## [param params] já validados e com defaults (Plugin SDK §6).
func _vn_start_activity(_activity_id: StringName, _params: Dictionary, _handle: VNActivityHandle) -> void:
	pass


## A atividade foi encerrada de fora (pulo, timeout, saída do jogador). O handle
## já está inativo quando este método é chamado (Plugin SDK §6).
func _vn_cancel_activity(_handle: VNActivityHandle) -> void:
	pass


## Dados próprios para o save (requer [code]save.data[/code]; Plugin SDK §9).
## Só tipos JSON, de preferência menos de 256 KB.
func _vn_save() -> Variant:
	return {}


## Restaura os dados de [method _vn_save]; [param data] é [code]null[/code] se o
## save não tem dados do plugin.
func _vn_load(_data: Variant) -> void:
	pass


## Converte dados de save de [param from_version] para a versão atual
## ([code]save.data_version[/code]); chamado em cadeia antes de [method _vn_load].
func _vn_migrate_save_data(data: Variant, _from_version: int) -> Variant:
	return data


## Converte dados de perfil (requer [code]profile.data[/code]; Plugin SDK §9.1).
func _vn_migrate_profile_data(data: Variant, _from_version: int) -> Variant:
	return data


func _vn_game_ended() -> void:
	pass


func _vn_shutdown() -> void:
	pass
