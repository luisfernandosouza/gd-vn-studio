class_name VNLayers
extends RefCounted
## Camadas de desenho (RT §1.1).
##
## O Stage e o UI Manager desenham em [CanvasLayer]s fixos, de baixo para cima.
## Um nó de uma camada nunca aparece acima de outra camada superior.

const BACKGROUND := 0        ## Cenário: background (imagem ou set, com hotspots cosméticos)
const CHARACTERS := 10       ## Personagens: sprites de show, na ordem de z e depois de entrada
const HOTSPOTS := 15         ## Áreas clicáveis de interact
const PLUGIN_OVERLAYS := 20  ## ui.overlay (Plugin SDK §5.6)
const TEXTBOX := 30          ## Caixa de fala, plaquinha de nome, escolhas
const HUD := 40              ## Tela hud (UI Spec §2)
const SCREENS := 50          ## Pilha de telas do UI Manager
const ACTIVITY := 60         ## Cena do minijogo, quando a atividade cobre a tela
const SYSTEM := 100          ## Confirmações, runtime/message/*, overlay de erro de debug

## Todas as camadas, de baixo para cima.
const ALL: Array[int] = [BACKGROUND, CHARACTERS, HOTSPOTS, PLUGIN_OVERLAYS, TEXTBOX, HUD, SCREENS, ACTIVITY, SYSTEM]

## Camadas que entram na miniatura do save: o jogo sem UI (RT §8.5).
const THUMBNAIL_MAX := PLUGIN_OVERLAYS


## Nome do nó CanvasLayer de cada camada, para depuração.
static func layer_name(layer: int) -> String:
	match layer:
		BACKGROUND: return "Background"
		CHARACTERS: return "Characters"
		HOTSPOTS: return "Hotspots"
		PLUGIN_OVERLAYS: return "PluginOverlays"
		TEXTBOX: return "Textbox"
		HUD: return "Hud"
		SCREENS: return "Screens"
		ACTIVITY: return "Activity"
		SYSTEM: return "System"
	return "Layer%d" % layer
