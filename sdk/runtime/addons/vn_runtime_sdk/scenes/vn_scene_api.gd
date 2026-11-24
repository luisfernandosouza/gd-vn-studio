class_name VNSceneAPI
extends VNPluginService
## Pedidos de cena do plugin (Plugin SDK §5.5; RT §4.3).
##
## [method request] registra um [b]pedido[/b] para o próximo ponto de seleção,
## tratado como [code]end.then.scene[/code]: o Scheduler só o aceita se a cena
## for elegível ou [code]manual[/code]. Não interrompe a cena atual. O último
## pedido antes do ponto de seleção vence; pedidos do conteúdo têm precedência.


## Requer [code]scenes.request[/code] e a cena em [code]grants.scenes[/code].
func request(scene_id: String) -> VNResult:
	if not _check_thread("scenes.request"):
		return _wrong_thread("scenes.request")
	if not _bridge.has_capability(VNRuntimeSDK.CAP_SCENES_REQUEST):
		return _deny(VNRuntimeSDK.CAP_SCENES_REQUEST, "scenes.request(%s)" % scene_id)
	if not _bridge.can_request_scene(scene_id):
		return _deny(VNRuntimeSDK.CAP_SCENES_REQUEST, "scenes.request(%s)" % scene_id)
	return _bridge.request_scene(scene_id)
