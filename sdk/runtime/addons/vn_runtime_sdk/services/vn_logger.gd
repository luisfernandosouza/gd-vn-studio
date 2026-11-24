class_name VNLogger
extends VNPluginService
## Log do plugin ([code]ctx.log[/code]). As linhas vão para o log do plugin no
## runtime e para o console do Preview, prefixadas pelo namespace.


func debug(message: String) -> void:
	_bridge.write_log(&"debug", message)


func info(message: String) -> void:
	_bridge.write_log(&"info", message)


func warn(message: String) -> void:
	_bridge.write_log(&"warn", message)


func error(message: String) -> void:
	_bridge.write_log(&"error", message)
