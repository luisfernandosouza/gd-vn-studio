class_name VNI18nAPI
extends VNPluginService
## Idioma do jogo e textos [code]runtime/[/code] do plugin (Plugin SDK §5.7). Não pede capacidade.

## O jogador trocou o idioma do jogo.
signal locale_changed(locale: String)

## Idioma atual do jogo, ex.: [code]"pt-BR"[/code].
var locale: String:
	get:
		return _bridge.get_locale()


func _init(bridge: VNPluginBridge = null, plugin_namespace: StringName = &"") -> void:
	super(bridge, plugin_namespace)
	# Sem referência forte para não criar ciclo ponte → serviço → ponte.
	var self_ref := weakref(self)
	_bridge.locale_changed.connect(func(new_locale: String) -> void:
		var api: Object = self_ref.get_ref()
		if api != null:
			api.locale_changed.emit(new_locale))


## Texto para o jogador. Procura [param key] ([code]runtime/…[/code]) na tradução do
## projeto, em [code]plugin_locales[/code] do idioma atual e do idioma-fonte, e por
## fim usa [param fallback]; depois interpola [param args] como o texto do projeto
## ([code]{nome}[/code], [code]{{[/code]/[code]}}[/code] literais, números pela tabela do
## idioma). O nome é [code]text[/code] e não [code]tr[/code] para não colidir com
## [code]Object.tr[/code].
func text(key: String, fallback: String, args: Dictionary = {}) -> String:
	if not key.begins_with("runtime/"):
		_bridge.write_log(&"warn", "i18n.text: a chave '%s' deveria começar com runtime/ (W016)" % key)
	var template := _bridge.lookup_text(_ns, key)
	if template.is_empty():
		template = fallback
	return _bridge.format_text(template, args)
