@abstract
class_name VNAssets
extends VNModule
## VNAssets: resolve ids de asset do projeto em recursos do Godot.
##
## Todo módulo que desenha ou toca um asset do projeto pede por aqui: Stage,
## Audio Manager, UI Manager e o [code]VNAssetAPI[/code]/[code]VNAudioAPI[/code]
## do Runtime SDK. No jogo, o id vira o caminho [code]res://[/code] de
## [code]bundle.json → assets[/code] e o recurso vem do import do Godot. No
## Preview, o prefixo [code]res://vn_content/assets/[/code] é trocado por
## [code]assets_base[/code] e o recurso é criado dos bytes do arquivo do autor,
## aplicando as opções de [code]import[/code] de [code]assets.json[/code]
## (carregador de bytes, PP §1.3).
##
## O modo stream ([method resolve_id]) é aplicado aqui, no momento de
## desenhar ou tocar: [code]replace_with[/code] devolve a substituta e
## [code]hide[/code] devolve vazio (RT §5.5, Plugin SDK §5.6).
##
## Specs: RT §2, §5.5, §11; Preview Protocol §1.3, §3 ([code]preview.load[/code],
## troca [code]/assets/<id>[/code]); DM §10.1, §10.4. Tarefa: M4-07.


func module_id() -> StringName:
	return &"assets"


## O id existe no bundle.
@abstract func has_asset(asset_id: String) -> bool

## O id que vale no modo atual: o próprio, o de [code]censored.replace_with[/code]
## ou vazio para [code]censored.hide[/code] (RT §5.5).
@abstract func resolve_id(asset_id: String) -> String

## Caminho do asset depois da troca de base (no Preview, a URL ou o caminho
## do arquivo do autor). Vazio se o id não existe.
@abstract func resolve_path(asset_id: String) -> String

## O recurso ([Texture2D], [AudioStream], [Font]) do id **já resolvido pelo
## modo stream**; [code]null[/code] para [code]hide[/code] ou id inexistente.
## Fica em cache até [method invalidate].
@abstract func load_asset(asset_id: String) -> Resource

## Modo preview (PP §1.3): [param assets_base] é a URL do protocolo
## [code]vnpreview[/code] no painel ou a pasta [code]assets/[/code] na janela.
## Vazio volta ao modo normal ([code]res://[/code]).
@abstract func set_assets_base(assets_base: String) -> void

## Liga ou desliga o modo stream para [method resolve_id].
@abstract func set_content_filter(enabled: bool) -> void

## Descarta o recurso em cache (troca [code]/assets/<id>[/code] em
## [code]preview.reload[/code]). Sem id, descarta tudo.
@abstract func invalidate(asset_id: String = "") -> void
