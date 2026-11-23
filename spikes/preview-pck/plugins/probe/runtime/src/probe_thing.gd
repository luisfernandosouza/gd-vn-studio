# Classe com class_name dentro do pacote do plugin (prefixo do namespace, P011).
class_name ProbeThing
extends RefCounted

const VERSION := 1

var label := "probe"


static func version_text() -> String:
	return "v%d" % VERSION
