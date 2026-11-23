class_name VNFakeModules
extends RefCounted
## Monta um [VNModules] só com dublês, já ligados ao registro.
##
## Uso típico numa tarefa que implementa um módulo:
## [codeblock]
## var m := VNFakeModules.create()
## m.state = MyRealStateManager.new()   # o módulo em teste
## m.bind_all()
## [/codeblock]
## Os dublês ficam em [code]tests/fakes/<módulo>/[/code] e nunca são usados
## pelo código de [code]vn_runtime/[/code] (spec 09 §1.2: [code]tests/[/code]
## não entra em nenhum artefato).


static func create() -> VNModules:
	var m := VNModules.new()
	m.engine = FakeNarrativeEngine.new()
	m.scheduler = FakeSceneScheduler.new()
	m.conditions = FakeConditionEvaluator.new()
	m.state = FakeStateManager.new()
	m.variables = FakeVariableManager.new()
	m.events = FakeEventBus.new()
	m.plugins = FakePluginHost.new()
	m.saves = FakeSaveManager.new()
	m.storage = FakeStorage.new()
	m.stage = FakeStage.new()
	m.audio = FakeAudioManager.new()
	m.ui = FakeUIManager.new()
	m.assets = FakeAssets.new()
	m.bind_all()
	return m
