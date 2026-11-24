class_name VNI18nAPI
extends VNPluginService
## Idioma do jogo e textos [code]runtime/[/code] do plugin (Plugin SDK §5.7).
## Assinaturas do Plugin SDK §5.6–§5.7; a implementação chega com a tarefa M3-03.
## Até lá o serviço é inerte: devolve o valor vazio de cada método.
## Por enquanto [method text] devolve o [code]fallback[/code] com os [code]args[/code] trocados.

signal locale_changed(locale: String)

var locale: String = "en"


func text(_key: String, fallback: String, args: Dictionary = {}) -> String:
	var out := fallback
	for k in args:
		out = out.replace("{%s}" % k, str(args[k]))
	return out
