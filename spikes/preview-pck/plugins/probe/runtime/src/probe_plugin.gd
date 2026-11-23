# Plugin de prova do spike M4-02. Usa um class_name do próprio pacote como tipo, com .new(),
# constante e método estático, e herda uma classe do pacote principal (VNRuntimePlugin, do SDK).
# As linhas "#v2 " só valem no pacote v2 (tools/make_pck.py --variant v2), que acrescenta
# ProbeExtra, um class_name que não existia quando o motor abriu.
extends VNRuntimePlugin

const PanelScene := preload("res://vn_plugins/probe/runtime/scenes/probe_panel.tscn")


func describe() -> Dictionary:
	var thing: ProbeThing = ProbeThing.new()
	var out := {"thing_version": ProbeThing.VERSION, "static": ProbeThing.version_text(), "label": thing.label}
	#v2 var extra: ProbeExtra = ProbeExtra.new()
	#v2 out["extra"] = extra.hello()
	return out


func make_panel() -> ProbePanel:
	return PanelScene.instantiate() as ProbePanel
